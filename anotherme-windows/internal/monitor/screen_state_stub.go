//go:build !windows

package monitor

import (
	"fmt"
	"sync"
)

// ScreenStateMonitor detects whether the screen is locked, the screensaver
// is active, or the user has been idle for an extended period.
// On non-Windows platforms this is a stub.
type ScreenStateMonitor struct {
	locked      bool
	screensaver bool
	idle        bool
	inputMon    *InputMonitor
	onChange    func(locked, screensaver, idle bool)
	mu         sync.RWMutex
	stopCh     chan struct{}
}

// NewScreenStateMonitor creates a new ScreenStateMonitor.
func NewScreenStateMonitor(inputMon *InputMonitor) *ScreenStateMonitor {
	return &ScreenStateMonitor{
		inputMon: inputMon,
	}
}

// Start is not supported on this platform.
func (s *ScreenStateMonitor) Start() error {
	return fmt.Errorf("screen state monitor: not supported on this platform")
}

// Stop is a no-op on non-Windows platforms.
func (s *ScreenStateMonitor) Stop() {}

// IsLocked always returns false on non-Windows platforms.
func (s *ScreenStateMonitor) IsLocked() bool {
	return false
}

// IsScreensaver always returns false on non-Windows platforms.
func (s *ScreenStateMonitor) IsScreensaver() bool {
	return false
}

// IsIdle always returns false on non-Windows platforms.
func (s *ScreenStateMonitor) IsIdle() bool {
	return false
}

// SetOnChange registers a callback (no-op on non-Windows).
func (s *ScreenStateMonitor) SetOnChange(fn func(bool, bool, bool)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.onChange = fn
}
