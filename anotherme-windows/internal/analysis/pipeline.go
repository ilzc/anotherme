package analysis

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/user/anotherme-cli/pkg/ai"
	"github.com/user/anotherme-cli/pkg/db"
	"github.com/user/anotherme-windows/internal/capture"

	_ "modernc.org/sqlite"
)

// AnalysisResult holds the structured output from AI screenshot analysis.
type AnalysisResult struct {
	AppName          string   `json:"app_name"`
	WindowTitle      string   `json:"window_title"`
	VisibleApps      []string `json:"visible_apps"`
	ActivityCategory string   `json:"activity_category"`
	Topics           []string `json:"topics"`
	ContentSummary   string   `json:"content_summary"`
	ExtractedText    struct {
		UserAuthored    string   `json:"user_authored"`
		UserExpressions []string `json:"user_expressions"`
		ReadingContent  string   `json:"reading_content"`
		CodeSnippets    string   `json:"code_snippets"`
		UIData          string   `json:"ui_data"`
	} `json:"extracted_text"`
	UserIntent      string `json:"user_intent"`
	EngagementLevel string `json:"engagement_level"`
}

// PipelineItem represents a unit of work for the analysis pipeline.
type PipelineItem struct {
	Screenshots []capture.ScreenshotResult
	AppName     string
	WindowTitle string
	CapturedAt  time.Time
}

// Pipeline manages the asynchronous screenshot analysis workflow.
// Screenshots are enqueued and processed sequentially with retry logic.
type Pipeline struct {
	aiClient   *ai.Client
	activityDB *sql.DB
	memoryDB   *sql.DB
	ownDBs     bool // true if Pipeline opened its own DB connections
	queue      chan *PipelineItem
	maxQueue   int
	running    bool
	stopCh     chan struct{}
	mu         sync.Mutex

	// Vision request fields (bypass ai.Client for multimodal)
	endpoint string
	apiKey   string
	model    string

	// retry configuration
	maxRetries int
	retryDelay time.Duration

	// stats
	processedCount int
	errorCount     int
}

// NewPipeline creates a new analysis Pipeline.
// It opens its own read-write connections to activity.sqlite and memory.sqlite
// under dbPath, so it is not limited by the CLI's read-only db.Manager.
func NewPipeline(aiClient *ai.Client, dbPath, endpoint, apiKey, model string) (*Pipeline, error) {
	activityDSN := fmt.Sprintf("file:%s?_journal_mode=WAL", filepath.Join(dbPath, "activity.sqlite"))
	activityDB, err := sql.Open("sqlite", activityDSN)
	if err != nil {
		return nil, fmt.Errorf("open activity.sqlite: %w", err)
	}
	if err := activityDB.Ping(); err != nil {
		activityDB.Close()
		return nil, fmt.Errorf("ping activity.sqlite: %w", err)
	}

	memoryDSN := fmt.Sprintf("file:%s?_journal_mode=WAL", filepath.Join(dbPath, "memory.sqlite"))
	memoryDB, err := sql.Open("sqlite", memoryDSN)
	if err != nil {
		activityDB.Close()
		return nil, fmt.Errorf("open memory.sqlite: %w", err)
	}
	if err := memoryDB.Ping(); err != nil {
		activityDB.Close()
		memoryDB.Close()
		return nil, fmt.Errorf("ping memory.sqlite: %w", err)
	}

	maxQueue := 20
	return &Pipeline{
		aiClient:   aiClient,
		activityDB: activityDB,
		memoryDB:   memoryDB,
		ownDBs:     true,
		queue:      make(chan *PipelineItem, maxQueue),
		maxQueue:   maxQueue,
		endpoint:   strings.TrimRight(endpoint, "/"),
		apiKey:     apiKey,
		model:      model,
		maxRetries: 3,
		retryDelay: 30 * time.Second,
	}, nil
}

// Start begins the pipeline processing goroutine.
func (p *Pipeline) Start() {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.running {
		return
	}
	p.running = true
	p.stopCh = make(chan struct{})

	go p.processLoop()
}

// Stop halts the pipeline processing goroutine and closes owned DB connections.
func (p *Pipeline) Stop() {
	p.mu.Lock()
	defer p.mu.Unlock()

	if !p.running {
		return
	}
	close(p.stopCh)
	p.running = false

	if p.ownDBs {
		if p.activityDB != nil {
			p.activityDB.Close()
		}
		if p.memoryDB != nil {
			p.memoryDB.Close()
		}
	}
}

// Enqueue adds an item to the analysis queue. Returns false if the queue is full.
func (p *Pipeline) Enqueue(item *PipelineItem) bool {
	select {
	case p.queue <- item:
		return true
	default:
		// Queue is full; drop oldest and enqueue new item.
		select {
		case <-p.queue:
			log.Println("[Pipeline] Queue full, dropping oldest item")
		default:
		}
		select {
		case p.queue <- item:
			return true
		default:
			return false
		}
	}
}

// QueueSize returns the current number of items waiting in the queue.
func (p *Pipeline) QueueSize() int {
	return len(p.queue)
}

// ProcessedCount returns the number of successfully processed items.
func (p *Pipeline) ProcessedCount() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.processedCount
}

// ErrorCount returns the number of failed processing attempts.
func (p *Pipeline) ErrorCount() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.errorCount
}

func (p *Pipeline) processLoop() {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[Pipeline] Recovered from panic: %v", r)
			// Restart the loop after recovery.
			p.mu.Lock()
			if p.running {
				go p.processLoop()
			}
			p.mu.Unlock()
		}
	}()

	for {
		select {
		case <-p.stopCh:
			return
		case item := <-p.queue:
			p.processItem(item)
		}
	}
}

func (p *Pipeline) processItem(item *PipelineItem) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[Pipeline] Recovered from panic in processItem: %v", r)
			p.mu.Lock()
			p.errorCount++
			p.mu.Unlock()
		}
	}()

	for _, screenshot := range item.Screenshots {
		result, err := p.analyzeWithRetry(screenshot, item)
		if err != nil {
			log.Printf("[Pipeline] Analysis failed after retries: %v", err)
			p.mu.Lock()
			p.errorCount++
			p.mu.Unlock()
			continue
		}

		// Sanitize the result.
		result = sanitizeResult(result)

		// Store the activity record.
		if err := p.storeActivityRecord(result, item, screenshot.DisplayIndex); err != nil {
			log.Printf("[Pipeline] Failed to store activity record: %v", err)
			p.mu.Lock()
			p.errorCount++
			p.mu.Unlock()
			continue
		}

		// Extract memories from the analysis.
		if candidate := ExtractMemory(result, item.CapturedAt); candidate != nil {
			if err := p.storeMemory(candidate); err != nil {
				log.Printf("[Pipeline] Failed to store memory: %v", err)
			}
		}

		p.mu.Lock()
		p.processedCount++
		p.mu.Unlock()
	}
}

func (p *Pipeline) analyzeWithRetry(screenshot capture.ScreenshotResult, item *PipelineItem) (*AnalysisResult, error) {
	var lastErr error

	for attempt := 0; attempt <= p.maxRetries; attempt++ {
		if attempt > 0 {
			select {
			case <-p.stopCh:
				return nil, fmt.Errorf("pipeline stopped during retry")
			case <-time.After(p.retryDelay):
			}
		}

		result, err := p.analyze(screenshot)
		if err == nil {
			return result, nil
		}
		lastErr = err
		log.Printf("[Pipeline] Analysis attempt %d failed: %v", attempt+1, err)
	}

	return nil, fmt.Errorf("all %d attempts failed: %w", p.maxRetries+1, lastErr)
}

func (p *Pipeline) analyze(screenshot capture.ScreenshotResult) (*AnalysisResult, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()

	content, err := p.sendVisionRequest(ctx, ScreenshotAnalysisSystemPrompt, []string{screenshot.Base64})
	if err != nil {
		return nil, fmt.Errorf("vision request: %w", err)
	}

	var result AnalysisResult
	if err := json.Unmarshal([]byte(content), &result); err != nil {
		return nil, fmt.Errorf("parse analysis result: %w", err)
	}

	return &result, nil
}

// sendVisionRequest makes a direct HTTP call to the AI endpoint with OpenAI
// vision format, bypassing ai.Client which only supports string content.
func (p *Pipeline) sendVisionRequest(ctx context.Context, systemPrompt string, base64Images []string) (string, error) {
	// Build user content parts with images.
	userContent := make([]map[string]interface{}, 0, len(base64Images)+1)
	for _, img := range base64Images {
		userContent = append(userContent, map[string]interface{}{
			"type": "image_url",
			"image_url": map[string]string{
				"url": "data:image/jpeg;base64," + img,
			},
		})
	}

	reqBody := map[string]interface{}{
		"model": p.model,
		"messages": []map[string]interface{}{
			{"role": "system", "content": systemPrompt},
			{"role": "user", "content": userContent},
		},
		"response_format": map[string]string{"type": "json_object"},
	}

	bodyBytes, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("marshal vision request: %w", err)
	}

	url := p.endpoint + "/chat/completions"
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(bodyBytes))
	if err != nil {
		return "", fmt.Errorf("create vision request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+p.apiKey)

	resp, err := http.DefaultClient.Do(httpReq)
	if err != nil {
		return "", fmt.Errorf("send vision request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read vision response: %w", err)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("vision API error (status %d): %s", resp.StatusCode, string(respBody))
	}

	var chatResp ai.ChatResponse
	if err := json.Unmarshal(respBody, &chatResp); err != nil {
		return "", fmt.Errorf("unmarshal vision response: %w", err)
	}

	if len(chatResp.Choices) == 0 {
		return "", fmt.Errorf("empty vision response")
	}

	return chatResp.Choices[0].Message.Content, nil
}

func sanitizeResult(result *AnalysisResult) *AnalysisResult {
	validCategories := map[string]bool{
		"work": true, "entertainment": true, "social": true, "learning": true,
		"finance": true, "creative": true, "system": true, "other": true,
	}
	if !validCategories[result.ActivityCategory] {
		result.ActivityCategory = "other"
	}

	if result.AppName == "" {
		result.AppName = "Unknown"
	}

	if len(result.Topics) > 8 {
		result.Topics = result.Topics[:8]
	}

	validEngagement := map[string]bool{
		"deep_focus": true, "active_work": true, "browsing": true, "idle": true,
	}
	if !validEngagement[result.EngagementLevel] {
		result.EngagementLevel = "active_work"
	}

	// Filter empty user expressions.
	var filtered []string
	for _, expr := range result.ExtractedText.UserExpressions {
		if expr != "" {
			filtered = append(filtered, expr)
		}
	}
	result.ExtractedText.UserExpressions = filtered

	return result
}

func (p *Pipeline) storeActivityRecord(result *AnalysisResult, item *PipelineItem, screenIndex int) error {
	topicsJSON, err := json.Marshal(result.Topics)
	if err != nil {
		topicsJSON = []byte("[]")
	}

	visibleAppsJSON, err := json.Marshal(result.VisibleApps)
	if err != nil {
		visibleAppsJSON = []byte("[]")
	}

	userExprsJSON, err := json.Marshal(result.ExtractedText.UserExpressions)
	if err != nil {
		userExprsJSON = []byte("[]")
	}

	// Combine extracted text fields for the legacy extractedText column.
	combinedText := result.ExtractedText.ReadingContent
	if result.ExtractedText.CodeSnippets != "" {
		combinedText += "\n" + result.ExtractedText.CodeSnippets
	}
	if result.ExtractedText.UIData != "" {
		combinedText += "\n" + result.ExtractedText.UIData
	}

	_, err = p.activityDB.Exec(`
		INSERT INTO activity_logs (
			id, timestamp, appName, windowTitle, extractedText, contentSummary,
			userIntent, activityCategory, topics, screenIndex, captureMode,
			analyzed, visibleApps, userAuthored, userExpressions, engagementLevel
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		uuid.New().String(),
		db.FormatGRDBDate(item.CapturedAt),
		result.AppName,
		result.WindowTitle,
		nilIfEmpty(combinedText),
		nilIfEmpty(result.ContentSummary),
		nilIfEmpty(result.UserIntent),
		result.ActivityCategory,
		string(topicsJSON),
		screenIndex,
		"interval", // capture mode
		0,          // not yet analyzed by modeling
		string(visibleAppsJSON),
		nilIfEmpty(result.ExtractedText.UserAuthored),
		string(userExprsJSON),
		nilIfEmpty(result.EngagementLevel),
	)
	return err
}

func (p *Pipeline) storeMemory(candidate *MemoryCandidate) error {
	keywordsJSON, err := json.Marshal(candidate.Keywords)
	if err != nil {
		keywordsJSON = []byte("[]")
	}

	_, err = p.memoryDB.Exec(`
		INSERT INTO memories (id, content, category, keywords, importance, accessCount, pinned, sourceType, createdAt, lastAccessedAt)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		uuid.New().String(),
		candidate.Content,
		candidate.Category,
		string(keywordsJSON),
		candidate.Importance,
		0,     // accessCount
		false, // pinned
		candidate.SourceType,
		db.FormatGRDBDate(time.Now()),
		db.FormatGRDBDate(time.Now()),
	)
	return err
}

func nilIfEmpty(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

