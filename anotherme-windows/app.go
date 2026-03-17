package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/user/anotherme-cli/pkg/agent"
	"github.com/user/anotherme-cli/pkg/ai"
	"github.com/user/anotherme-cli/pkg/config"
	"github.com/user/anotherme-cli/pkg/db"
	"github.com/user/anotherme-windows/internal/analysis"
	"github.com/user/anotherme-windows/internal/capture"
	"github.com/user/anotherme-windows/internal/monitor"
	wailsRuntime "github.com/wailsapp/wails/v2/pkg/runtime"
)

// App is the main application struct bound to the Wails frontend.
type App struct {
	ctx context.Context

	// Services
	dbMgr         *db.Manager
	agentService  *agent.Service
	chatClient    *ai.Client
	routerClient  *ai.Client

	// Configuration
	cfg     *config.Config
	cfgPath string

	// Capture & analysis
	captureStatus    CaptureStatus
	captureMu        sync.RWMutex
	captureService   *capture.Service
	analysisPipeline *analysis.Pipeline
	modelingEngine   *analysis.ModelingEngine
	consolidator     *analysis.MemoryConsolidator

	// Monitors (need references for start/stop)
	inputMon    *monitor.InputMonitor
	screenState *monitor.ScreenStateMonitor
}

// NewApp creates a new App instance.
func NewApp() *App {
	return &App{}
}

// startup is called when the app starts. The context is saved
// so we can call the runtime methods.
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx

	// Load configuration
	a.cfgPath = config.DefaultConfigPath()
	a.cfg = config.LoadOrDefault()

	// Initialize database manager
	var err error
	a.dbMgr, err = db.NewManager(a.cfg.DBPath)
	if err != nil {
		// Log error but don't crash - user may need to configure DB path
		fmt.Printf("Warning: could not open databases: %v\n", err)
		return
	}

	// Initialize AI clients
	a.initAIClients()

	// Initialize agent service
	if a.dbMgr != nil && a.chatClient != nil {
		a.agentService = agent.NewService(a.dbMgr, a.cfg.CacheDir, a.cfg.ResponseLanguage())
	}

	// Initialize capture & analysis components
	a.initCaptureAndAnalysis()
}

// shutdown is called when the app is closing.
func (a *App) shutdown(ctx context.Context) {
	// Stop all capture and analysis components.
	if a.captureService != nil {
		a.captureService.Stop()
	}
	if a.analysisPipeline != nil {
		a.analysisPipeline.Stop()
	}
	if a.modelingEngine != nil {
		a.modelingEngine.Stop()
	}
	if a.consolidator != nil {
		a.consolidator.Stop()
	}

	// Stop monitors.
	if a.screenState != nil {
		a.screenState.Stop()
	}
	if a.inputMon != nil {
		a.inputMon.Stop()
	}

	a.captureMu.Lock()
	a.captureStatus.Running = false
	a.captureMu.Unlock()

	// Close database connections
	if a.dbMgr != nil {
		a.dbMgr.Close()
	}
}

// initAIClients sets up AI clients from configuration.
func (a *App) initAIClients() {
	chatProviders := config.GetFunctionProviders(a.cfg, "chat")
	routerProviders := config.GetFunctionProviders(a.cfg, "router")

	// Fall back to first provider if function-specific config is missing
	if len(chatProviders) == 0 && len(a.cfg.Providers) > 0 {
		chatProviders = []config.Provider{a.cfg.Providers[0]}
	}
	if len(routerProviders) == 0 {
		routerProviders = chatProviders
	}

	if len(chatProviders) > 0 {
		p := chatProviders[0]
		a.chatClient = ai.NewClient(p.Endpoint, p.APIKey, p.Model)
	}
	if len(routerProviders) > 0 {
		p := routerProviders[0]
		a.routerClient = ai.NewClient(p.Endpoint, p.APIKey, p.Model)
	}
}

// initCaptureAndAnalysis creates and wires the capture, analysis, modeling,
// and consolidation components. Errors are logged but do not prevent startup.
func (a *App) initCaptureAndAnalysis() {
	if a.dbMgr == nil {
		return
	}

	dbPath := a.dbMgr.DBPath()

	// --- Capture stack ---
	capturer := capture.NewCapturer()
	dedup := capture.NewDeduplicator()
	windowTracker := monitor.NewWindowTracker()
	a.inputMon = monitor.NewInputMonitor()
	a.screenState = monitor.NewScreenStateMonitor(a.inputMon)
	securityFilter := monitor.NewSecurityFilter()

	// Start monitors so screen state detection works.
	if err := a.inputMon.Start(); err != nil {
		log.Printf("[App] Failed to start input monitor: %v", err)
	}
	if err := a.screenState.Start(); err != nil {
		log.Printf("[App] Failed to start screen state monitor: %v", err)
	}

	a.captureService = capture.NewService(capturer, dedup, windowTracker, a.screenState, securityFilter)

	// --- Analysis pipeline ---
	// Use the screenshot_analysis provider if configured, otherwise fall back to chat provider.
	ssProviders := config.GetFunctionProviders(a.cfg, "screenshot_analysis")
	if len(ssProviders) == 0 {
		ssProviders = config.GetFunctionProviders(a.cfg, "chat")
	}
	if len(ssProviders) == 0 && len(a.cfg.Providers) > 0 {
		ssProviders = []config.Provider{a.cfg.Providers[0]}
	}

	if len(ssProviders) > 0 {
		p := ssProviders[0]
		aiClientForPipeline := ai.NewClient(p.Endpoint, p.APIKey, p.Model)

		pipeline, err := analysis.NewPipeline(aiClientForPipeline, dbPath, p.Endpoint, p.APIKey, p.Model)
		if err != nil {
			log.Printf("[App] Failed to create analysis pipeline: %v", err)
		} else {
			a.analysisPipeline = pipeline
		}
	}

	// Wire capture -> analysis: convert CaptureResult to PipelineItem.
	if a.analysisPipeline != nil {
		a.captureService.SetOnCapture(func(result *capture.CaptureResult) {
			item := &analysis.PipelineItem{
				Screenshots: result.Screenshots,
				AppName:     result.AppName,
				WindowTitle: result.WindowTitle,
				CapturedAt:  result.CapturedAt,
			}
			a.analysisPipeline.Enqueue(item)
		})
	}

	// --- Modeling engine ---
	if a.chatClient != nil {
		engine, err := analysis.NewModelingEngine(a.chatClient, a.dbMgr, a.cfg.ResponseLanguage())
		if err != nil {
			log.Printf("[App] Failed to create modeling engine: %v", err)
		} else {
			a.modelingEngine = engine
		}
	}

	// --- Memory consolidator ---
	if a.chatClient != nil {
		consolidator, err := analysis.NewMemoryConsolidator(a.chatClient, dbPath, a.cfg.ResponseLanguage())
		if err != nil {
			log.Printf("[App] Failed to create memory consolidator: %v", err)
		} else {
			a.consolidator = consolidator
		}
	}
}

// RunModelingNow triggers an immediate personality modeling analysis run.
func (a *App) RunModelingNow() error {
	if a.modelingEngine == nil {
		return fmt.Errorf("modeling engine not initialized")
	}
	return a.modelingEngine.RunNow()
}

// ─── Dashboard ──────────────────────────────────────────────────────────────

// GetDashboardStats returns summary statistics for the dashboard.
func (a *App) GetDashboardStats() (*DashboardStats, error) {
	if a.dbMgr == nil {
		return nil, fmt.Errorf("database not initialized")
	}

	stats := &DashboardStats{
		TraitsPerLayer: make(map[int]int),
	}

	// Count activities
	if actDB := a.dbMgr.ActivityDB(); actDB != nil {
		count, err := db.CountActivities(actDB)
		if err == nil {
			stats.TotalActivities = count
		}
		// Today's activities
		today := time.Date(time.Now().Year(), time.Now().Month(), time.Now().Day(), 0, 0, 0, 0, time.Now().Location())
		var todayCount int
		if err := actDB.QueryRow("SELECT COUNT(*) FROM activity_logs WHERE timestamp >= ?", db.FormatGRDBDate(today)).Scan(&todayCount); err == nil {
			stats.TodayActivities = todayCount
		}
		// Latest capture
		latest, err := db.LatestActivity(actDB)
		if err == nil && latest != nil {
			stats.LatestCapture = &latest.Timestamp
		}
	}

	// Count memories
	if memDB := a.dbMgr.MemoryDB(); memDB != nil {
		count, err := db.CountMemories(memDB)
		if err == nil {
			stats.TotalMemories = count
		}
	}

	// Count traits per layer
	for i := 1; i <= 5; i++ {
		if layerDB := a.dbMgr.LayerDB(i); layerDB != nil {
			count, err := db.CountTraits(layerDB, i)
			if err == nil {
				stats.TraitsPerLayer[i] = count
				stats.TotalTraits += count
			}
		}
	}

	// Count insights
	if insightDB := a.dbMgr.InsightDB(); insightDB != nil {
		count, err := db.CountInsights(insightDB)
		if err == nil {
			stats.TotalInsights = count
		}
	}

	// Count chat sessions
	if chatDB := a.dbMgr.ChatDB(); chatDB != nil {
		var count int
		if err := chatDB.QueryRow("SELECT COUNT(*) FROM chat_sessions").Scan(&count); err == nil {
			stats.TotalChatSessions = count
		}
	}

	a.captureMu.RLock()
	stats.CaptureRunning = a.captureStatus.Running
	a.captureMu.RUnlock()

	return stats, nil
}

// GetTodayActivities returns recent activities from today.
func (a *App) GetTodayActivities(limit int) ([]db.ActivityRecord, error) {
	if a.dbMgr == nil {
		return nil, fmt.Errorf("database not initialized")
	}
	actDB := a.dbMgr.ActivityDB()
	if actDB == nil {
		return nil, fmt.Errorf("activity database not available")
	}
	today := time.Date(time.Now().Year(), time.Now().Month(), time.Now().Day(), 0, 0, 0, 0, time.Now().Location())
	return db.FetchActivities(actDB, today, limit)
}

// ─── Capture Control ────────────────────────────────────────────────────────

// StartCapture begins screen capture and all associated analysis services.
func (a *App) StartCapture() error {
	a.captureMu.Lock()
	defer a.captureMu.Unlock()

	if a.captureStatus.Running {
		return fmt.Errorf("capture is already running")
	}

	// Start analysis pipeline first so it is ready to receive items.
	if a.analysisPipeline != nil {
		a.analysisPipeline.Start()
	}

	// Start capture service.
	if a.captureService != nil {
		if err := a.captureService.Start(); err != nil {
			log.Printf("[App] Failed to start capture service: %v", err)
			return fmt.Errorf("start capture: %w", err)
		}
	}

	// Start modeling engine.
	if a.modelingEngine != nil {
		a.modelingEngine.Start()
	}

	// Start memory consolidator.
	if a.consolidator != nil {
		a.consolidator.Start()
	}

	now := time.Now()
	a.captureStatus = CaptureStatus{
		Running:   true,
		StartedAt: &now,
	}
	return nil
}

// StopCapture stops screen capture and all associated analysis services.
func (a *App) StopCapture() {
	a.captureMu.Lock()
	defer a.captureMu.Unlock()

	if a.captureService != nil {
		a.captureService.Stop()
	}
	if a.analysisPipeline != nil {
		a.analysisPipeline.Stop()
	}
	if a.modelingEngine != nil {
		a.modelingEngine.Stop()
	}
	if a.consolidator != nil {
		a.consolidator.Stop()
	}

	a.captureStatus.Running = false
}

// GetCaptureStatus returns the current capture state.
func (a *App) GetCaptureStatus() CaptureStatus {
	a.captureMu.RLock()
	defer a.captureMu.RUnlock()
	return a.captureStatus
}

// ─── Chat ───────────────────────────────────────────────────────────────────

// GetChatSessions returns recent chat sessions.
func (a *App) GetChatSessions(limit int) ([]db.ChatSession, error) {
	if a.dbMgr == nil {
		return nil, fmt.Errorf("database not initialized")
	}
	chatDB := a.dbMgr.ChatDB()
	if chatDB == nil {
		return nil, fmt.Errorf("chat database not available")
	}
	return db.FetchRecentSessions(chatDB, limit)
}

// CreateChatSession creates a new chat session.
func (a *App) CreateChatSession() (*db.ChatSession, error) {
	if a.dbMgr == nil {
		return nil, fmt.Errorf("database not initialized")
	}
	chatDB := a.dbMgr.ChatDB()
	if chatDB == nil {
		return nil, fmt.Errorf("chat database not available")
	}
	session := db.ChatSession{
		ID:        uuid.New().String(),
		CreatedAt: time.Now(),
		Title:     "New Chat",
	}
	if err := db.CreateSession(chatDB, session); err != nil {
		return nil, fmt.Errorf("create session: %w", err)
	}
	return &session, nil
}

// GetSessionMessages returns all messages in a chat session.
func (a *App) GetSessionMessages(sessionID string) ([]db.ChatMessage, error) {
	if a.dbMgr == nil {
		return nil, fmt.Errorf("database not initialized")
	}
	chatDB := a.dbMgr.ChatDB()
	if chatDB == nil {
		return nil, fmt.Errorf("chat database not available")
	}
	return db.FetchSessionMessages(chatDB, sessionID)
}

// SendChatMessage sends a user message and returns the agent's reply.
// Internally uses streaming to get the response.
func (a *App) SendChatMessage(sessionID, text string) (*db.ChatMessage, error) {
	result, err := a.SendChatMessageStream(sessionID, text)
	if err != nil {
		return nil, err
	}

	// Return as a ChatMessage for backward compatibility
	msg := &db.ChatMessage{
		ID:        result.MessageID,
		SessionID: result.SessionID,
		Timestamp: time.Now(),
		Role:      "agent",
		Content:   result.Content,
	}
	return msg, nil
}

// SendChatMessageStream sends a message and streams the response via events.
// Returns the complete response after streaming finishes.
func (a *App) SendChatMessageStream(sessionID, text string) (*ChatStreamResult, error) {
	if a.agentService == nil {
		return nil, fmt.Errorf("agent service not initialized (check AI configuration)")
	}
	if a.chatClient == nil || a.routerClient == nil {
		return nil, fmt.Errorf("AI clients not configured")
	}

	ctx := a.ctx

	// Accumulate the full response from streaming chunks
	var accumulated strings.Builder

	callback := func(chunk string) {
		accumulated.WriteString(chunk)
		wailsRuntime.EventsEmit(a.ctx, "chat:chunk", chunk)
	}

	err := a.agentService.SendMessageStream(ctx, a.chatClient, a.routerClient, text, sessionID, callback)
	if err != nil {
		wailsRuntime.EventsEmit(a.ctx, "chat:error", err.Error())
		return nil, fmt.Errorf("stream message: %w", err)
	}

	// Fetch the saved agent message ID from DB
	messageID := uuid.New().String()
	messages, err := db.FetchSessionMessages(a.dbMgr.ChatDB(), sessionID)
	if err == nil && len(messages) > 0 {
		lastMsg := messages[len(messages)-1]
		messageID = lastMsg.ID
	}

	result := &ChatStreamResult{
		SessionID: sessionID,
		MessageID: messageID,
		Content:   accumulated.String(),
	}
	wailsRuntime.EventsEmit(a.ctx, "chat:done", result)

	return result, nil
}

// ─── Personality ────────────────────────────────────────────────────────────

// GetLayerTraits returns traits for a specific personality layer (1-5).
func (a *App) GetLayerTraits(layer int) ([]db.Trait, error) {
	if a.dbMgr == nil {
		return nil, fmt.Errorf("database not initialized")
	}
	if layer < 1 || layer > 5 {
		return nil, fmt.Errorf("layer must be between 1 and 5")
	}
	layerDB := a.dbMgr.LayerDB(layer)
	if layerDB == nil {
		return nil, fmt.Errorf("layer %d database not available", layer)
	}
	return db.FetchTraits(layerDB, layer)
}

// GetAllLayerTraits returns traits from all 5 personality layers.
func (a *App) GetAllLayerTraits() (map[int][]db.Trait, error) {
	if a.dbMgr == nil {
		return nil, fmt.Errorf("database not initialized")
	}
	result := make(map[int][]db.Trait)
	for i := 1; i <= 5; i++ {
		layerDB := a.dbMgr.LayerDB(i)
		if layerDB == nil {
			result[i] = []db.Trait{}
			continue
		}
		traits, err := db.FetchTraits(layerDB, i)
		if err != nil {
			result[i] = []db.Trait{}
			continue
		}
		if traits == nil {
			traits = []db.Trait{}
		}
		result[i] = traits
	}
	return result, nil
}

// GetLatestSnapshot returns the most recent personality snapshot.
func (a *App) GetLatestSnapshot() (*db.PersonalitySnapshot, error) {
	if a.dbMgr == nil {
		return nil, fmt.Errorf("database not initialized")
	}
	snapshotDB := a.dbMgr.SnapshotDB()
	if snapshotDB == nil {
		return nil, fmt.Errorf("snapshot database not available")
	}
	snapshots, err := db.FetchSnapshots(snapshotDB, 1)
	if err != nil {
		return nil, err
	}
	if len(snapshots) == 0 {
		return nil, nil
	}
	return &snapshots[0], nil
}

// ─── Memory ─────────────────────────────────────────────────────────────────

// SearchMemories searches memories by keyword.
func (a *App) SearchMemories(query string, limit int) ([]db.Memory, error) {
	if a.dbMgr == nil {
		return nil, fmt.Errorf("database not initialized")
	}
	memDB := a.dbMgr.MemoryDB()
	if memDB == nil {
		return nil, fmt.Errorf("memory database not available")
	}
	return db.SearchMemories(memDB, query, limit)
}

// GetRecentMemories returns the most recent memories.
func (a *App) GetRecentMemories(limit int) ([]db.Memory, error) {
	if a.dbMgr == nil {
		return nil, fmt.Errorf("database not initialized")
	}
	memDB := a.dbMgr.MemoryDB()
	if memDB == nil {
		return nil, fmt.Errorf("memory database not available")
	}
	return db.FetchRecentMemories(memDB, limit)
}

// ─── Settings ───────────────────────────────────────────────────────────────

// GetConfig returns the current application configuration.
func (a *App) GetConfig() (*config.Config, error) {
	if a.cfg == nil {
		return nil, fmt.Errorf("configuration not loaded")
	}
	return a.cfg, nil
}

// SaveConfig saves the configuration and reinitializes services.
func (a *App) SaveConfig(cfg *config.Config) error {
	if err := config.Save(cfg, a.cfgPath); err != nil {
		return fmt.Errorf("save config: %w", err)
	}
	a.cfg = cfg

	// Reinitialize AI clients with new config
	a.initAIClients()

	// Reinitialize agent service if DB is available
	if a.dbMgr != nil && a.chatClient != nil {
		a.agentService = agent.NewService(a.dbMgr, a.cfg.CacheDir, a.cfg.ResponseLanguage())
	}

	// Update language on existing engines
	lang := a.cfg.ResponseLanguage()
	if a.modelingEngine != nil {
		a.modelingEngine.SetLanguage(lang)
	}
	if a.consolidator != nil {
		a.consolidator.SetLanguage(lang)
	}

	// Reinitialize capture and analysis to pick up new provider settings.
	a.captureMu.Lock()
	wasRunning := a.captureStatus.Running
	a.captureMu.Unlock()

	if wasRunning {
		a.StopCapture()
	}

	// Stop old monitors before reinit.
	if a.screenState != nil {
		a.screenState.Stop()
	}
	if a.inputMon != nil {
		a.inputMon.Stop()
	}

	a.initCaptureAndAnalysis()

	if wasRunning {
		_ = a.StartCapture()
	}

	return nil
}

// TestAIConnection tests connectivity to an AI provider.
func (a *App) TestAIConnection(endpoint, apiKey, model string) error {
	client := ai.NewClient(endpoint, apiKey, model)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	_, err := client.ChatCompletion(ctx, ai.ChatRequest{
		Messages: []ai.Message{
			{Role: "user", Content: "Hello"},
		},
		Temperature: 0.1,
	})
	if err != nil {
		return fmt.Errorf("connection test failed: %w", err)
	}
	return nil
}

// ─── Export ──────────────────────────────────────────────────────────────────

// ExportPersonality exports personality data in the specified format.
func (a *App) ExportPersonality(format string) (string, error) {
	if a.dbMgr == nil {
		return "", fmt.Errorf("database not initialized")
	}

	allTraits, err := a.GetAllLayerTraits()
	if err != nil {
		return "", fmt.Errorf("fetch traits: %w", err)
	}

	switch format {
	case "json":
		return exportTraitsJSON(allTraits)
	case "card":
		return exportTraitsCard(allTraits), nil
	case "minimal":
		return exportTraitsMinimal(allTraits), nil
	default:
		return "", fmt.Errorf("unknown format '%s': must be one of json, card, minimal", format)
	}
}

// ─── Export helpers ─────────────────────────────────────────────────────────

var layerNames = []string{"Rhythm", "Knowledge", "Cognitive", "Expression", "Value"}

func exportTraitsMinimal(allTraits map[int][]db.Trait) string {
	var parts []string
	for i := 1; i <= 5; i++ {
		traits := allTraits[i]
		if len(traits) == 0 {
			continue
		}
		var traitStrs []string
		for _, t := range traits {
			traitStrs = append(traitStrs, fmt.Sprintf("%s=%s", t.Dimension, t.Value))
		}
		parts = append(parts, fmt.Sprintf("%s: %s", layerNames[i-1], strings.Join(traitStrs, ", ")))
	}
	if len(parts) == 0 {
		return "No personality data available."
	}
	return "Personality Profile: " + strings.Join(parts, ". ") + "."
}

func exportTraitsCard(allTraits map[int][]db.Trait) string {
	result := "=== AnotherMe Personality Profile ===\n\n"
	totalTraits := 0
	for _, traits := range allTraits {
		totalTraits += len(traits)
	}
	result += fmt.Sprintf("Total traits: %d across 5 layers\n\n", totalTraits)

	for i := 1; i <= 5; i++ {
		traits := allTraits[i]
		result += fmt.Sprintf("--- Layer %d: %s (%d traits) ---\n", i, layerNames[i-1], len(traits))
		if len(traits) == 0 {
			result += "  (no traits)\n"
		} else {
			for _, t := range traits {
				result += fmt.Sprintf("  %s: %s (%.2f)\n", t.Dimension, t.Value, t.Confidence)
			}
		}
		result += "\n"
	}
	return result
}

func exportTraitsJSON(allTraits map[int][]db.Trait) (string, error) {
	type traitExport struct {
		Dimension   string  `json:"dimension"`
		Value       string  `json:"value"`
		Confidence  float64 `json:"confidence"`
		Description *string `json:"description,omitempty"`
	}
	type layerOutput struct {
		Layer     int           `json:"layer"`
		LayerName string        `json:"layer_name"`
		Traits    []traitExport `json:"traits"`
	}

	var output []layerOutput
	for i := 1; i <= 5; i++ {
		lo := layerOutput{
			Layer:     i,
			LayerName: layerNames[i-1],
		}
		for _, t := range allTraits[i] {
			lo.Traits = append(lo.Traits, traitExport{
				Dimension:   t.Dimension,
				Value:       t.Value,
				Confidence:  t.Confidence,
				Description: t.Description,
			})
		}
		if lo.Traits == nil {
			lo.Traits = []traitExport{}
		}
		output = append(output, lo)
	}

	data, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		return "", fmt.Errorf("marshal JSON: %w", err)
	}
	return string(data), nil
}

// ─── Frontend API wrappers ──────────────────────────────────────────────────
// These methods match the names expected by the Vue frontend (mock.js).
// Wails binds Go methods by name, so the frontend calls must match exactly.

// GetChatMessages returns all messages in a chat session.
// Frontend calls this instead of GetSessionMessages.
func (a *App) GetChatMessages(sessionID string) ([]db.ChatMessage, error) {
	return a.GetSessionMessages(sessionID)
}

// GetAllPersonalityLayers returns traits from all 5 personality layers.
func (a *App) GetAllPersonalityLayers() (map[int][]db.Trait, error) {
	return a.GetAllLayerTraits()
}

// GetPersonalityLayer returns traits for a specific personality layer (1-5).
func (a *App) GetPersonalityLayer(layer int) ([]db.Trait, error) {
	return a.GetLayerTraits(layer)
}

// GetPersonalitySnapshot returns the most recent personality snapshot.
func (a *App) GetPersonalitySnapshot() (*db.PersonalitySnapshot, error) {
	return a.GetLatestSnapshot()
}

// SettingsData is the frontend-friendly settings format.
type SettingsData struct {
	Language  string          `json:"language"`
	AI        SettingsAI      `json:"ai"`
	Capture   SettingsCapture `json:"capture"`
	Blacklist []string        `json:"blacklist"`
}

// SettingsAI holds AI provider settings for the frontend.
type SettingsAI struct {
	ProviderName string `json:"providerName"`
	Endpoint     string `json:"endpoint"`
	APIKey       string `json:"apiKey"`
	ModelName    string `json:"modelName"`
}

// SettingsCapture holds capture settings for the frontend.
type SettingsCapture struct {
	Mode            string `json:"mode"`
	IntervalSeconds int    `json:"intervalSeconds"`
	DailyLimit      int    `json:"dailyLimit"`
}

// GetSettings returns settings in the format expected by the frontend.
func (a *App) GetSettings() (*SettingsData, error) {
	if a.cfg == nil {
		return nil, fmt.Errorf("configuration not loaded")
	}

	data := &SettingsData{
		Language:  a.cfg.Language,
		Blacklist: []string{},
		Capture: SettingsCapture{
			Mode:            "smart",
			IntervalSeconds: 300,
			DailyLimit:      200,
		},
	}

	// Extract first provider info
	if len(a.cfg.Providers) > 0 {
		p := a.cfg.Providers[0]
		data.AI = SettingsAI{
			ProviderName: p.Name,
			Endpoint:     p.Endpoint,
			APIKey:       p.APIKey,
			ModelName:    p.Model,
		}
	}

	return data, nil
}

// SaveSettings saves settings from the frontend format.
func (a *App) SaveSettings(data *SettingsData) error {
	if a.cfg == nil {
		return fmt.Errorf("configuration not loaded")
	}

	// Update language
	a.cfg.Language = data.Language

	// Update or create provider
	if len(a.cfg.Providers) == 0 {
		a.cfg.Providers = []config.Provider{{}}
	}
	a.cfg.Providers[0].Name = data.AI.ProviderName
	a.cfg.Providers[0].Endpoint = data.AI.Endpoint
	a.cfg.Providers[0].APIKey = data.AI.APIKey
	a.cfg.Providers[0].Model = data.AI.ModelName

	return a.SaveConfig(a.cfg)
}

// DataStats holds database statistics for the frontend.
type DataStats struct {
	DBPath           string `json:"dbPath"`
	DBSize           string `json:"dbSize"`
	ActivitiesCount  int    `json:"activitiesCount"`
	MemoriesCount    int    `json:"memoriesCount"`
	PersonalityVer   int    `json:"personalityVersion"`
	OldestRecord     string `json:"oldestRecord"`
}

// GetDataStats returns database statistics.
func (a *App) GetDataStats() (*DataStats, error) {
	if a.dbMgr == nil {
		return nil, fmt.Errorf("database not initialized")
	}

	stats := &DataStats{
		DBPath: a.dbMgr.DBPath(),
	}

	// Calculate total DB size
	var totalSize int64
	entries, err := os.ReadDir(a.dbMgr.DBPath())
	if err == nil {
		for _, e := range entries {
			if !e.IsDir() && strings.HasSuffix(e.Name(), ".sqlite") {
				info, err := e.Info()
				if err == nil {
					totalSize += info.Size()
				}
			}
		}
	}
	if totalSize > 1024*1024 {
		stats.DBSize = fmt.Sprintf("%.1f MB", float64(totalSize)/(1024*1024))
	} else {
		stats.DBSize = fmt.Sprintf("%.1f KB", float64(totalSize)/1024)
	}

	// Count activities
	if actDB := a.dbMgr.ActivityDB(); actDB != nil {
		count, err := db.CountActivities(actDB)
		if err == nil {
			stats.ActivitiesCount = count
		}
	}

	// Count memories
	if memDB := a.dbMgr.MemoryDB(); memDB != nil {
		count, err := db.CountMemories(memDB)
		if err == nil {
			stats.MemoriesCount = count
		}
	}

	// Count personality snapshots as version
	if snapshotDB := a.dbMgr.SnapshotDB(); snapshotDB != nil {
		var count int
		if err := snapshotDB.QueryRow("SELECT COUNT(*) FROM personality_snapshots").Scan(&count); err == nil {
			stats.PersonalityVer = count
		}
	}

	return stats, nil
}

// MemoryListOptions holds query options for the memory list.
type MemoryListOptions struct {
	Keyword  string `json:"keyword"`
	Category string `json:"category"`
	SortBy   string `json:"sortBy"`
}

// GetMemories returns memories filtered by the given options.
func (a *App) GetMemories(options MemoryListOptions) ([]db.Memory, error) {
	if a.dbMgr == nil {
		return nil, fmt.Errorf("database not initialized")
	}
	memDB := a.dbMgr.MemoryDB()
	if memDB == nil {
		return nil, fmt.Errorf("memory database not available")
	}

	var memories []db.Memory
	var err error

	if options.Keyword != "" {
		memories, err = db.SearchMemories(memDB, options.Keyword, 500)
	} else {
		memories, err = db.FetchRecentMemories(memDB, 500)
	}
	if err != nil {
		return nil, err
	}

	// Filter by category
	if options.Category != "" && options.Category != "all" {
		filtered := make([]db.Memory, 0, len(memories))
		for _, m := range memories {
			if m.Category == options.Category {
				filtered = append(filtered, m)
			}
		}
		memories = filtered
	}

	// Sort
	switch options.SortBy {
	case "importance":
		sort.Slice(memories, func(i, j int) bool {
			return memories[i].Importance > memories[j].Importance
		})
	case "recency":
		sort.Slice(memories, func(i, j int) bool {
			return memories[i].LastAccessedAt.After(memories[j].LastAccessedAt)
		})
	default: // "date" or empty
		sort.Slice(memories, func(i, j int) bool {
			return memories[i].CreatedAt.After(memories[j].CreatedAt)
		})
	}

	// Cap at 100
	if len(memories) > 100 {
		memories = memories[:100]
	}

	return memories, nil
}

// MemoryStats holds memory statistics for the frontend.
type MemoryStats struct {
	Total  int `json:"total"`
	Pinned int `json:"pinned"`
}

// GetMemoryStats returns memory statistics.
func (a *App) GetMemoryStats() (*MemoryStats, error) {
	if a.dbMgr == nil {
		return nil, fmt.Errorf("database not initialized")
	}
	memDB := a.dbMgr.MemoryDB()
	if memDB == nil {
		return nil, fmt.Errorf("memory database not available")
	}

	stats := &MemoryStats{}
	count, err := db.CountMemories(memDB)
	if err == nil {
		stats.Total = count
	}

	// Count pinned memories
	var pinned int
	if err := memDB.QueryRow("SELECT COUNT(*) FROM memories WHERE pinned = 1").Scan(&pinned); err == nil {
		stats.Pinned = pinned
	}

	return stats, nil
}
