package analysis

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/user/anotherme-cli/pkg/ai"
	"github.com/user/anotherme-cli/pkg/db"

	_ "modernc.org/sqlite"
)

// memoryRow represents a memory record fetched for consolidation.
type memoryRow struct {
	id             string
	content        string
	category       string
	keywords       string
	importance     float64
	accessCount    int
	pinned         bool
	sourceType     string
	sourceID       sql.NullString
	createdAt      string
	lastAccessedAt string
	monthKey       string // YYYY-MM
}

const (
	defaultSoftLimit     = 250
	defaultHardLimit     = 300
	consolidationAgeDays = 14
	decayIdleDays        = 30
	decayFactor          = 0.9
	consolidationCheckInterval = 24 * time.Hour
)

// MemoryConsolidator periodically merges old, low-importance memories into
// AI-generated summaries. It runs a daily check and consolidates memories
// older than 14 days, grouped by calendar month.
type MemoryConsolidator struct {
	aiClient  *ai.Client
	dbPath    string
	memoryDB  *sql.DB // read-write
	softLimit int     // trigger consolidation when exceeded (default 250)
	hardLimit int     // capacity cap (default 300)
	running   bool
	stopCh    chan struct{}
	mu        sync.Mutex
	language  string // AI response language
}

// NewMemoryConsolidator creates a new MemoryConsolidator. It opens its own
// read-write connection to memory.sqlite under dbPath.
func NewMemoryConsolidator(aiClient *ai.Client, dbPath string, language ...string) (*MemoryConsolidator, error) {
	memoryDSN := fmt.Sprintf("file:%s?_journal_mode=WAL", filepath.Join(dbPath, "memory.sqlite"))
	memoryDB, err := sql.Open("sqlite", memoryDSN)
	if err != nil {
		return nil, fmt.Errorf("open memory.sqlite: %w", err)
	}
	if err := memoryDB.Ping(); err != nil {
		memoryDB.Close()
		return nil, fmt.Errorf("ping memory.sqlite: %w", err)
	}

	lang := ""
	if len(language) > 0 {
		lang = language[0]
	}
	return &MemoryConsolidator{
		aiClient:  aiClient,
		dbPath:    dbPath,
		memoryDB:  memoryDB,
		softLimit: defaultSoftLimit,
		hardLimit: defaultHardLimit,
		language:  lang,
	}, nil
}

// SetLanguage updates the AI response language for subsequent consolidation runs.
func (c *MemoryConsolidator) SetLanguage(language string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.language = language
}

// Start begins the daily consolidation check scheduler.
func (c *MemoryConsolidator) Start() {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.running {
		return
	}
	c.running = true
	c.stopCh = make(chan struct{})

	go c.scheduleLoop()
}

// Stop halts the consolidation scheduler and closes the DB connection.
func (c *MemoryConsolidator) Stop() {
	c.mu.Lock()
	defer c.mu.Unlock()

	if !c.running {
		return
	}
	close(c.stopCh)
	c.running = false

	if c.memoryDB != nil {
		c.memoryDB.Close()
	}
}

// RunNow triggers an immediate consolidation run, bypassing the scheduler.
func (c *MemoryConsolidator) RunNow() error {
	return c.consolidate()
}

func (c *MemoryConsolidator) scheduleLoop() {
	ticker := time.NewTicker(consolidationCheckInterval)
	defer ticker.Stop()

	for {
		select {
		case <-c.stopCh:
			return
		case <-ticker.C:
			if err := c.consolidate(); err != nil {
				log.Printf("[MemoryConsolidator] Consolidation failed: %v", err)
			}
		}
	}
}

// consolidate runs the full consolidation pipeline:
// 1. Check if total memories exceed soft limit
// 2. Group old non-pinned memories by month and consolidate via AI
// 3. Apply importance decay to stale memories
// 4. Enforce hard capacity limit
func (c *MemoryConsolidator) consolidate() error {
	log.Println("[MemoryConsolidator] Starting consolidation check...")

	// Step 1: Count total memories.
	totalCount, err := c.countMemories()
	if err != nil {
		return fmt.Errorf("count memories: %w", err)
	}

	log.Printf("[MemoryConsolidator] Total memories: %d (soft limit: %d)", totalCount, c.softLimit)

	if totalCount >= c.softLimit {
		// Step 2: Find and consolidate old memories by month.
		if err := c.consolidateOldMemories(); err != nil {
			log.Printf("[MemoryConsolidator] Consolidation step failed: %v", err)
			// Continue with decay and pruning even if consolidation fails.
		}
	}

	// Step 3: Apply importance decay.
	if err := c.applyImportanceDecay(); err != nil {
		log.Printf("[MemoryConsolidator] Importance decay failed: %v", err)
	}

	// Step 4: Enforce capacity limit.
	if err := c.enforceCapacityLimit(); err != nil {
		log.Printf("[MemoryConsolidator] Capacity enforcement failed: %v", err)
	}

	log.Println("[MemoryConsolidator] Consolidation check complete")
	return nil
}

func (c *MemoryConsolidator) countMemories() (int, error) {
	var count int
	err := c.memoryDB.QueryRow("SELECT COUNT(*) FROM memories").Scan(&count)
	return count, err
}

// consolidateOldMemories finds non-pinned memories older than 14 days,
// groups them by month (YYYY-MM), and for each group with >3 memories,
// calls AI to produce consolidated summaries.
func (c *MemoryConsolidator) consolidateOldMemories() error {
	cutoff := time.Now().AddDate(0, 0, -consolidationAgeDays)
	cutoffStr := db.FormatGRDBDate(cutoff)

	rows, err := c.memoryDB.Query(`
		SELECT id, content, category, keywords, importance, accessCount,
		       pinned, sourceType, sourceId, createdAt, lastAccessedAt
		FROM memories
		WHERE pinned = 0 AND createdAt < ?
		ORDER BY createdAt`,
		cutoffStr,
	)
	if err != nil {
		return fmt.Errorf("fetch candidates: %w", err)
	}
	defer rows.Close()

	// Scan all candidates.
	var candidates []memoryRow
	for rows.Next() {
		var m memoryRow
		var pinnedInt int
		err := rows.Scan(
			&m.id, &m.content, &m.category, &m.keywords,
			&m.importance, &m.accessCount, &pinnedInt,
			&m.sourceType, &m.sourceID, &m.createdAt, &m.lastAccessedAt,
		)
		if err != nil {
			return fmt.Errorf("scan memory: %w", err)
		}
		m.pinned = pinnedInt != 0

		// Parse createdAt to extract month key.
		t, err := db.ParseGRDBDate(m.createdAt)
		if err != nil {
			log.Printf("[MemoryConsolidator] Skip memory %s: bad date: %v", m.id, err)
			continue
		}
		m.monthKey = t.Format("2006-01")
		candidates = append(candidates, m)
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("iterate candidates: %w", err)
	}

	if len(candidates) < 5 {
		log.Printf("[MemoryConsolidator] Only %d candidates, skipping consolidation", len(candidates))
		return nil
	}

	// Group by month.
	grouped := make(map[string][]memoryRow)
	for _, m := range candidates {
		grouped[m.monthKey] = append(grouped[m.monthKey], m)
	}

	for monthKey, memories := range grouped {
		if len(memories) < 3 {
			continue
		}

		if err := c.consolidateMonthGroup(monthKey, memories); err != nil {
			// AI failure for one month should not block others.
			log.Printf("[MemoryConsolidator] Failed to consolidate %s: %v", monthKey, err)
			continue
		}
	}

	return nil
}

type consolidationOutput struct {
	Content  string   `json:"content"`
	Keywords []string `json:"keywords"`
	Category string   `json:"category"`
}

func (c *MemoryConsolidator) consolidateMonthGroup(monthKey string, memories []memoryRow) error {
	log.Printf("[MemoryConsolidator] Consolidating %d memories for %s", len(memories), monthKey)

	// Build the memories text for the prompt.
	var lines []string
	for i, m := range memories {
		var keywords []string
		_ = json.Unmarshal([]byte(m.keywords), &keywords)
		kwStr := strings.Join(keywords, ", ")
		lines = append(lines, fmt.Sprintf("[%d] %s (keywords: %s)", i+1, m.content, kwStr))
	}
	memoriesText := strings.Join(lines, "\n")

	// Calculate target count: 1-5 consolidated memories.
	targetCount := len(memories) / 3
	if targetCount < 2 {
		targetCount = 2
	}
	if targetCount > 5 {
		targetCount = 5
	}

	userPrompt := BuildMemoryConsolidationUserPrompt(monthKey, len(memories), targetCount, memoriesText)

	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()

	resp, err := c.aiClient.ChatCompletion(ctx, ai.ChatRequest{
		Messages: []ai.Message{
			{Role: "system", Content: MemoryConsolidationSystemPrompt + LanguageDirective(c.language)},
			{Role: "user", Content: userPrompt},
		},
		Temperature: 0.3,
	})
	if err != nil {
		return fmt.Errorf("AI consolidation call: %w", err)
	}

	if len(resp.Choices) == 0 {
		return fmt.Errorf("empty AI response")
	}

	content := resp.Choices[0].Message.Content

	var summaries []consolidationOutput
	if err := json.Unmarshal([]byte(content), &summaries); err != nil {
		return fmt.Errorf("parse consolidation response: %w", err)
	}

	if len(summaries) == 0 {
		return nil
	}

	// Derive properties from the source group.
	var maxImportance float64
	var earliestDate string
	for _, m := range memories {
		if m.importance > maxImportance {
			maxImportance = m.importance
		}
	}
	earliestDate = memories[0].createdAt // already sorted by createdAt

	// Atomically replace originals with consolidated summaries.
	tx, err := c.memoryDB.Begin()
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}
	defer tx.Rollback()

	// Delete originals.
	ids := make([]string, len(memories))
	for i, m := range memories {
		ids[i] = m.id
	}
	if err := c.deleteByIDs(tx, ids); err != nil {
		return fmt.Errorf("delete originals: %w", err)
	}

	// Insert consolidated summaries.
	importance := maxImportance + 0.1
	if importance > 1.0 {
		importance = 1.0
	}
	now := db.FormatGRDBDate(time.Now())

	for _, summary := range summaries {
		keywordsJSON, err := json.Marshal(summary.Keywords)
		if err != nil {
			keywordsJSON = []byte("[]")
		}

		_, err = tx.Exec(`
			INSERT INTO memories (id, content, category, keywords, importance, accessCount, pinned, sourceType, createdAt, lastAccessedAt)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			uuid.New().String(),
			summary.Content,
			summary.Category,
			string(keywordsJSON),
			importance,
			0,     // accessCount
			false, // pinned
			"consolidation",
			earliestDate,
			now,
		)
		if err != nil {
			return fmt.Errorf("insert consolidated memory: %w", err)
		}
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit transaction: %w", err)
	}

	log.Printf("[MemoryConsolidator] Consolidated %d memories into %d summaries for %s",
		len(memories), len(summaries), monthKey)
	return nil
}

func (c *MemoryConsolidator) deleteByIDs(tx *sql.Tx, ids []string) error {
	if len(ids) == 0 {
		return nil
	}

	// Build placeholder string: ?,?,?...
	placeholders := make([]string, len(ids))
	args := make([]interface{}, len(ids))
	for i, id := range ids {
		placeholders[i] = "?"
		args[i] = id
	}

	query := fmt.Sprintf("DELETE FROM memories WHERE id IN (%s)", strings.Join(placeholders, ","))
	_, err := tx.Exec(query, args...)
	return err
}

// applyImportanceDecay multiplies importance by 0.9 for non-pinned memories
// not accessed in the last 30 days.
func (c *MemoryConsolidator) applyImportanceDecay() error {
	cutoff := time.Now().AddDate(0, 0, -decayIdleDays)
	cutoffStr := db.FormatGRDBDate(cutoff)

	result, err := c.memoryDB.Exec(`
		UPDATE memories SET importance = importance * ?
		WHERE pinned = 0 AND lastAccessedAt < ?`,
		decayFactor, cutoffStr,
	)
	if err != nil {
		return fmt.Errorf("apply decay: %w", err)
	}

	affected, _ := result.RowsAffected()
	if affected > 0 {
		log.Printf("[MemoryConsolidator] Applied importance decay to %d memories", affected)
	}
	return nil
}

// enforceCapacityLimit deletes the lowest-scored non-pinned memories when
// the total count exceeds the hard limit (300).
func (c *MemoryConsolidator) enforceCapacityLimit() error {
	totalCount, err := c.countMemories()
	if err != nil {
		return fmt.Errorf("count memories: %w", err)
	}

	overflow := totalCount - c.hardLimit
	if overflow <= 0 {
		return nil
	}

	log.Printf("[MemoryConsolidator] Over capacity by %d, pruning lowest-scored memories", overflow)

	// Delete the lowest-scored memories using composite score:
	// importance * recencyScore where recencyScore = 1/(1 + daysSinceAccess/30)
	_, err = c.memoryDB.Exec(`
		DELETE FROM memories WHERE id IN (
			SELECT id FROM memories
			WHERE pinned = 0
			ORDER BY importance * (1.0 / (1.0 + (julianday('now') - julianday(lastAccessedAt)) / 30.0)) ASC
			LIMIT ?
		)`, overflow)
	if err != nil {
		return fmt.Errorf("delete overflow: %w", err)
	}

	log.Printf("[MemoryConsolidator] Pruned %d lowest-scored memories", overflow)
	return nil
}
