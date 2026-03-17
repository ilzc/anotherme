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
	ID               string    `json:"id"`
	Timestamp        time.Time `json:"timestamp"`
	AppName          string    `json:"appName"`
	WindowTitle      string    `json:"windowTitle"`
	ExtractedText    *string   `json:"extractedText,omitempty"`
	ContentSummary   *string   `json:"contentSummary,omitempty"`
	UserIntent       *string   `json:"userIntent,omitempty"`
	ActivityCategory string    `json:"activityCategory"`
	Topics           []string  `json:"topics"`
	ScreenIndex      int       `json:"screenIndex"`
	CaptureMode      string    `json:"captureMode"`
	Analyzed         bool      `json:"analyzed"`
	VisibleApps      []string  `json:"visibleApps"`
	UserAuthored     *string   `json:"userAuthored,omitempty"`
	UserExpressions  []string  `json:"userExpressions"`
	EngagementLevel  *string   `json:"engagementLevel,omitempty"`
}

// Trait represents a personality trait from any layer (1-5).
//
//	Layer 1: rhythm_traits   (in layer1.sqlite)
//	Layer 2: knowledge_traits (in layer2.sqlite)
//	Layer 3: cognitive_traits (in layer3.sqlite) – has Description
//	Layer 4: expression_traits (in layer4.sqlite)
//	Layer 5: value_traits     (in layer5.sqlite) – has Description
type Trait struct {
	ID            string     `json:"id"`
	Dimension     string     `json:"dimension"`
	Value         string     `json:"value"`
	Description   *string    `json:"description,omitempty"`
	Confidence    float64    `json:"confidence"`
	EvidenceCount *int       `json:"evidenceCount,omitempty"`
	FirstObserved *time.Time `json:"firstObserved,omitempty"`
	LastUpdated   time.Time  `json:"lastUpdated"`
	Version       int        `json:"version"`
	Layer         int        `json:"layer"`
}

// Memory corresponds to the memories table in memory.sqlite.
type Memory struct {
	ID             string    `json:"id"`
	Content        string    `json:"content"`
	Category       string    `json:"category"`
	Keywords       []string  `json:"keywords"`
	Importance     float64   `json:"importance"`
	AccessCount    int       `json:"accessCount"`
	Pinned         bool      `json:"isPinned"`
	SourceType     string    `json:"sourceType"`
	SourceID       *string   `json:"sourceId,omitempty"`
	CreatedAt      time.Time `json:"createdAt"`
	LastAccessedAt time.Time `json:"updatedAt"`
}

// ChatSession corresponds to the chat_sessions table in chat.sqlite.
type ChatSession struct {
	ID        string    `json:"id"`
	CreatedAt time.Time `json:"createdAt"`
	Title     string    `json:"title"`
}

// ChatMessage corresponds to the chat_messages table in chat.sqlite.
type ChatMessage struct {
	ID               string            `json:"id"`
	SessionID        string            `json:"sessionId"`
	Timestamp        time.Time         `json:"timestamp"`
	Role             string            `json:"role"`
	Content          string            `json:"content"`
	ReferencedLayers []int             `json:"referencedLayers,omitempty"`
	ReferencedData   map[string]string `json:"referencedData,omitempty"`
}

// Insight corresponds to the insights table in insights.sqlite.
type Insight struct {
	ID            string    `json:"id"`
	CreatedAt     time.Time `json:"createdAt"`
	Type          string    `json:"type"`
	Title         string    `json:"title"`
	Content       string    `json:"content"`
	RelatedLayers []int     `json:"relatedLayers,omitempty"`
	Notified      bool      `json:"notified"`
}

// PersonalitySnapshot corresponds to the personality_snapshots table in snapshots.sqlite.
type PersonalitySnapshot struct {
	ID           string    `json:"id"`
	SnapshotDate time.Time `json:"generatedAt"`
	FullProfile  string    `json:"fullProfile"`
	SummaryText  *string   `json:"summary,omitempty"`
	Trigger      string    `json:"trigger"`
}
