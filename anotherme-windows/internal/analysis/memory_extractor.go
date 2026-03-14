package analysis

import (
	"strings"
	"time"
)

// MemoryCandidate represents a potential memory extracted from an activity record.
type MemoryCandidate struct {
	Content    string
	Category   string  // topic, intent, habit, opinion, milestone
	Keywords   []string
	Importance float64
	SourceType string // "activity"
}

// ExtractMemory extracts a memory candidate from an analysis result.
// Returns nil if the activity is too low-value to warrant a memory (idle/browsing)
// or if no meaningful topics were detected.
func ExtractMemory(result *AnalysisResult, capturedAt time.Time) *MemoryCandidate {
	_ = capturedAt // reserved for future time-based filtering

	// Skip if no topics detected.
	if len(result.Topics) == 0 {
		return nil
	}

	// Skip low-value activities — idle and casual browsing are not worth remembering.
	engagement := result.EngagementLevel
	if engagement == "idle" || engagement == "browsing" {
		return nil
	}

	// Convert content_summary from third person to first person.
	content := toFirstPerson(result.ContentSummary)

	return &MemoryCandidate{
		Content:    content,
		Category:   categorize(result.ActivityCategory),
		Keywords:   result.Topics,
		Importance: importanceScore(engagement),
		SourceType: "activity",
	}
}

// toFirstPerson rewrites a third-person observation ("The user is...") to first person.
func toFirstPerson(text string) string {
	// Remove common third-person prefixes used by the AI.
	// Order from longest to shortest to strip the longest matching prefix first.
	prefixes := []string{
		"The user is currently ",
		"The user is ",
		"User is currently ",
		"User is ",
		"The user ",
		"User ",
	}
	for _, prefix := range prefixes {
		if strings.HasPrefix(text, prefix) {
			rest := text[len(prefix):]
			// Lowercase the first character of the remaining text.
			if len(rest) > 0 {
				runes := []rune(rest)
				if runes[0] >= 'A' && runes[0] <= 'Z' {
					runes[0] = runes[0] + 32
				}
				rest = string(runes)
			}
			return rest
		}
	}
	return text
}

// categorize maps an activity category to a memory category.
func categorize(activityCategory string) string {
	switch activityCategory {
	case "work":
		return "topic"
	case "learning":
		return "topic"
	case "creative":
		return "topic"
	case "social":
		return "intent"
	case "entertainment":
		return "habit"
	default:
		return "topic"
	}
}

// importanceScore assigns an importance score based on engagement level.
func importanceScore(engagement string) float64 {
	switch engagement {
	case "deep_focus":
		return 0.8
	case "active_work":
		return 0.6
	case "browsing":
		return 0.3
	case "idle":
		return 0.1
	default:
		return 0.5
	}
}
