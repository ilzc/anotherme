//go:build !windows

package monitor

import (
	"fmt"
	"sync"
)

// WindowInfo describes the currently focused window.
type WindowInfo struct {
	ProcessName string
	AppName     string
	Title       string
	PID         uint32
	HWND        uintptr
}

// WindowTracker monitors the foreground window and fires a callback
// when the active window or its title changes.
// On non-Windows platforms this is a stub.
type WindowTracker struct {
	current  *WindowInfo
	onChange func(old, cur *WindowInfo)
	mu       sync.RWMutex
	stopCh   chan struct{}
}

// NewWindowTracker creates a new WindowTracker.
func NewWindowTracker() *WindowTracker {
	return &WindowTracker{}
}

// Start is not supported on this platform.
func (wt *WindowTracker) Start() error {
	return fmt.Errorf("window tracker: not supported on this platform")
}

// Stop is a no-op on non-Windows platforms.
func (wt *WindowTracker) Stop() {}

// Current returns nil on non-Windows platforms.
func (wt *WindowTracker) Current() *WindowInfo {
	return nil
}

// SetOnChange registers a callback (no-op on non-Windows).
func (wt *WindowTracker) SetOnChange(fn func(old, cur *WindowInfo)) {
	wt.mu.Lock()
	defer wt.mu.Unlock()
	wt.onChange = fn
}
