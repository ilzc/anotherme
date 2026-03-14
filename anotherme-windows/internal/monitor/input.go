//go:build windows

package monitor

import (
	"sync"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	moduser32Input = windows.NewLazySystemDLL("user32.dll")
	modkernel32In  = windows.NewLazySystemDLL("kernel32.dll")

	procGetLastInputInfo = moduser32Input.NewProc("GetLastInputInfo")
	procGetTickCount     = modkernel32In.NewProc("GetTickCount")
)

const (
	inputPollInterval   = 5 * time.Second
	idleThresholdSec    = 60
	deepIdleThresholdSec = 180
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

// lastInputInfo matches the Windows LASTINPUTINFO structure.
type lastInputInfo struct {
	CbSize uint32
	DwTime uint32
}

// InputMonitor tracks user input activity by polling GetLastInputInfo.
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

// Start begins polling user input activity every 5 seconds.
func (im *InputMonitor) Start() error {
	im.mu.Lock()
	defer im.mu.Unlock()
	im.stopCh = make(chan struct{})
	go im.pollLoop()
	return nil
}

// Stop halts the input monitoring loop.
func (im *InputMonitor) Stop() {
	im.mu.Lock()
	defer im.mu.Unlock()
	if im.stopCh != nil {
		close(im.stopCh)
		im.stopCh = nil
	}
}

// GetIdleSeconds returns the number of seconds since the last user input.
func (im *InputMonitor) GetIdleSeconds() uint32 {
	var lii lastInputInfo
	lii.CbSize = uint32(unsafe.Sizeof(lii))

	ret, _, _ := procGetLastInputInfo.Call(uintptr(unsafe.Pointer(&lii)))
	if ret == 0 {
		return 0
	}

	tickCount, _, _ := procGetTickCount.Call()
	elapsed := uint32(tickCount) - lii.DwTime
	return elapsed / 1000
}

// GetActivityLevel returns the current activity level based on idle time.
func (im *InputMonitor) GetActivityLevel() ActivityLevel {
	im.mu.RLock()
	defer im.mu.RUnlock()
	return im.level
}

// pollLoop periodically updates the activity level.
func (im *InputMonitor) pollLoop() {
	ticker := time.NewTicker(inputPollInterval)
	defer ticker.Stop()

	for {
		select {
		case <-im.stopCh:
			return
		case <-ticker.C:
			idle := im.GetIdleSeconds()
			var level ActivityLevel
			switch {
			case idle >= deepIdleThresholdSec:
				level = ActivityDeepIdle
			case idle >= idleThresholdSec:
				level = ActivityIdle
			default:
				level = ActivityActive
			}
			im.mu.Lock()
			im.level = level
			im.mu.Unlock()
		}
	}
}
