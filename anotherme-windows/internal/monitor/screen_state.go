//go:build windows

package monitor

import (
	"sync"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	moduser32SS = windows.NewLazySystemDLL("user32.dll")

	procFindWindowW      = moduser32SS.NewProc("FindWindowW")
	procOpenInputDesktop = moduser32SS.NewProc("OpenInputDesktop")
	procCloseDesktop     = moduser32SS.NewProc("CloseDesktop")
)

const (
	screenStatePollInterval = 5 * time.Second
	idleScreenThreshold     = 180 // seconds
)

// ScreenStateMonitor detects whether the screen is locked, the screensaver
// is active, or the user has been idle for an extended period.
type ScreenStateMonitor struct {
	locked      bool
	screensaver bool
	idle        bool
	inputMon    *InputMonitor
	onChange    func(locked, screensaver, idle bool)
	mu         sync.RWMutex
	stopCh     chan struct{}
}

// NewScreenStateMonitor creates a new ScreenStateMonitor backed by the
// given InputMonitor for idle detection.
func NewScreenStateMonitor(inputMon *InputMonitor) *ScreenStateMonitor {
	return &ScreenStateMonitor{
		inputMon: inputMon,
	}
}

// Start begins polling screen state every 5 seconds.
func (s *ScreenStateMonitor) Start() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.stopCh = make(chan struct{})
	go s.pollLoop()
	return nil
}

// Stop halts the screen state polling loop.
func (s *ScreenStateMonitor) Stop() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.stopCh != nil {
		close(s.stopCh)
		s.stopCh = nil
	}
}

// IsLocked reports whether the workstation screen is locked.
func (s *ScreenStateMonitor) IsLocked() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.locked
}

// IsScreensaver reports whether the screensaver is currently running.
func (s *ScreenStateMonitor) IsScreensaver() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.screensaver
}

// IsIdle reports whether the user has been idle for an extended period
// (more than 180 seconds without input).
func (s *ScreenStateMonitor) IsIdle() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.idle
}

// SetOnChange registers a callback fired when any screen state changes.
func (s *ScreenStateMonitor) SetOnChange(fn func(locked, screensaver, idle bool)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.onChange = fn
}

// pollLoop periodically checks screen state.
func (s *ScreenStateMonitor) pollLoop() {
	ticker := time.NewTicker(screenStatePollInterval)
	defer ticker.Stop()

	for {
		select {
		case <-s.stopCh:
			return
		case <-ticker.C:
			s.update()
		}
	}
}

// update reads current screen state and fires onChange if anything changed.
func (s *ScreenStateMonitor) update() {
	locked := isScreenLocked()
	screensaver := isScreensaverRunning()
	idle := s.inputMon.GetIdleSeconds() > idleScreenThreshold

	s.mu.Lock()
	changed := s.locked != locked || s.screensaver != screensaver || s.idle != idle
	s.locked = locked
	s.screensaver = screensaver
	s.idle = idle
	cb := s.onChange
	s.mu.Unlock()

	if changed && cb != nil {
		cb(locked, screensaver, idle)
	}
}

// isScreenLocked checks if the workstation is locked by trying to open
// the input desktop. If the desktop cannot be opened or its name is empty,
// the station is likely locked.
func isScreenLocked() bool {
	// OpenInputDesktop returns 0 when the secure desktop (lock screen) is active.
	hDesk, _, _ := procOpenInputDesktop.Call(0, 0, 0x0001) // DESKTOP_READOBJECTS
	if hDesk == 0 {
		return true
	}
	procCloseDesktop.Call(hDesk)
	return false
}

// isScreensaverRunning checks for the Windows screensaver window class.
func isScreensaverRunning() bool {
	className, _ := windows.UTF16PtrFromString("WindowsScreenSaverClass")
	hwnd, _, _ := procFindWindowW.Call(
		uintptr(unsafe.Pointer(className)),
		0,
	)
	return hwnd != 0
}
