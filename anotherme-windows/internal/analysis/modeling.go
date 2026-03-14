package analysis

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/user/anotherme-cli/pkg/ai"
	"github.com/user/anotherme-cli/pkg/db"

	_ "modernc.org/sqlite"
)

// ModelingEngine orchestrates the full personality modeling pipeline across all 5 layers.
// It runs periodically and requires a minimum number of new activity records before
// triggering a new analysis cycle.
type ModelingEngine struct {
	aiClient    *ai.Client
	dbMgr       *db.Manager
	dbPath      string // base directory for opening read-write DB connections
	running     bool
	lastRunDate time.Time
	minRecords  int // minimum new records threshold before running
	mu          sync.Mutex
	stopCh      chan struct{}
	language    string // AI response language

	// own read-write connections
	activityRW *sql.DB
	layerRW    [5]*sql.DB
	snapshotRW *sql.DB
}

// openRW opens a read-write SQLite connection with WAL journal mode.
func openRW(path string) (*sql.DB, error) {
	dsn := fmt.Sprintf("file:%s?_journal_mode=WAL", path)
	d, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	if err := d.Ping(); err != nil {
		d.Close()
		return nil, err
	}
	return d, nil
}

// NewModelingEngine creates a new ModelingEngine instance.
// It opens its own read-write connections so the pipeline can write results.
func NewModelingEngine(aiClient *ai.Client, dbMgr *db.Manager, language ...string) (*ModelingEngine, error) {
	dbPath := dbMgr.DBPath()
	lang := ""
	if len(language) > 0 {
		lang = language[0]
	}
	m := &ModelingEngine{
		aiClient:   aiClient,
		dbMgr:      dbMgr,
		dbPath:     dbPath,
		minRecords: 200,
		language:   lang,
	}

	var err error

	// Open read-write activity DB
	m.activityRW, err = openRW(filepath.Join(dbPath, "activity.sqlite"))
	if err != nil {
		return nil, fmt.Errorf("open activity.sqlite rw: %w", err)
	}

	// Open read-write layer DBs
	layerFiles := [5]string{
		"layer1_rhythms.sqlite",
		"layer2_knowledge.sqlite",
		"layer3_cognitive.sqlite",
		"layer4_expression.sqlite",
		"layer5_values.sqlite",
	}
	for i, file := range layerFiles {
		m.layerRW[i], err = openRW(filepath.Join(dbPath, file))
		if err != nil {
			m.closeOwnDBs()
			return nil, fmt.Errorf("open %s rw: %w", file, err)
		}
	}

	// Open read-write snapshot DB
	m.snapshotRW, err = openRW(filepath.Join(dbPath, "snapshots.sqlite"))
	if err != nil {
		m.closeOwnDBs()
		return nil, fmt.Errorf("open snapshots.sqlite rw: %w", err)
	}

	return m, nil
}

// SetLanguage updates the AI response language for subsequent analysis runs.
func (m *ModelingEngine) SetLanguage(language string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.language = language
}

// closeOwnDBs closes all read-write DB connections owned by the engine.
func (m *ModelingEngine) closeOwnDBs() {
	if m.activityRW != nil {
		m.activityRW.Close()
	}
	for _, d := range m.layerRW {
		if d != nil {
			d.Close()
		}
	}
	if m.snapshotRW != nil {
		m.snapshotRW.Close()
	}
}

// Start begins the daily modeling check scheduler.
func (m *ModelingEngine) Start() {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.running {
		return
	}
	m.running = true
	m.stopCh = make(chan struct{})

	go m.scheduleLoop()
}

// Stop halts the modeling scheduler and closes owned DB connections.
func (m *ModelingEngine) Stop() {
	m.mu.Lock()
	defer m.mu.Unlock()

	if !m.running {
		return
	}
	close(m.stopCh)
	m.running = false
	m.closeOwnDBs()
}

// RunNow triggers an immediate modeling run, bypassing the scheduler.
func (m *ModelingEngine) RunNow() error {
	m.mu.Lock()
	if !m.running {
		m.mu.Unlock()
		return fmt.Errorf("modeling engine is not running")
	}
	m.mu.Unlock()

	return m.runPipeline()
}

// ShouldRun returns true if enough new records have accumulated since the last run.
func (m *ModelingEngine) ShouldRun() bool {
	m.mu.Lock()
	lastRun := m.lastRunDate
	m.mu.Unlock()

	count, err := m.countRecordsSince(lastRun)
	if err != nil {
		log.Printf("[ModelingEngine] Failed to count records: %v", err)
		return false
	}

	return count >= m.minRecords
}

func (m *ModelingEngine) scheduleLoop() {
	// Check once per hour whether modeling should run.
	ticker := time.NewTicker(1 * time.Hour)
	defer ticker.Stop()

	for {
		select {
		case <-m.stopCh:
			return
		case <-ticker.C:
			if m.ShouldRun() {
				if err := m.runPipeline(); err != nil {
					log.Printf("[ModelingEngine] Pipeline failed: %v", err)
				}
			}
		}
	}
}

func (m *ModelingEngine) runPipeline() error {
	m.mu.Lock()
	lastRun := m.lastRunDate
	m.mu.Unlock()

	log.Println("[ModelingEngine] Starting modeling pipeline...")

	// Fetch activity records since last run (using own read-write connection).
	records, err := db.FetchActivities(m.activityRW, lastRun, 5000)
	if err != nil {
		return fmt.Errorf("fetch activities: %w", err)
	}
	if len(records) == 0 {
		log.Println("[ModelingEngine] No new records to analyze")
		return nil
	}

	log.Printf("[ModelingEngine] Analyzing %d records", len(records))

	// Layer 1: Behavioral rhythms
	log.Println("[ModelingEngine] Running Layer 1 analysis...")
	if err := m.runLayer1(records); err != nil {
		log.Printf("[ModelingEngine] Layer 1 failed: %v", err)
		// Continue with other layers.
	}

	// Layer 2: Knowledge & interests
	log.Println("[ModelingEngine] Running Layer 2 analysis...")
	if err := m.runLayer2(records); err != nil {
		log.Printf("[ModelingEngine] Layer 2 failed: %v", err)
	}

	// Layer 3: Cognitive style
	log.Println("[ModelingEngine] Running Layer 3 analysis...")
	if err := m.runLayer3(records); err != nil {
		log.Printf("[ModelingEngine] Layer 3 failed: %v", err)
	}

	// Layer 4: Expression style
	log.Println("[ModelingEngine] Running Layer 4 analysis...")
	if err := m.runLayer4(records); err != nil {
		log.Printf("[ModelingEngine] Layer 4 failed: %v", err)
	}

	// Layer 5: Values & priorities
	log.Println("[ModelingEngine] Running Layer 5 analysis...")
	if err := m.runLayer5(records); err != nil {
		log.Printf("[ModelingEngine] Layer 5 failed: %v", err)
	}

	// Generate snapshot summary.
	log.Println("[ModelingEngine] Generating snapshot summary...")
	if err := m.generateSnapshot(); err != nil {
		log.Printf("[ModelingEngine] Snapshot generation failed: %v", err)
	}

	// Run MBTI + Big Five analysis.
	log.Println("[ModelingEngine] Running personality assessments...")
	if err := m.runPersonalityAssessments(); err != nil {
		log.Printf("[ModelingEngine] Personality assessments failed: %v", err)
	}

	m.mu.Lock()
	m.lastRunDate = time.Now()
	m.mu.Unlock()

	log.Println("[ModelingEngine] Pipeline completed")
	return nil
}

func (m *ModelingEngine) countRecordsSince(since time.Time) (int, error) {
	var count int
	err := m.activityRW.QueryRow(
		"SELECT COUNT(*) FROM activity_logs WHERE timestamp >= ?",
		db.FormatGRDBDate(since),
	).Scan(&count)
	return count, err
}

// ParsedTrait represents a single trait parsed from AI response.
type ParsedTrait struct {
	Dimension   string  `json:"dimension"`
	Value       string  `json:"value"`
	Confidence  float64 `json:"confidence"`
	Description string  `json:"description,omitempty"`
}

// TraitsResponse is the standard AI response format for trait analysis.
type TraitsResponse struct {
	Traits []ParsedTrait `json:"traits"`
}

// ─────────────────────────────────────────────
// Layer 1: Behavioral Rhythms
// ─────────────────────────────────────────────

// RhythmSummary holds the statistical summary for Layer 1 analysis.
type RhythmSummary struct {
	DayCount           int
	AvgActiveHours     float64
	AvgStartTime       string
	AvgEndTime         string
	AvgFocusScore      float64
	AvgSwitchesPerHour float64
	PeakHours          []int
	TopApps            []AppUsage
	WorkMins           int
	LeisureMins        int
	OtherMins          int
	CommRatio          float64
	CommSessionCount   int
	AvgCommSessionMins float64
	AvgWeekdayMins     float64
	AvgWeekdayFocus    float64
	AvgWeekendMins     float64
	AvgWeekendFocus    float64
}

// AppUsage tracks an application's usage statistics.
type AppUsage struct {
	Name string
	Mins int
}

func (m *ModelingEngine) runLayer1(records []db.ActivityRecord) error {
	summary := m.buildRhythmSummary(records)

	// Build user message with statistics.
	topAppsStr := formatTopApps(summary.TopApps, 8)
	peakHoursStr := formatPeakHours(summary.PeakHours)

	userMessage := fmt.Sprintf(`The following are the user's activity rhythm statistics for the last %d days:

- Average daily active hours: %.1f hours
- Average start time: %s
- Average end time: %s
- Average focus score: %.2f (0-1)
- Average app switches per hour: %.1f
- Peak hours: %s
- Frequently used apps: %s
- Work/learning time: %d minutes
- Entertainment/social time: %d minutes
- Other time: %d minutes
- Communication tool proportion: %.1f%%
- Communication session count: %d
- Average communication session duration: %.1f minutes
- Weekday average active: %.0f minutes, focus %.2f
- Weekend average active: %.0f minutes, focus %.2f

Please analyze this user's behavioral rhythm characteristics.`,
		summary.DayCount,
		summary.AvgActiveHours,
		summary.AvgStartTime,
		summary.AvgEndTime,
		summary.AvgFocusScore,
		summary.AvgSwitchesPerHour,
		orNoData(peakHoursStr),
		orNoData(topAppsStr),
		summary.WorkMins,
		summary.LeisureMins,
		summary.OtherMins,
		summary.CommRatio*100,
		summary.CommSessionCount,
		summary.AvgCommSessionMins,
		summary.AvgWeekdayMins,
		summary.AvgWeekdayFocus,
		summary.AvgWeekendMins,
		summary.AvgWeekendFocus,
	)

	traits, err := m.callAIForTraits(Layer1SystemPrompt+LanguageDirective(m.language), userMessage)
	if err != nil {
		return fmt.Errorf("Layer 1 AI call: %w", err)
	}

	return m.upsertTraits(m.layerRW[0], "rhythm_traits", traits)
}

func (m *ModelingEngine) buildRhythmSummary(records []db.ActivityRecord) RhythmSummary {
	summary := RhythmSummary{}

	if len(records) == 0 {
		return summary
	}

	// Calculate unique days.
	daySet := make(map[string]bool)
	appMinutes := make(map[string]int)
	hourCounts := make(map[int]int)
	var workMins, leisureMins, otherMins int
	var commMins int
	var focusScores []float64
	var weekdayMins, weekendMins []float64
	var weekdayFocus, weekendFocus []float64

	commApps := map[string]bool{
		"WeChat": true, "Slack": true, "Discord": true,
		"Teams": true, "Feishu": true, "Telegram": true, "DingTalk": true,
	}

	// Estimate 5 minutes per record.
	const minsPerRecord = 5

	for _, rec := range records {
		day := rec.Timestamp.Format("2006-01-02")
		daySet[day] = true

		appMinutes[rec.AppName] += minsPerRecord
		hourCounts[rec.Timestamp.Hour()]++

		switch rec.ActivityCategory {
		case "work", "learning":
			workMins += minsPerRecord
		case "entertainment", "social":
			leisureMins += minsPerRecord
		default:
			otherMins += minsPerRecord
		}

		if commApps[rec.AppName] {
			commMins += minsPerRecord
		}

		// Approximate focus score from engagement level.
		var focus float64
		if rec.EngagementLevel != nil {
			switch *rec.EngagementLevel {
			case "deep_focus":
				focus = 0.9
			case "active_work":
				focus = 0.7
			case "browsing":
				focus = 0.3
			case "idle":
				focus = 0.1
			default:
				focus = 0.5
			}
		} else {
			focus = 0.5
		}
		focusScores = append(focusScores, focus)

		wd := rec.Timestamp.Weekday()
		if wd == time.Saturday || wd == time.Sunday {
			weekendMins = append(weekendMins, float64(minsPerRecord))
			weekendFocus = append(weekendFocus, focus)
		} else {
			weekdayMins = append(weekdayMins, float64(minsPerRecord))
			weekdayFocus = append(weekdayFocus, focus)
		}
	}

	summary.DayCount = len(daySet)
	if summary.DayCount == 0 {
		summary.DayCount = 1
	}

	totalMins := len(records) * minsPerRecord
	summary.AvgActiveHours = float64(totalMins) / float64(summary.DayCount) / 60.0

	// Avg focus score.
	if len(focusScores) > 0 {
		var sum float64
		for _, f := range focusScores {
			sum += f
		}
		summary.AvgFocusScore = sum / float64(len(focusScores))
	}

	// App switch approximation: count distinct app transitions.
	var switches int
	for i := 1; i < len(records); i++ {
		if records[i].AppName != records[i-1].AppName {
			switches++
		}
	}
	totalHours := float64(totalMins) / 60.0
	if totalHours > 0 {
		summary.AvgSwitchesPerHour = float64(switches) / totalHours
	}

	// Top apps.
	type appCount struct {
		name string
		mins int
	}
	var apps []appCount
	for name, mins := range appMinutes {
		apps = append(apps, appCount{name, mins})
	}
	sort.Slice(apps, func(i, j int) bool { return apps[i].mins > apps[j].mins })
	for _, a := range apps {
		summary.TopApps = append(summary.TopApps, AppUsage{Name: a.name, Mins: a.mins})
	}

	// Peak hours (top 3).
	type hourCount struct {
		hour  int
		count int
	}
	var hours []hourCount
	for h, c := range hourCounts {
		hours = append(hours, hourCount{h, c})
	}
	sort.Slice(hours, func(i, j int) bool { return hours[i].count > hours[j].count })
	for i, h := range hours {
		if i >= 3 {
			break
		}
		summary.PeakHours = append(summary.PeakHours, h.hour)
	}

	summary.WorkMins = workMins
	summary.LeisureMins = leisureMins
	summary.OtherMins = otherMins

	if totalMins > 0 {
		summary.CommRatio = float64(commMins) / float64(totalMins)
	}

	// Approximate start/end times from earliest/latest records per day.
	if len(records) > 0 {
		summary.AvgStartTime = records[len(records)-1].Timestamp.Format("15:04")
		summary.AvgEndTime = records[0].Timestamp.Format("15:04")
	}

	// Weekday/weekend averages.
	summary.AvgWeekdayMins = sumFloat(weekdayMins) / maxFloat(1, float64(countWeekdays(daySet)))
	summary.AvgWeekendMins = sumFloat(weekendMins) / maxFloat(1, float64(countWeekends(daySet)))
	summary.AvgWeekdayFocus = avgFloat(weekdayFocus)
	summary.AvgWeekendFocus = avgFloat(weekendFocus)

	return summary
}

// ─────────────────────────────────────────────
// Layer 2: Knowledge & Interests
// ─────────────────────────────────────────────

// topicAggregation tracks per-topic statistics across activity records.
type topicAggregation struct {
	count         int
	totalSecs     int
	firstSeen     time.Time
	lastSeen      time.Time
	categoryCounts map[string]int
	distinctDays  map[string]bool
}

func (m *ModelingEngine) runLayer2(records []db.ActivityRecord) error {
	if len(records) == 0 {
		return nil
	}

	// Phase 1: Aggregate topic stats from activity records.
	topicStats := make(map[string]*topicAggregation)

	for _, rec := range records {
		for _, topic := range rec.Topics {
			agg, ok := topicStats[topic]
			if !ok {
				agg = &topicAggregation{
					firstSeen:      rec.Timestamp,
					lastSeen:       rec.Timestamp,
					categoryCounts: make(map[string]int),
					distinctDays:   make(map[string]bool),
				}
				topicStats[topic] = agg
			}
			agg.count++
			agg.totalSecs += effectiveSeconds(rec)
			if rec.Timestamp.Before(agg.firstSeen) {
				agg.firstSeen = rec.Timestamp
			}
			if rec.Timestamp.After(agg.lastSeen) {
				agg.lastSeen = rec.Timestamp
			}
			agg.categoryCounts[rec.ActivityCategory]++
			agg.distinctDays[rec.Timestamp.Format("2006-01-02")] = true
		}
	}

	if len(topicStats) == 0 {
		log.Println("[ModelingEngine] Layer 2: no topics found in records")
		return nil
	}

	// Phase 2: Compute depth scores and classify topics.
	type topicNode struct {
		topic      string
		totalSecs  int
		visitCount int
		depthScore float64
		category   string
	}

	var allNodes []topicNode
	sevenDaysAgo := time.Now().AddDate(0, 0, -7)
	var recentCount int

	for topic, agg := range topicStats {
		// Determine dominant category.
		bestCat := "other"
		bestCount := 0
		for cat, cnt := range agg.categoryCounts {
			if cnt > bestCount {
				bestCat = cat
				bestCount = cnt
			}
		}

		// Calculate depth score (matching Swift implementation).
		depth := calculateDepthScore(agg.totalSecs, agg.count, len(agg.distinctDays), agg.lastSeen)

		allNodes = append(allNodes, topicNode{
			topic:      topic,
			totalSecs:  agg.totalSecs,
			visitCount: agg.count,
			depthScore: depth,
			category:   bestCat,
		})

		if agg.firstSeen.After(sevenDaysAgo) {
			recentCount++
		}
	}

	// Diversity index: unique categories / 8 (max expected categories).
	categorySet := make(map[string]bool)
	for _, node := range allNodes {
		categorySet[node.category] = true
	}
	diversityIndex := float64(len(categorySet)) / 8.0

	// Deep topics (depth >= 0.5) and expert topics (depth >= 0.8).
	var deepTopics, expertTopics []string
	for _, node := range allNodes {
		if node.depthScore >= 0.8 {
			expertTopics = append(expertTopics, node.topic)
		} else if node.depthScore >= 0.5 {
			deepTopics = append(deepTopics, node.topic)
		}
	}

	// Domain distribution.
	categoryDist := make(map[string]int)
	for _, node := range allNodes {
		categoryDist[node.category]++
	}
	domainStr := formatMapSorted(categoryDist, "")

	// Learning style stats.
	learningRecords := filterByCategory(records, "learning")
	var systematic, practice, community int
	for _, rec := range learningRecords {
		app := strings.ToLower(rec.AppName)
		switch {
		case containsAny(app, "safari", "chrome", "firefox", "arc", "edge", "brave", "preview", "books"):
			systematic++
		case containsAny(app, "xcode", "vscode", "visual studio", "terminal", "iterm", "cursor", "warp", "powershell", "cmd"):
			practice++
		case containsAny(app, "slack", "discord", "reddit", "teams"):
			community++
		}
	}
	learningStr := "no learning records"
	if len(learningRecords) > 0 {
		learningStr = fmt.Sprintf("reading:%d, practice:%d, community:%d", systematic, practice, community)
	}

	// Top topics by time (top 15).
	sort.Slice(allNodes, func(i, j int) bool { return allNodes[i].totalSecs > allNodes[j].totalSecs })
	var topByTimeParts []string
	for i, node := range allNodes {
		if i >= 15 {
			break
		}
		topByTimeParts = append(topByTimeParts, fmt.Sprintf("%s(%.1fh, depth:%.2f)",
			node.topic, float64(node.totalSecs)/3600.0, node.depthScore))
	}
	topByTimeStr := strings.Join(topByTimeParts, ", ")

	// Top co-occurrence edges (simplified: use topic-pair co-occurrence from records).
	coOccurrences := buildTopicCoOccurrences(records)
	var edgeParts []string
	type edgeEntry struct {
		key   string
		count int
	}
	var edgeList []edgeEntry
	for key, cnt := range coOccurrences {
		edgeList = append(edgeList, edgeEntry{key, cnt})
	}
	sort.Slice(edgeList, func(i, j int) bool { return edgeList[i].count > edgeList[j].count })
	for i, e := range edgeList {
		if i >= 10 {
			break
		}
		edgeParts = append(edgeParts, fmt.Sprintf("%s(%d times)", e.key, e.count))
	}
	edgesStr := strings.Join(edgeParts, ", ")

	// Build user message.
	userMessage := fmt.Sprintf(`The following are the user's knowledge graph statistics:

- Total topics: %d
- New topics in last 7 days: %d
- Domain diversity index: %.2f (0-1)
- Deep topics (depthScore >= 0.5): %s
- Expert topics (depthScore >= 0.8): %s
- Domain distribution: %s
- Learning style statistics: %s
- Most active topics (top 15 by time): %s
- Strongest associations: %s

Please analyze this user's knowledge structure and interest characteristics.`,
		len(allNodes),
		recentCount,
		diversityIndex,
		orNoData(strings.Join(deepTopics, ", ")),
		orNoData(strings.Join(expertTopics, ", ")),
		orNoData(domainStr),
		learningStr,
		orNoData(topByTimeStr),
		orNoData(edgesStr),
	)

	traits, err := m.callAIForTraits(Layer2SystemPrompt+LanguageDirective(m.language), userMessage)
	if err != nil {
		return fmt.Errorf("Layer 2 AI call: %w", err)
	}

	return m.upsertTraits(m.layerRW[1], "knowledge_traits", traits)
}

// effectiveSeconds estimates weighted seconds for an activity record based on engagement.
func effectiveSeconds(rec db.ActivityRecord) int {
	if rec.EngagementLevel == nil {
		return 200
	}
	switch *rec.EngagementLevel {
	case "deep_focus", "active_work":
		return 300
	case "browsing":
		return 150
	case "idle":
		return 0
	default:
		return 200
	}
}

// calculateDepthScore computes a topic depth score using weighted factors, matching the Swift implementation.
func calculateDepthScore(totalTimeSecs, visitCount, revisitDays int, lastSeen time.Time) float64 {
	// timeFactor: normalize total time (cap at 100 hours = 360000 secs)
	timeFactor := math.Min(1.0, float64(totalTimeSecs)/360000.0)

	// revisitFactor: distinct days visited (cap at 30 days)
	revisitFactor := math.Min(1.0, float64(max(revisitDays, 1))/30.0)

	// avgTimeFactor: average time per visit (cap at 30 min = 1800 secs)
	avgTime := 0.0
	if visitCount > 0 {
		avgTime = float64(totalTimeSecs) / float64(visitCount)
	}
	avgTimeFactor := math.Min(1.0, avgTime/1800.0)

	score := timeFactor*0.4 + revisitFactor*0.3 + avgTimeFactor*0.3

	// Recency decay: topics not seen in 30+ days start losing depth score.
	daysSince := math.Max(0, -time.Since(lastSeen).Hours()/24.0)
	if daysSince > 30 {
		recencyFactor := math.Min(1.0, 30.0/daysSince)
		score *= recencyFactor
	}

	return score
}

// buildTopicCoOccurrences builds topic co-occurrence counts from activity records.
// Topics that appear together in the same record or within a 30-minute window are paired.
func buildTopicCoOccurrences(records []db.ActivityRecord) map[string]int {
	coOccurrences := make(map[string]int)

	sorted := make([]db.ActivityRecord, len(records))
	copy(sorted, records)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].Timestamp.Before(sorted[j].Timestamp) })

	const windowSecs = 30 * 60

	for i := 0; i < len(sorted); i++ {
		topicsI := sorted[i].Topics

		// Intra-record pairing.
		for a := 0; a < len(topicsI); a++ {
			for b := a + 1; b < len(topicsI); b++ {
				key := pairKey(topicsI[a], topicsI[b])
				coOccurrences[key]++
			}
		}

		// Cross-record pairing within 30-minute window.
		for j := i + 1; j < len(sorted); j++ {
			diff := sorted[j].Timestamp.Sub(sorted[i].Timestamp).Seconds()
			if diff > float64(windowSecs) {
				break
			}
			for _, tA := range topicsI {
				for _, tB := range sorted[j].Topics {
					if tA != tB {
						key := pairKey(tA, tB)
						coOccurrences[key]++
					}
				}
			}
		}
	}

	return coOccurrences
}

func pairKey(a, b string) string {
	if a < b {
		return a + "<->" + b
	}
	return b + "<->" + a
}

func filterByCategory(records []db.ActivityRecord, category string) []db.ActivityRecord {
	var result []db.ActivityRecord
	for _, r := range records {
		if r.ActivityCategory == category {
			result = append(result, r)
		}
	}
	return result
}

func containsAny(s string, subs ...string) bool {
	for _, sub := range subs {
		if strings.Contains(s, sub) {
			return true
		}
	}
	return false
}

// ─────────────────────────────────────────────
// Layer 3: Cognitive Style
// ─────────────────────────────────────────────

// BehaviorSummary holds the statistical summary for Layer 3 analysis.
type BehaviorSummary struct {
	TotalRecords           int
	AvgSwitchesPerHour     float64
	AvgSessionMinutes      float64
	SearchReadPracticeRatio string
	MultiWindowFrequency   float64
	AvgVisibleAppsCount    float64
	EngagementDistribution map[string]int
	TopApps                []AppCount
	TopIntents             []string
	DominantTopics         []string
	SampleActivities       []string
	ProblemSolvingPatterns  map[string]int
}

// AppCount tracks app name and usage count.
type AppCount struct {
	App   string
	Count int
}

func (m *ModelingEngine) runLayer3(records []db.ActivityRecord) error {
	summary := m.buildBehaviorSummary(records)

	engagementStr := formatMapSorted(summary.EngagementDistribution, " times")
	topAppsStr := formatAppCounts(summary.TopApps, 8)
	topIntentsStr := strings.Join(summary.TopIntents, "; ")
	topTopicsStr := strings.Join(summary.DominantTopics, ", ")
	patternsStr := formatMapSorted(summary.ProblemSolvingPatterns, " times")

	var sampleLines []string
	for i, s := range summary.SampleActivities {
		if i >= 10 {
			break
		}
		sampleLines = append(sampleLines, fmt.Sprintf("[%d] %s", i+1, s))
	}
	sampleStr := strings.Join(sampleLines, "\n")

	userMessage := fmt.Sprintf(`The following is a behavioral statistics summary for the user (based on %d screen activity records):

- Average app switches per hour: %.1f
- Average single app usage duration: %.1f minutes
- Search/read/practice ratio: %s
- Multi-window parallel frequency: %.2f
- Average simultaneously visible apps: %.1f
- Engagement distribution: %s
- Frequently used apps: %s
- Common intents: %s
- Followed topics: %s
- Problem-solving patterns: %s

Activity content samples:
%s

Please analyze this user's cognitive style.`,
		summary.TotalRecords,
		summary.AvgSwitchesPerHour,
		summary.AvgSessionMinutes,
		summary.SearchReadPracticeRatio,
		summary.MultiWindowFrequency,
		summary.AvgVisibleAppsCount,
		orNoData(engagementStr),
		orNoData(topAppsStr),
		orNoData(topIntentsStr),
		orNoData(topTopicsStr),
		orNoData(patternsStr),
		orNoData(sampleStr),
	)

	traits, err := m.callAIForTraits(Layer3SystemPrompt+LanguageDirective(m.language), userMessage)
	if err != nil {
		return fmt.Errorf("Layer 3 AI call: %w", err)
	}

	return m.upsertTraits(m.layerRW[2], "cognitive_traits", traits)
}

func (m *ModelingEngine) buildBehaviorSummary(records []db.ActivityRecord) BehaviorSummary {
	summary := BehaviorSummary{
		TotalRecords:          len(records),
		EngagementDistribution: make(map[string]int),
		ProblemSolvingPatterns: make(map[string]int),
	}

	if len(records) == 0 {
		return summary
	}

	appCounts := make(map[string]int)
	topicCounts := make(map[string]int)
	intentSet := make(map[string]bool)
	var totalVisibleApps int
	var multiWindowCount int
	var searchCount, readCount, practiceCount int

	const minsPerRecord = 5

	for _, rec := range records {
		appCounts[rec.AppName]++

		if rec.EngagementLevel != nil {
			summary.EngagementDistribution[*rec.EngagementLevel]++
		}

		for _, topic := range rec.Topics {
			topicCounts[topic]++
		}

		if rec.UserIntent != nil && *rec.UserIntent != "" {
			intentSet[*rec.UserIntent] = true
		}

		totalVisibleApps += len(rec.VisibleApps)
		if len(rec.VisibleApps) > 2 {
			multiWindowCount++
		}

		// Classify activity for search/read/practice ratio.
		switch rec.ActivityCategory {
		case "learning":
			readCount++
		case "work", "creative":
			practiceCount++
		default:
			searchCount++
		}
	}

	// App switches.
	var switches int
	for i := 1; i < len(records); i++ {
		if records[i].AppName != records[i-1].AppName {
			switches++
		}
	}
	totalHours := float64(len(records)*minsPerRecord) / 60.0
	if totalHours > 0 {
		summary.AvgSwitchesPerHour = float64(switches) / totalHours
	}

	// Average session length approximation.
	if switches > 0 {
		summary.AvgSessionMinutes = float64(len(records)*minsPerRecord) / float64(switches+1)
	} else {
		summary.AvgSessionMinutes = float64(len(records) * minsPerRecord)
	}

	// Search/read/practice ratio.
	total := searchCount + readCount + practiceCount
	if total > 0 {
		summary.SearchReadPracticeRatio = fmt.Sprintf("%.0f%%/%.0f%%/%.0f%%",
			float64(searchCount)/float64(total)*100,
			float64(readCount)/float64(total)*100,
			float64(practiceCount)/float64(total)*100,
		)
	} else {
		summary.SearchReadPracticeRatio = "no data"
	}

	// Multi-window frequency.
	summary.MultiWindowFrequency = float64(multiWindowCount) / float64(len(records))

	// Average visible apps.
	summary.AvgVisibleAppsCount = float64(totalVisibleApps) / float64(len(records))

	// Top apps.
	type ac struct {
		app   string
		count int
	}
	var appList []ac
	for app, count := range appCounts {
		appList = append(appList, ac{app, count})
	}
	sort.Slice(appList, func(i, j int) bool { return appList[i].count > appList[j].count })
	for _, a := range appList {
		summary.TopApps = append(summary.TopApps, AppCount{App: a.app, Count: a.count})
	}

	// Top intents (deduplicated, limited).
	var intents []string
	for intent := range intentSet {
		intents = append(intents, intent)
	}
	if len(intents) > 10 {
		intents = intents[:10]
	}
	summary.TopIntents = intents

	// Dominant topics.
	type tc struct {
		topic string
		count int
	}
	var topicList []tc
	for topic, count := range topicCounts {
		topicList = append(topicList, tc{topic, count})
	}
	sort.Slice(topicList, func(i, j int) bool { return topicList[i].count > topicList[j].count })
	for i, t := range topicList {
		if i >= 10 {
			break
		}
		summary.DominantTopics = append(summary.DominantTopics, t.topic)
	}

	// Sample activities.
	step := len(records) / 10
	if step < 1 {
		step = 1
	}
	for i := 0; i < len(records) && len(summary.SampleActivities) < 10; i += step {
		if records[i].ContentSummary != nil {
			summary.SampleActivities = append(summary.SampleActivities, *records[i].ContentSummary)
		}
	}

	return summary
}

// ─────────────────────────────────────────────
// Layer 4: Expression Style
// ─────────────────────────────────────────────

// writingSample represents a user writing sample for expression analysis.
type writingSample struct {
	Context   string `json:"context"`
	Content   string `json:"content"`
	WordCount int    `json:"wordCount"`
}

func (m *ModelingEngine) runLayer4(records []db.ActivityRecord) error {
	// Collect text samples from user expressions and user authored text.
	const minTextLen = 20
	const minSampleCount = 5
	const maxSamples = 30

	var samples []writingSample

	for _, rec := range records {
		// Determine writing context from app and category.
		ctx := inferWritingContext(rec)

		// Collect individual user expressions.
		for _, expr := range rec.UserExpressions {
			if len(expr) < 5 {
				continue
			}
			content := expr
			if len(content) > 500 {
				content = content[:500]
			}
			samples = append(samples, writingSample{
				Context:   ctx,
				Content:   content,
				WordCount: countWords(content),
			})
		}

		// Collect user authored text.
		if rec.UserAuthored != nil && len(*rec.UserAuthored) >= minTextLen {
			content := *rec.UserAuthored
			if len(content) > 500 {
				content = content[:500]
			}
			samples = append(samples, writingSample{
				Context:   ctx,
				Content:   content,
				WordCount: countWords(content),
			})
		}
	}

	if len(samples) < minSampleCount {
		log.Printf("[ModelingEngine] Layer 4: insufficient text samples (%d/%d), skipping", len(samples), minSampleCount)
		return nil
	}

	// Limit to maxSamples.
	if len(samples) > maxSamples {
		samples = samples[:maxSamples]
	}

	// Build user message with samples.
	var sampleLines []string
	for i, s := range samples {
		sampleLines = append(sampleLines, fmt.Sprintf("[%d] Context: %s, word count: %d\n%s", i+1, s.Context, s.WordCount, s.Content))
	}
	samplesText := strings.Join(sampleLines, "\n\n")

	userMessage := fmt.Sprintf(`The following are %d text samples from the user:

%s

Please analyze this user's expression style.`, len(samples), samplesText)

	// Expression traits analysis.
	traits, err := m.callAIForTraits(Layer4ExpressionSystemPrompt+LanguageDirective(m.language), userMessage)
	if err != nil {
		return fmt.Errorf("Layer 4 expression AI call: %w", err)
	}

	if err := m.upsertTraits(m.layerRW[3], "expression_traits", traits); err != nil {
		return fmt.Errorf("Layer 4 upsert expression traits: %w", err)
	}

	// Style guide generation (only if we have enough samples).
	if len(samples) >= 20 {
		if err := m.generateStyleGuide(samples); err != nil {
			log.Printf("[ModelingEngine] Layer 4 style guide generation failed: %v", err)
		}
	} else {
		log.Printf("[ModelingEngine] Layer 4: insufficient samples for style guide (%d/20)", len(samples))
	}

	return nil
}

// generateStyleGuide calls AI with Layer4StyleGuideSystemPrompt and stores the result as traits.
func (m *ModelingEngine) generateStyleGuide(samples []writingSample) error {
	// Build samples text for style guide (use all samples).
	var sampleLines []string
	for i, s := range samples {
		sampleLines = append(sampleLines, fmt.Sprintf("[%d] (%s) %s", i+1, s.Context, s.Content))
	}
	samplesText := strings.Join(sampleLines, "\n")

	userMessage := fmt.Sprintf(`The following are %d text samples from the user:

%s

Please generate this user's expression style guide.`, len(samples), samplesText)

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	resp, err := m.aiClient.ChatCompletion(ctx, ai.ChatRequest{
		Messages: []ai.Message{
			{Role: "system", Content: Layer4StyleGuideSystemPrompt + LanguageDirective(m.language)},
			{Role: "user", Content: userMessage},
		},
	})
	if err != nil {
		return fmt.Errorf("style guide AI call: %w", err)
	}

	if len(resp.Choices) == 0 {
		return fmt.Errorf("empty style guide response")
	}

	content := resp.Choices[0].Message.Content

	// Parse the style guide response.
	var sgResp map[string]interface{}
	if err := json.Unmarshal([]byte(content), &sgResp); err != nil {
		return fmt.Errorf("parse style guide response: %w", err)
	}

	anchor, _ := sgResp["style_anchor"].(string)

	// Re-serialize differentiators and examples as JSON strings.
	diffsJSON, _ := json.Marshal(sgResp["differentiators"])
	examplesJSON, _ := json.Marshal(sgResp["selected_examples"])

	confidence := math.Min(1.0, float64(len(samples))/100.0)

	// Store as three trait dimensions.
	styleTraits := []ParsedTrait{
		{Dimension: "style_anchor", Value: anchor, Confidence: confidence},
		{Dimension: "key_differentiators", Value: string(diffsJSON), Confidence: confidence},
		{Dimension: "curated_examples", Value: string(examplesJSON), Confidence: confidence},
	}

	return m.upsertTraits(m.layerRW[3], "expression_traits", styleTraits)
}

// inferWritingContext maps an activity record's app and category to a writing context label.
func inferWritingContext(rec db.ActivityRecord) string {
	app := strings.ToLower(rec.AppName)
	cat := strings.ToLower(rec.ActivityCategory)

	switch {
	case containsAny(app, "slack", "discord", "telegram", "wechat", "teams",
		"messages", "dingtalk", "feishu", "lark") || cat == "social":
		return "work_chat"
	case containsAny(app, "mail", "outlook"):
		return "email"
	case containsAny(app, "xcode", "vscode", "visual studio", "intellij", "sublime", "vim",
		"cursor", "terminal", "iterm", "warp", "powershell", "cmd"):
		return "code_comment"
	case containsAny(app, "safari", "chrome", "firefox", "edge", "arc", "brave"):
		return "browser"
	case containsAny(app, "pages", "word", "notion", "obsidian", "bear", "notes",
		"typora", "ulysses") || cat == "creative":
		return "document"
	default:
		return "other"
	}
}

// countWords counts words in text, handling both CJK and Latin text.
func countWords(text string) int {
	return len(strings.Fields(text))
}

// ─────────────────────────────────────────────
// Layer 5: Values & Priorities
// ─────────────────────────────────────────────

func (m *ModelingEngine) runLayer5(records []db.ActivityRecord) error {
	const minRecordCount = 100

	if len(records) < minRecordCount {
		log.Printf("[ModelingEngine] Layer 5: insufficient records (%d/%d), skipping", len(records), minRecordCount)
		return nil
	}

	// 1. Category distribution.
	categoryDist := make(map[string]int)
	for _, rec := range records {
		categoryDist[rec.ActivityCategory]++
	}

	categoryDistStr := formatMapSorted(categoryDist, "")

	// Category time estimates (each record ~ 5 min).
	categoryTimeEst := make(map[string]int)
	for cat, cnt := range categoryDist {
		categoryTimeEst[cat] = cnt * 5
	}
	categoryTimeStr := formatMapSorted(categoryTimeEst, " min")

	// 2. Persistent topics from knowledge nodes (Layer 2 DB).
	persistentTopics := m.fetchPersistentTopics()
	topicsStr := strings.Join(persistentTopics, ", ")

	// 3. Work/life ratio from activity categories.
	workCount := categoryDist["work"] + categoryDist["learning"]
	lifeCount := categoryDist["entertainment"] + categoryDist["social"]
	totalWL := workCount + lifeCount
	workLifeRatio := 0.5
	if totalWL > 0 {
		workLifeRatio = float64(workCount) / float64(totalWL)
	}

	// 4. Engagement breakdown.
	engagementBreakdown := make(map[string]int)
	for _, rec := range records {
		if rec.EngagementLevel != nil {
			engagementBreakdown[*rec.EngagementLevel]++
		}
	}
	engagementStr := formatMapSorted(engagementBreakdown, "")

	// 5. Learning record count.
	learningCount := categoryDist["learning"]

	// 6. App switch patterns.
	switchPatterns := buildSwitchPatterns(records)
	switchStr := strings.Join(switchPatterns, ", ")

	// 7. Content summaries (sampled).
	var contentSummaries []string
	for _, rec := range records {
		if rec.ContentSummary != nil && *rec.ContentSummary != "" {
			s := *rec.ContentSummary
			if len(s) > 200 {
				s = s[:200]
			}
			contentSummaries = append(contentSummaries, s)
		}
	}
	// Take last 30, then sample 20 for the prompt.
	if len(contentSummaries) > 30 {
		contentSummaries = contentSummaries[len(contentSummaries)-30:]
	}
	var contentLines []string
	for i, s := range contentSummaries {
		if i >= 20 {
			break
		}
		contentLines = append(contentLines, fmt.Sprintf("[%d] %s", i+1, s))
	}
	contentSummariesStr := strings.Join(contentLines, "\n")

	// 8. User intents (sampled).
	var userIntents []string
	for _, rec := range records {
		if rec.UserIntent != nil && *rec.UserIntent != "" {
			s := *rec.UserIntent
			if len(s) > 150 {
				s = s[:150]
			}
			userIntents = append(userIntents, s)
		}
	}
	if len(userIntents) > 20 {
		userIntents = userIntents[len(userIntents)-20:]
	}
	var intentLines []string
	for i, s := range userIntents {
		if i >= 15 {
			break
		}
		intentLines = append(intentLines, fmt.Sprintf("[%d] %s", i+1, s))
	}
	userIntentsStr := strings.Join(intentLines, "\n")

	// Build user message.
	userMessage := fmt.Sprintf(`The following are the user's long-term behavior statistics (based on %d records):

- Activity category distribution: %s
- Estimated time per category: %s
- Persistently followed topics: %s
- Work/life time ratio: %.2f
- Engagement distribution: %s
- Learning-related record count: %d
- App switching patterns (top 10 by frequency): %s

User activity content summaries (sampled):
%s

User intent inferences (sampled):
%s

Please infer this user's deep values.`,
		len(records),
		orNoData(categoryDistStr),
		orNoData(categoryTimeStr),
		orNoData(topicsStr),
		workLifeRatio,
		orNoData(engagementStr),
		learningCount,
		orNoData(switchStr),
		orNoData(contentSummariesStr),
		orNoData(userIntentsStr),
	)

	traits, err := m.callAIForTraits(Layer5SystemPrompt+LanguageDirective(m.language), userMessage)
	if err != nil {
		return fmt.Errorf("Layer 5 AI call: %w", err)
	}

	return m.upsertTraits(m.layerRW[4], "value_traits", traits)
}

// fetchPersistentTopics retrieves the top knowledge topics from the Layer 2 database.
func (m *ModelingEngine) fetchPersistentTopics() []string {
	if m.layerRW[1] == nil {
		return nil
	}

	rows, err := m.layerRW[1].Query(`
		SELECT topic FROM knowledge_nodes
		ORDER BY totalTimeSpent DESC
		LIMIT 10
	`)
	if err != nil {
		// Table may not exist yet; that's fine.
		log.Printf("[ModelingEngine] Layer 5: failed to fetch knowledge nodes: %v", err)
		return nil
	}
	defer rows.Close()

	var topics []string
	for rows.Next() {
		var topic string
		if err := rows.Scan(&topic); err != nil {
			continue
		}
		topics = append(topics, topic)
	}
	return topics
}

// buildSwitchPatterns builds top app switch patterns like ["Xcode->Slack:15", "Slack->Xcode:12"].
func buildSwitchPatterns(records []db.ActivityRecord) []string {
	sorted := make([]db.ActivityRecord, len(records))
	copy(sorted, records)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].Timestamp.Before(sorted[j].Timestamp) })

	patterns := make(map[string]int)
	for i := 1; i < len(sorted); i++ {
		prev := sorted[i-1].AppName
		curr := sorted[i].AppName
		if prev != curr {
			patterns[prev+"->"+curr]++
		}
	}

	type pc struct {
		key   string
		count int
	}
	var list []pc
	for k, v := range patterns {
		list = append(list, pc{k, v})
	}
	sort.Slice(list, func(i, j int) bool { return list[i].count > list[j].count })

	var result []string
	for i, p := range list {
		if i >= 10 {
			break
		}
		result = append(result, fmt.Sprintf("%s:%d", p.key, p.count))
	}
	return result
}

// ─────────────────────────────────────────────
// Snapshot & Personality Assessments
// ─────────────────────────────────────────────

func (m *ModelingEngine) generateSnapshot() error {
	// Gather all traits from all layers.
	allTraits := make(map[string][]ParsedTrait)

	layerNames := map[int]string{
		1: "rhythm_traits",
		2: "knowledge_traits",
		3: "cognitive_traits",
		4: "expression_traits",
		5: "value_traits",
	}

	for layer := 1; layer <= 5; layer++ {
		layerDB := m.layerRW[layer-1]
		if layerDB == nil {
			continue
		}
		tableName := layerNames[layer]
		traits, err := m.fetchTraitsFromDB(layerDB, tableName)
		if err != nil {
			log.Printf("[ModelingEngine] Failed to fetch Layer %d traits: %v", layer, err)
			continue
		}
		if len(traits) > 0 {
			allTraits[fmt.Sprintf("layer%d", layer)] = traits
		}
	}

	if len(allTraits) == 0 {
		log.Println("[ModelingEngine] No traits available for snapshot")
		return nil
	}

	traitsJSON, err := json.MarshalIndent(allTraits, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal traits: %w", err)
	}

	userMessage := fmt.Sprintf("The following is the user's multi-dimensional trait data (JSON format):\n\n%s\n\nPlease generate a personality profile description.", string(traitsJSON))

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	resp, err := m.aiClient.ChatCompletion(ctx, ai.ChatRequest{
		Messages: []ai.Message{
			{Role: "system", Content: SnapshotSummarySystemPrompt + LanguageDirective(m.language)},
			{Role: "user", Content: userMessage},
		},
	})
	if err != nil {
		return fmt.Errorf("snapshot AI call: %w", err)
	}

	if len(resp.Choices) == 0 {
		return fmt.Errorf("empty snapshot response")
	}

	summaryText := resp.Choices[0].Message.Content

	// Store snapshot using own read-write connection.
	if m.snapshotRW == nil {
		return fmt.Errorf("snapshot database not available")
	}

	_, err = m.snapshotRW.Exec(`
		INSERT INTO personality_snapshots (id, snapshotDate, fullProfile, summaryText, trigger)
		VALUES (?, ?, ?, ?, ?)`,
		uuid.New().String(),
		db.FormatGRDBDate(time.Now()),
		string(traitsJSON),
		summaryText,
		"scheduled",
	)
	return err
}

func (m *ModelingEngine) runPersonalityAssessments() error {
	// Gather all traits for MBTI and Big Five analysis.
	allTraits := make(map[string][]ParsedTrait)
	layerNames := map[int]string{
		1: "rhythm_traits",
		2: "knowledge_traits",
		3: "cognitive_traits",
		4: "expression_traits",
		5: "value_traits",
	}

	for layer := 1; layer <= 5; layer++ {
		layerDB := m.layerRW[layer-1]
		if layerDB == nil {
			continue
		}
		traits, err := m.fetchTraitsFromDB(layerDB, layerNames[layer])
		if err != nil {
			continue
		}
		if len(traits) > 0 {
			allTraits[fmt.Sprintf("layer%d", layer)] = traits
		}
	}

	if len(allTraits) == 0 {
		return fmt.Errorf("no traits available for personality assessment")
	}

	traitsJSON, err := json.MarshalIndent(allTraits, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal traits: %w", err)
	}

	// Run MBTI analysis.
	mbtiUserMsg := fmt.Sprintf("The following is the user's multi-dimensional personality trait data:\n\n%s\n\nBased on all the above data, please infer this user's MBTI type.", string(traitsJSON))

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	mbtiResp, err := m.aiClient.ChatCompletion(ctx, ai.ChatRequest{
		Messages: []ai.Message{
			{Role: "system", Content: MBTIAnalysisSystemPrompt + LanguageDirective(m.language)},
			{Role: "user", Content: mbtiUserMsg},
		},
	})
	if err != nil {
		log.Printf("[ModelingEngine] MBTI analysis failed: %v", err)
	} else if len(mbtiResp.Choices) > 0 {
		mbtiResult := mbtiResp.Choices[0].Message.Content
		log.Printf("[ModelingEngine] MBTI result: %s", mbtiResult)
		if err := m.storeAssessmentResult("mbti", mbtiResult); err != nil {
			log.Printf("[ModelingEngine] Failed to store MBTI result: %v", err)
		}
	}

	// Run Big Five analysis.
	bigFiveUserMsg := fmt.Sprintf("The following is the user's multi-dimensional personality trait data:\n\n%s\n\nBased on all the above data, please infer this user's Big Five personality traits.", string(traitsJSON))

	ctx2, cancel2 := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel2()

	bigFiveResp, err := m.aiClient.ChatCompletion(ctx2, ai.ChatRequest{
		Messages: []ai.Message{
			{Role: "system", Content: BigFiveAnalysisSystemPrompt + LanguageDirective(m.language)},
			{Role: "user", Content: bigFiveUserMsg},
		},
	})
	if err != nil {
		log.Printf("[ModelingEngine] Big Five analysis failed: %v", err)
	} else if len(bigFiveResp.Choices) > 0 {
		bigFiveResult := bigFiveResp.Choices[0].Message.Content
		log.Printf("[ModelingEngine] Big Five result: %s", bigFiveResult)
		if err := m.storeAssessmentResult("big_five", bigFiveResult); err != nil {
			log.Printf("[ModelingEngine] Failed to store Big Five result: %v", err)
		}
	}

	return nil
}

// storeAssessmentResult stores a personality assessment (MBTI or Big Five) result
// in the snapshots database. It updates the latest snapshot's fullProfile to include
// the assessment data, or inserts a new assessment-only snapshot.
func (m *ModelingEngine) storeAssessmentResult(assessmentType, resultJSON string) error {
	if m.snapshotRW == nil {
		return fmt.Errorf("snapshot database not available")
	}

	// Ensure personality_assessments table exists.
	_, err := m.snapshotRW.Exec(`
		CREATE TABLE IF NOT EXISTS personality_assessments (
			id TEXT PRIMARY KEY,
			assessmentType TEXT NOT NULL,
			resultJSON TEXT NOT NULL,
			createdAt DATETIME NOT NULL
		)
	`)
	if err != nil {
		return fmt.Errorf("create personality_assessments table: %w", err)
	}

	_, err = m.snapshotRW.Exec(`
		INSERT INTO personality_assessments (id, assessmentType, resultJSON, createdAt)
		VALUES (?, ?, ?, ?)`,
		uuid.New().String(),
		assessmentType,
		resultJSON,
		db.FormatGRDBDate(time.Now()),
	)
	return err
}

// ─────────────────────────────────────────────
// Shared AI & DB helpers
// ─────────────────────────────────────────────

func (m *ModelingEngine) callAIForTraits(systemPrompt, userMessage string) ([]ParsedTrait, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	resp, err := m.aiClient.ChatCompletion(ctx, ai.ChatRequest{
		Messages: []ai.Message{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userMessage},
		},
	})
	if err != nil {
		return nil, fmt.Errorf("AI call: %w", err)
	}

	if len(resp.Choices) == 0 {
		return nil, fmt.Errorf("empty AI response")
	}

	content := resp.Choices[0].Message.Content

	var traitsResp TraitsResponse
	if err := json.Unmarshal([]byte(content), &traitsResp); err != nil {
		return nil, fmt.Errorf("parse traits response: %w", err)
	}

	return traitsResp.Traits, nil
}

func (m *ModelingEngine) upsertTraits(layerDB *sql.DB, tableName string, traits []ParsedTrait) error {
	if layerDB == nil {
		return fmt.Errorf("layer database not available")
	}

	for _, trait := range traits {
		var descPtr *string
		if trait.Description != "" {
			descPtr = &trait.Description
		}

		_, err := layerDB.Exec(fmt.Sprintf(`
			INSERT INTO %s (id, dimension, value, description, confidence, evidenceCount, firstObserved, lastUpdated, version)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)
			ON CONFLICT(dimension) DO UPDATE SET
				value = excluded.value,
				description = excluded.description,
				confidence = excluded.confidence,
				evidenceCount = COALESCE(evidenceCount, 0) + 1,
				lastUpdated = excluded.lastUpdated,
				version = version + 1
		`, tableName),
			uuid.New().String(),
			trait.Dimension,
			trait.Value,
			descPtr,
			trait.Confidence,
			1,
			db.FormatGRDBDate(time.Now()),
			db.FormatGRDBDate(time.Now()),
		)
		if err != nil {
			log.Printf("[ModelingEngine] Failed to upsert trait %s: %v", trait.Dimension, err)
		}
	}

	return nil
}

func (m *ModelingEngine) fetchTraitsFromDB(layerDB *sql.DB, tableName string) ([]ParsedTrait, error) {
	query := fmt.Sprintf("SELECT dimension, value, confidence, description FROM %s", tableName)
	rows, err := layerDB.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var traits []ParsedTrait
	for rows.Next() {
		var t ParsedTrait
		var desc sql.NullString
		if err := rows.Scan(&t.Dimension, &t.Value, &t.Confidence, &desc); err != nil {
			return nil, err
		}
		if desc.Valid {
			t.Description = desc.String
		}
		traits = append(traits, t)
	}
	return traits, rows.Err()
}

// ─────────────────────────────────────────────
// Formatting helpers
// ─────────────────────────────────────────────

func formatTopApps(apps []AppUsage, limit int) string {
	var parts []string
	for i, a := range apps {
		if i >= limit {
			break
		}
		parts = append(parts, fmt.Sprintf("%s(%d min)", a.Name, a.Mins))
	}
	return strings.Join(parts, ", ")
}

func formatPeakHours(hours []int) string {
	var parts []string
	for _, h := range hours {
		parts = append(parts, fmt.Sprintf("%d:00", h))
	}
	return strings.Join(parts, ", ")
}

func formatAppCounts(apps []AppCount, limit int) string {
	var parts []string
	for i, a := range apps {
		if i >= limit {
			break
		}
		parts = append(parts, fmt.Sprintf("%s(%d times)", a.App, a.Count))
	}
	return strings.Join(parts, ", ")
}

func formatMapSorted(m map[string]int, unit string) string {
	type kv struct {
		key   string
		value int
	}
	var sorted []kv
	for k, v := range m {
		sorted = append(sorted, kv{k, v})
	}
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].value > sorted[j].value })

	var parts []string
	for _, item := range sorted {
		parts = append(parts, fmt.Sprintf("%s: %d%s", item.key, item.value, unit))
	}
	return strings.Join(parts, ", ")
}

func orNoData(s string) string {
	if s == "" {
		return "no data"
	}
	return s
}

func sumFloat(vals []float64) float64 {
	var s float64
	for _, v := range vals {
		s += v
	}
	return s
}

func avgFloat(vals []float64) float64 {
	if len(vals) == 0 {
		return 0
	}
	return sumFloat(vals) / float64(len(vals))
}

func maxFloat(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}

func countWeekdays(daySet map[string]bool) int {
	count := 0
	for day := range daySet {
		t, err := time.Parse("2006-01-02", day)
		if err != nil {
			continue
		}
		wd := t.Weekday()
		if wd != time.Saturday && wd != time.Sunday {
			count++
		}
	}
	return count
}

func countWeekends(daySet map[string]bool) int {
	count := 0
	for day := range daySet {
		t, err := time.Parse("2006-01-02", day)
		if err != nil {
			continue
		}
		wd := t.Weekday()
		if wd == time.Saturday || wd == time.Sunday {
			count++
		}
	}
	return count
}
