//go:build !windows

package capture

import (
	"fmt"
	"time"
)

// ScreenshotResult holds a captured screenshot.
type ScreenshotResult struct {
	DisplayIndex int
	ImageData    []byte // JPEG bytes
	Base64       string // Base64-encoded JPEG
	Width        int
	Height       int
	CapturedAt   time.Time
}

// Capturer handles Windows screen capture via GDI BitBlt.
// On non-Windows platforms this is a stub that returns errors.
type Capturer struct{}

// NewCapturer creates a new Capturer instance.
func NewCapturer() *Capturer {
	return &Capturer{}
}

// CaptureAllDisplays is not supported on this platform.
func (c *Capturer) CaptureAllDisplays() ([]ScreenshotResult, error) {
	return nil, fmt.Errorf("screen capture: %w", errNotSupported)
}

// CaptureDisplay is not supported on this platform.
func (c *Capturer) CaptureDisplay(index int) (*ScreenshotResult, error) {
	return nil, fmt.Errorf("screen capture: %w", errNotSupported)
}

var errNotSupported = fmt.Errorf("not supported on this platform")
