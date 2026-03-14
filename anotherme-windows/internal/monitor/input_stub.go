//go:build !windows

package monitor

import (
	"fmt"
	"sync"
)

// ActivityLevel represents the user's input activity state.
type ActivityLevel int

const (
	// ActivityActive means the user has had recent input.
	ActivityActive ActivityLevel = iota
	// ActivityIdle means no input for more than 60 seconds.
	ActivityIdle
	// ActivityDeepIdle means no input for more than 180 seconds.
	ActivityDeepIdle
)

// InputMonitor tracks user input activity by polling GetLastInputInfo.
// On non-Windows platforms this is a stub.
type InputMonitor struct {
	level  ActivityLevel
	mu     sync.RWMutex
	stopCh chan struct{}
}

// NewInputMonitor creates a new InputMonitor.
func NewInputMonitor() *InputMonitor {
	return &InputMonitor{
		level: ActivityActive,
	}
}

// Start is not supported on this platform.
func (im *InputMonitor) Start() error {
	return fmt.Errorf("input monitor: not supported on this platform")
}

// Stop is a no-op on non-Windows platforms.
func (im *InputMonitor) Stop() {}

// GetIdleSeconds always returns 0 on non-Windows platforms.
func (im *InputMonitor) GetIdleSeconds() uint32 {
	return 0
}

// GetActivityLevel always returns ActivityActive on non-Windows platforms.
func (im *InputMonitor) GetActivityLevel() ActivityLevel {
	return ActivityActive
}
