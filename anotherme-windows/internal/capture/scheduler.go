package capture

import (
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/user/anotherme-windows/internal/monitor"
)

// CaptureMode defines the scheduling strategy for screen capture.
type CaptureMode string

const (
	// ModeInterval captures at a fixed time interval.
	ModeInterval CaptureMode = "interval"
	// ModeEvent captures when the foreground window changes.
	ModeEvent CaptureMode = "event"
	// ModeSmart uses adaptive intervals based on user activity.
	ModeSmart CaptureMode = "smart"
)

const (
	defaultInterval    = 5 * time.Minute
	defaultMinInterval = 10 * time.Second
	defaultDailyLimit  = 200

	smartActiveInterval = 2 * time.Minute
	smartIdleInterval   = 10 * time.Minute
)

// CaptureResult holds the outcome of a single capture cycle, including
// screenshots from all displays along with the active application context.
type CaptureResult struct {
	Screenshots []ScreenshotResult
	AppName     string
	WindowTitle string
	CapturedAt  time.Time
}

// Service orchestrates screen capture scheduling with multiple modes,
// deduplication, and security filtering.
type Service struct {
	capturer       *Capturer
	dedup          *Deduplicator
	windowTracker  *monitor.WindowTracker
	screenState    *monitor.ScreenStateMonitor
	securityFilter *monitor.SecurityFilter

	mode        CaptureMode
	interval    time.Duration
	minInterval time.Duration
	dailyLimit  int
	todayCount  int
	lastDate    time.Time

	onCapture func(result *CaptureResult)
	running   bool
	mu        sync.Mutex
	stopCh    chan struct{}
}

// NewService creates a new capture Service wired to the given dependencies.
func NewService(
	capturer *Capturer,
	dedup *Deduplicator,
	wt *monitor.WindowTracker,
	ss *monitor.ScreenStateMonitor,
	sf *monitor.SecurityFilter,
) *Service {
	return &Service{
		capturer:       capturer,
		dedup:          dedup,
		windowTracker:  wt,
		screenState:    ss,
		securityFilter: sf,
		mode:           ModeInterval,
		interval:       defaultInterval,
		minInterval:    defaultMinInterval,
		dailyLimit:     defaultDailyLimit,
		lastDate:       time.Now().Truncate(24 * time.Hour),
	}
}

// Start begins the capture loop in the configured mode.
func (s *Service) Start() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.running {
		return fmt.Errorf("capture service: already running")
	}

	s.stopCh = make(chan struct{})
	s.running = true

	switch s.mode {
	case ModeEvent:
		s.startEventMode()
	case ModeSmart:
		go s.smartLoop()
	default:
		go s.intervalLoop()
	}

	return nil
}

// Stop halts the capture loop.
func (s *Service) Stop() {
	s.mu.Lock()
	defer s.mu.Unlock()

	if !s.running {
		return
	}
	close(s.stopCh)
	s.running = false

	// Stop the window tracker if it was started (event mode).
	if s.mode == ModeEvent {
		s.windowTracker.Stop()
	}
}

// SetMode changes the capture scheduling mode. Takes effect after
// restarting the service.
func (s *Service) SetMode(mode CaptureMode) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.mode = mode
}

// SetInterval sets the capture interval for interval and smart modes.
func (s *Service) SetInterval(d time.Duration) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if d < s.minInterval {
		d = s.minInterval
	}
	s.interval = d
}

// SetOnCapture registers a callback invoked after each successful capture.
func (s *Service) SetOnCapture(fn func(*CaptureResult)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.onCapture = fn
}

// IsRunning reports whether the capture service is active.
func (s *Service) IsRunning() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.running
}

// TodayCount returns the number of captures performed today.
func (s *Service) TodayCount() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.resetDailyCountIfNeeded()
	return s.todayCount
}

// TriggerOnce performs a single manual capture cycle, bypassing the scheduler
// but still respecting security filters and deduplication.
func (s *Service) TriggerOnce() error {
	return s.triggerCapture()
}

// intervalLoop runs the simple fixed-interval capture loop.
func (s *Service) intervalLoop() {
	ticker := time.NewTicker(s.interval)
	defer ticker.Stop()

	for {
		select {
		case <-s.stopCh:
			return
		case <-ticker.C:
			_ = s.triggerCapture()
		}
	}
}

// startEventMode subscribes to window-change events to trigger captures.
func (s *Service) startEventMode() {
	// Start the window tracker so it begins polling/emitting change events.
	if err := s.windowTracker.Start(); err != nil {
		log.Printf("[Scheduler] Failed to start window tracker: %v", err)
	}

	stopCh := s.stopCh

	var lastCapture time.Time
	s.windowTracker.SetOnChange(func(old, cur *monitor.WindowInfo) {
		select {
		case <-stopCh:
			return
		default:
		}
		if time.Since(lastCapture) < s.minInterval {
			return
		}
		lastCapture = time.Now()
		_ = s.triggerCapture()
	})
}

// smartLoop adapts the capture interval based on user activity level.
func (s *Service) smartLoop() {
	timer := time.NewTimer(s.interval)
	defer timer.Stop()

	for {
		select {
		case <-s.stopCh:
			return
		case <-timer.C:
			_ = s.triggerCapture()

			// Adapt interval based on screen state.
			next := smartActiveInterval
			if s.screenState.IsIdle() {
				next = smartIdleInterval
			}
			timer.Reset(next)
		}
	}
}

// triggerCapture executes the full capture pipeline with all gates.
func (s *Service) triggerCapture() error {
	s.mu.Lock()
	s.resetDailyCountIfNeeded()

	// Gate 0: daily limit.
	if s.todayCount >= s.dailyLimit {
		s.mu.Unlock()
		return fmt.Errorf("daily capture limit (%d) reached", s.dailyLimit)
	}
	callback := s.onCapture
	s.mu.Unlock()

	// Gate 1: screen state — skip if locked or screensaver.
	// Idle state is handled by smart mode's adaptive interval, not skipped.
	if s.screenState.IsLocked() || s.screenState.IsScreensaver() {
		return nil
	}

	// Get current window context.
	var appName, windowTitle, processName string
	if wi := s.windowTracker.Current(); wi != nil {
		appName = wi.AppName
		windowTitle = wi.Title
		processName = wi.ProcessName
	}

	// Gate 2: hard-blocked apps (password managers, crypto wallets, etc.).
	if s.securityFilter.IsHardBlocked(processName) {
		return nil
	}

	// Gate 3: soft-filtered apps/keywords.
	if s.securityFilter.IsSoftFiltered(processName, windowTitle) {
		return nil
	}

	// Capture screenshots from all displays.
	screenshots, err := s.capturer.CaptureAllDisplays()
	if err != nil {
		return fmt.Errorf("capture screenshots: %w", err)
	}

	// Gate 4: deduplication — keep only non-duplicate displays.
	var kept []ScreenshotResult
	for _, ss := range screenshots {
		if !s.dedup.IsDuplicate(ss.DisplayIndex, ss.ImageData) {
			kept = append(kept, ss)
		}
	}
	if len(kept) == 0 {
		return nil // all duplicates
	}

	s.mu.Lock()
	s.todayCount++
	s.mu.Unlock()

	result := &CaptureResult{
		Screenshots: kept,
		AppName:     appName,
		WindowTitle: windowTitle,
		CapturedAt:  time.Now(),
	}

	if callback != nil {
		callback(result)
	}

	return nil
}

// resetDailyCountIfNeeded resets the counter if the day has changed.
// Caller must hold s.mu.
func (s *Service) resetDailyCountIfNeeded() {
	today := time.Now().Truncate(24 * time.Hour)
	if today.After(s.lastDate) {
		s.todayCount = 0
		s.lastDate = today
	}
}
