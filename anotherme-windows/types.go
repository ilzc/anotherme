package main

import "time"

// DashboardStats holds summary statistics for the dashboard view.
type DashboardStats struct {
	TotalActivities   int            `json:"totalActivities"`
	TodayActivities   int            `json:"todayActivities"`
	TotalMemories     int            `json:"totalMemories"`
	TotalTraits       int            `json:"totalTraits"`
	TraitsPerLayer    map[int]int    `json:"traitsPerLayer"`
	TotalInsights     int            `json:"totalInsights"`
	TotalChatSessions int            `json:"totalChatSessions"`
	LatestCapture     *time.Time     `json:"latestCapture"`
	CaptureRunning    bool           `json:"captureRunning"`
}

// CaptureStatus represents the current state of screen capture.
type CaptureStatus struct {
	Running       bool       `json:"running"`
	StartedAt     *time.Time `json:"startedAt"`
	CaptureCount  int        `json:"captureCount"`
	ErrorMessage  string     `json:"errorMessage,omitempty"`
}

// ChatStreamResult holds the result of a streaming chat response.
type ChatStreamResult struct {
	SessionID string `json:"sessionId"`
	MessageID string `json:"messageId"`
	Content   string `json:"content"`
}
