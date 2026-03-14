//go:build windows

package monitor

import (
	"path/filepath"
	"strings"
	"sync"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	moduser32Win = windows.NewLazySystemDLL("user32.dll")
	modkernel32  = windows.NewLazySystemDLL("kernel32.dll")

	procGetForegroundWindow       = moduser32Win.NewProc("GetForegroundWindow")
	procGetWindowTextW            = moduser32Win.NewProc("GetWindowTextW")
	procGetWindowTextLengthW      = moduser32Win.NewProc("GetWindowTextLengthW")
	procGetWindowThreadProcessId  = moduser32Win.NewProc("GetWindowThreadProcessId")
)

const windowPollInterval = 500 * time.Millisecond

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

// Start begins polling the foreground window every 500ms.
func (wt *WindowTracker) Start() error {
	wt.mu.Lock()
	defer wt.mu.Unlock()

	wt.stopCh = make(chan struct{})
	go wt.pollLoop()
	return nil
}

// Stop halts the polling loop.
func (wt *WindowTracker) Stop() {
	wt.mu.Lock()
	defer wt.mu.Unlock()

	if wt.stopCh != nil {
		close(wt.stopCh)
		wt.stopCh = nil
	}
}

// Current returns the currently tracked WindowInfo, or nil if unknown.
func (wt *WindowTracker) Current() *WindowInfo {
	wt.mu.RLock()
	defer wt.mu.RUnlock()
	return wt.current
}

// SetOnChange registers a callback fired when the foreground window changes.
func (wt *WindowTracker) SetOnChange(fn func(old, cur *WindowInfo)) {
	wt.mu.Lock()
	defer wt.mu.Unlock()
	wt.onChange = fn
}

// pollLoop polls GetForegroundWindow and detects changes.
func (wt *WindowTracker) pollLoop() {
	ticker := time.NewTicker(windowPollInterval)
	defer ticker.Stop()

	for {
		select {
		case <-wt.stopCh:
			return
		case <-ticker.C:
			wt.poll()
		}
	}
}

// poll reads the current foreground window and fires onChange if different.
func (wt *WindowTracker) poll() {
	hwnd, _, _ := procGetForegroundWindow.Call()
	if hwnd == 0 {
		return
	}

	title := getWindowText(hwnd)

	var pid uint32
	procGetWindowThreadProcessId.Call(hwnd, uintptr(unsafe.Pointer(&pid)))

	processName := getProcessName(pid)
	appName := extractAppName(processName)

	info := &WindowInfo{
		ProcessName: processName,
		AppName:     appName,
		Title:       title,
		PID:         pid,
		HWND:        hwnd,
	}

	wt.mu.Lock()
	old := wt.current
	changed := old == nil || old.HWND != info.HWND || old.Title != info.Title
	if changed {
		wt.current = info
	}
	cb := wt.onChange
	wt.mu.Unlock()

	if changed && cb != nil {
		cb(old, info)
	}
}

// getWindowText retrieves the title text of the given window handle.
func getWindowText(hwnd uintptr) string {
	length, _, _ := procGetWindowTextLengthW.Call(hwnd)
	if length == 0 {
		return ""
	}
	buf := make([]uint16, length+1)
	procGetWindowTextW.Call(hwnd, uintptr(unsafe.Pointer(&buf[0])), uintptr(length+1))
	return windows.UTF16ToString(buf)
}

// getProcessName returns the full executable path for the given PID.
func getProcessName(pid uint32) string {
	handle, err := windows.OpenProcess(
		windows.PROCESS_QUERY_LIMITED_INFORMATION,
		false,
		pid,
	)
	if err != nil {
		return ""
	}
	defer windows.CloseHandle(handle)

	var buf [windows.MAX_PATH]uint16
	size := uint32(len(buf))
	err = windows.QueryFullProcessImageName(handle, 0, &buf[0], &size)
	if err != nil {
		return ""
	}
	return windows.UTF16ToString(buf[:size])
}

// extractAppName returns the executable file name without extension
// from a full process path.
func extractAppName(processPath string) string {
	if processPath == "" {
		return ""
	}
	base := filepath.Base(processPath)
	ext := filepath.Ext(base)
	return strings.TrimSuffix(base, ext)
}
