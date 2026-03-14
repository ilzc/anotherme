package notification

import (
	"log"
	"strings"
	"sync"
)

// Notifier tracks consecutive AI failures per function and determines
// when a function should be paused due to repeated errors.
type Notifier struct {
	consecutiveFailures map[string]int
	pauseThreshold      int
	mu                  sync.Mutex
}

// NewNotifier creates a new Notifier instance.
func NewNotifier() *Notifier {
	return &Notifier{
		consecutiveFailures: make(map[string]int),
		pauseThreshold:      3,
	}
}

// OnAIFailure records a failure for the given function and sends a notification
// on the first failure. After pauseThreshold consecutive failures, the function
// is considered paused.
func (n *Notifier) OnAIFailure(function string, err error) {
	n.mu.Lock()
	n.consecutiveFailures[function]++
	count := n.consecutiveFailures[function]
	n.mu.Unlock()

	if count == 1 {
		sendNotification("AnotherMe", formatErrorMessage(err))
	}

	if count >= n.pauseThreshold {
		log.Printf("[Notifier] %s: %d consecutive failures, auto-paused", function, count)
	}
}

// OnAISuccess resets the failure counter for the given function.
func (n *Notifier) OnAISuccess(function string) {
	n.mu.Lock()
	defer n.mu.Unlock()
	n.consecutiveFailures[function] = 0
}

// ShouldPause returns true if the function has reached the consecutive failure
// threshold and should be temporarily paused.
func (n *Notifier) ShouldPause(function string) bool {
	n.mu.Lock()
	defer n.mu.Unlock()
	return n.consecutiveFailures[function] >= n.pauseThreshold
}

// ResetPause clears the failure counter for a function, allowing it to resume.
func (n *Notifier) ResetPause(function string) {
	n.mu.Lock()
	defer n.mu.Unlock()
	n.consecutiveFailures[function] = 0
}

func formatErrorMessage(err error) string {
	if err == nil {
		return "AI analysis encountered a problem"
	}
	msg := err.Error()
	// Provide user-friendly messages for common errors.
	switch {
	case strings.Contains(msg, "401") || strings.Contains(msg, "unauthorized"):
		return "Invalid API Key, please check settings"
	case strings.Contains(msg, "429") || strings.Contains(msg, "rate"):
		return "Rate limit exceeded, paused and will retry"
	case strings.Contains(msg, "timeout") || strings.Contains(msg, "network"):
		return "Network connection failed, please check your network"
	default:
		return "AI analysis encountered a problem"
	}
}
