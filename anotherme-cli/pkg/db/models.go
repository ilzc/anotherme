package db

import (
	"time"
)

const GRDBDateFormat = "2006-01-02 15:04:05.000"

// dateFormats lists all formats we might encounter in the database.
var dateFormats = []string{
	GRDBDateFormat,                // GRDB default: "2006-01-02 15:04:05.000"
	"2006-01-02 15:04:05",        // without millis
	time.RFC3339,                  // "2006-01-02T15:04:05Z07:00"
	"2006-01-02T15:04:05.000Z",   // ISO8601 with millis
	"2006-01-02T15:04:05.999Z",   // ISO8601 with variable millis
	"2006-01-02T15:04:05Z",       // ISO8601 without millis
}

func ParseGRDBDate(s string) (time.Time, error) {
	for _, layout := range dateFormats {
		if t, err := time.Parse(layout, s); err == nil {
			return t, nil
		}
	}
	return time.Time{}, &time.ParseError{Value: s, Message: "no matching date format"}
}

func FormatGRDBDate(t time.Time) string {
	return t.UTC().Format(GRDBDateFormat)
}

// ActivityRecord corresponds to the activity_logs table in activity.sqlite.
type ActivityRecord struct {
	ID               string
	Timestamp        time.Time
	AppName          string
	WindowTitle      string
	ExtractedText    *string
	ContentSummary   *string
	UserIntent       *string
	ActivityCategory string
	Topics           []string // JSON array in DB
	ScreenIndex      int
	CaptureMode      string
	Analyzed         bool
	VisibleApps      []string // JSON array, nullable
	UserAuthored     *string
	UserExpressions  []string // JSON array, nullable
	EngagementLevel  *string
}

// Trait represents a personality trait from any layer (1-5).
//
//	Layer 1: rhythm_traits   (in layer1.sqlite)
//	Layer 2: knowledge_traits (in layer2.sqlite)
//	Layer 3: cognitive_traits (in layer3.sqlite) – has Description
//	Layer 4: expression_traits (in layer4.sqlite)
//	Layer 5: value_traits     (in layer5.sqlite) – has Description
type Trait struct {
	ID            string
	Dimension     string
	Value         string
	Description   *string    // Only L3, L5
	Confidence    float64
	EvidenceCount *int       // L1, L3, L5
	FirstObserved *time.Time // L1, L3, L5
	LastUpdated   time.Time
	Version       int
	Layer         int // Set by code, not stored in DB
}

// Memory corresponds to the memories table in memory.sqlite.
type Memory struct {
	ID             string
	Content        string
	Category       string
	Keywords       []string // JSON array in DB
	Importance     float64
	AccessCount    int
	Pinned         bool
	SourceType     string
	SourceID       *string
	CreatedAt      time.Time
	LastAccessedAt time.Time
}

// ChatSession corresponds to the chat_sessions table in chat.sqlite.
type ChatSession struct {
	ID        string
	CreatedAt time.Time
	Title     string
}

// ChatMessage corresponds to the chat_messages table in chat.sqlite.
type ChatMessage struct {
	ID               string
	SessionID        string
	Timestamp        time.Time
	Role             string
	Content          string
	ReferencedLayers []int             // JSON array in DB
	ReferencedData   map[string]string // JSON object in DB
}

// Insight corresponds to the insights table in insights.sqlite.
type Insight struct {
	ID            string
	CreatedAt     time.Time
	Type          string
	Title         string
	Content       string
	RelatedLayers []int // JSON array in DB
	Notified      bool
}

// PersonalitySnapshot corresponds to the personality_snapshots table in snapshots.sqlite.
type PersonalitySnapshot struct {
	ID           string
	SnapshotDate time.Time
	FullProfile  string  // JSON string
	SummaryText  *string
	Trigger      string
}
