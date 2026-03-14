package agent

import (
	"database/sql"
	"fmt"
	"sort"
	"strings"
	"time"
	"unicode"

	"github.com/user/anotherme-cli/pkg/db"
)

// MemoryRetriever searches and ranks memories with time-decay weighting.
type MemoryRetriever struct {
	memDB *sql.DB
}

// NewMemoryRetriever creates a new MemoryRetriever.
func NewMemoryRetriever(memDB *sql.DB) *MemoryRetriever {
	return &MemoryRetriever{memDB: memDB}
}

// Recall extracts keywords from the query, searches memories by keyword,
// and ranks results by recency-weighted importance.
func (mr *MemoryRetriever) Recall(query string, limit int) ([]db.Memory, error) {
	keywords := extractKeywords(query)
	if len(keywords) == 0 {
		return nil, nil
	}

	// Search by each keyword and deduplicate
	seen := make(map[string]db.Memory)
	for _, kw := range keywords {
		results, err := db.SearchMemories(mr.memDB, kw, limit*2)
		if err != nil {
			continue
		}
		for _, m := range results {
			if _, exists := seen[m.ID]; !exists {
				seen[m.ID] = m
			}
		}
	}

	// Collect and rank by recency-weighted importance
	memories := make([]db.Memory, 0, len(seen))
	for _, m := range seen {
		memories = append(memories, m)
	}

	now := time.Now()
	sort.Slice(memories, func(i, j int) bool {
		scoreI := recencyScore(memories[i], now)
		scoreJ := recencyScore(memories[j], now)
		return scoreI > scoreJ
	})

	if len(memories) > limit {
		memories = memories[:limit]
	}

	return memories, nil
}

// FormatMemories formats a list of memories as "- (date) content" lines.
// Returns nil if the list is empty.
func FormatMemories(memories []db.Memory) *string {
	if len(memories) == 0 {
		return nil
	}

	var sb strings.Builder
	for _, m := range memories {
		sb.WriteString(fmt.Sprintf("- (%s) %s\n", m.CreatedAt.Format("2006-01-02"), m.Content))
	}

	result := sb.String()
	return &result
}

// recencyScore computes importance * (1.0 / (1.0 + daysSince / 7.0)).
func recencyScore(m db.Memory, now time.Time) float64 {
	daysSince := now.Sub(m.CreatedAt).Hours() / 24.0
	if daysSince < 0 {
		daysSince = 0
	}
	return m.Importance * (1.0 / (1.0 + daysSince/7.0))
}

// extractKeywords splits the query by non-alphanumeric characters (including CJK awareness),
// filters tokens of length >= 2, and returns top 5.
func extractKeywords(query string) []string {
	// Split by non-letter, non-number boundaries
	tokens := strings.FieldsFunc(query, func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsNumber(r)
	})

	// Filter by length >= 2 (rune count for CJK support)
	var keywords []string
	seen := make(map[string]bool)
	for _, t := range tokens {
		t = strings.TrimSpace(t)
		runeCount := len([]rune(t))
		if runeCount >= 2 && !seen[t] {
			keywords = append(keywords, t)
			seen[t] = true
		}
	}

	// Take top 5
	if len(keywords) > 5 {
		keywords = keywords[:5]
	}

	return keywords
}
