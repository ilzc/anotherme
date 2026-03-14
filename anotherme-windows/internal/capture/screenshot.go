//go:build windows

package capture

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"image"
	"image/jpeg"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	modgdi32   = windows.NewLazySystemDLL("gdi32.dll")
	moduser32  = windows.NewLazySystemDLL("user32.dll")
	modshcore  = windows.NewLazySystemDLL("shcore.dll")

	procGetDC                   = moduser32.NewProc("GetDC")
	procReleaseDC               = moduser32.NewProc("ReleaseDC")
	procCreateCompatibleDC      = modgdi32.NewProc("CreateCompatibleDC")
	procCreateCompatibleBitmap  = modgdi32.NewProc("CreateCompatibleBitmap")
	procSelectObject            = modgdi32.NewProc("SelectObject")
	procBitBlt                  = modgdi32.NewProc("BitBlt")
	procDeleteObject            = modgdi32.NewProc("DeleteObject")
	procDeleteDC                = modgdi32.NewProc("DeleteDC")
	procGetDIBits               = modgdi32.NewProc("GetDIBits")
	procGetSystemMetrics        = moduser32.NewProc("GetSystemMetrics")
	procEnumDisplayMonitors     = moduser32.NewProc("EnumDisplayMonitors")
	procGetMonitorInfoW         = moduser32.NewProc("GetMonitorInfoW")
)

const (
	srccopy       = 0x00CC0020
	biRGB         = 0
	dibRGBColors  = 0
	smCxScreen    = 0
	smCyScreen    = 1
	maxCaptureW   = 1920
	jpegQuality   = 85
)

// bitmapInfoHeader is the BITMAPINFOHEADER structure.
type bitmapInfoHeader struct {
	BiSize          uint32
	BiWidth         int32
	BiHeight        int32
	BiPlanes        uint16
	BiBitCount      uint16
	BiCompression   uint32
	BiSizeImage     uint32
	BiXPelsPerMeter int32
	BiYPelsPerMeter int32
	BiClrUsed       uint32
	BiClrImportant  uint32
}

// monitorInfo is the MONITORINFO structure.
type monitorInfo struct {
	CbSize    uint32
	RcMonitor rect
	RcWork    rect
	DwFlags   uint32
}

// rect is the RECT structure.
type rect struct {
	Left   int32
	Top    int32
	Right  int32
	Bottom int32
}

// monitorEnumData collects monitor rectangles during enumeration.
type monitorEnumData struct {
	monitors []rect
}

// ScreenshotResult holds a captured screenshot.
type ScreenshotResult struct {
	DisplayIndex int
	ImageData    []byte  // JPEG bytes
	Base64       string  // Base64-encoded JPEG
	Width        int
	Height       int
	CapturedAt   time.Time
}

// Capturer handles Windows screen capture via GDI BitBlt.
type Capturer struct{}

// NewCapturer creates a new Capturer instance.
func NewCapturer() *Capturer {
	return &Capturer{}
}

// CaptureAllDisplays captures screenshots from every connected display.
func (c *Capturer) CaptureAllDisplays() ([]ScreenshotResult, error) {
	monitors, err := enumMonitors()
	if err != nil {
		return nil, fmt.Errorf("enumerate monitors: %w", err)
	}
	if len(monitors) == 0 {
		// Fallback to primary display via GetSystemMetrics.
		result, err := c.capturePrimary()
		if err != nil {
			return nil, err
		}
		return []ScreenshotResult{*result}, nil
	}

	results := make([]ScreenshotResult, 0, len(monitors))
	for i, mon := range monitors {
		w := int(mon.Right - mon.Left)
		h := int(mon.Bottom - mon.Top)
		result, err := c.captureRect(int(mon.Left), int(mon.Top), w, h)
		if err != nil {
			return nil, fmt.Errorf("capture display %d: %w", i, err)
		}
		result.DisplayIndex = i
		results = append(results, *result)
	}
	return results, nil
}

// CaptureDisplay captures a screenshot from the display at the given index.
func (c *Capturer) CaptureDisplay(index int) (*ScreenshotResult, error) {
	monitors, err := enumMonitors()
	if err != nil {
		return nil, fmt.Errorf("enumerate monitors: %w", err)
	}
	if index < 0 || index >= len(monitors) {
		return nil, fmt.Errorf("display index %d out of range (have %d displays)", index, len(monitors))
	}
	mon := monitors[index]
	w := int(mon.Right - mon.Left)
	h := int(mon.Bottom - mon.Top)
	result, err := c.captureRect(int(mon.Left), int(mon.Top), w, h)
	if err != nil {
		return nil, fmt.Errorf("capture display %d: %w", index, err)
	}
	result.DisplayIndex = index
	return result, nil
}

// capturePrimary captures the primary display using GetSystemMetrics.
func (c *Capturer) capturePrimary() (*ScreenshotResult, error) {
	w, _, _ := procGetSystemMetrics.Call(uintptr(smCxScreen))
	h, _, _ := procGetSystemMetrics.Call(uintptr(smCyScreen))
	if w == 0 || h == 0 {
		return nil, fmt.Errorf("GetSystemMetrics returned zero dimensions")
	}
	return c.captureRect(0, 0, int(w), int(h))
}

// captureRect captures a rectangular region of the virtual screen.
func (c *Capturer) captureRect(x, y, width, height int) (*ScreenshotResult, error) {
	// Get screen DC.
	hdcScreen, _, _ := procGetDC.Call(0)
	if hdcScreen == 0 {
		return nil, fmt.Errorf("GetDC(0) failed")
	}
	defer procReleaseDC.Call(0, hdcScreen)

	// Create compatible DC and bitmap.
	hdcMem, _, _ := procCreateCompatibleDC.Call(hdcScreen)
	if hdcMem == 0 {
		return nil, fmt.Errorf("CreateCompatibleDC failed")
	}
	defer procDeleteDC.Call(hdcMem)

	hBitmap, _, _ := procCreateCompatibleBitmap.Call(hdcScreen, uintptr(width), uintptr(height))
	if hBitmap == 0 {
		return nil, fmt.Errorf("CreateCompatibleBitmap failed")
	}
	defer procDeleteObject.Call(hBitmap)

	// Select bitmap into memory DC.
	old, _, _ := procSelectObject.Call(hdcMem, hBitmap)
	if old == 0 {
		return nil, fmt.Errorf("SelectObject failed")
	}
	defer procSelectObject.Call(hdcMem, old)

	// BitBlt from screen to memory DC.
	ret, _, _ := procBitBlt.Call(
		hdcMem, 0, 0, uintptr(width), uintptr(height),
		hdcScreen, uintptr(x), uintptr(y), srccopy,
	)
	if ret == 0 {
		return nil, fmt.Errorf("BitBlt failed")
	}

	// Get raw pixel data via GetDIBits.
	bmi := bitmapInfoHeader{
		BiSize:        uint32(unsafe.Sizeof(bitmapInfoHeader{})),
		BiWidth:       int32(width),
		BiHeight:      -int32(height), // top-down
		BiPlanes:      1,
		BiBitCount:    32,
		BiCompression: biRGB,
	}

	pixelDataSize := width * height * 4
	pixelData := make([]byte, pixelDataSize)
	ret, _, _ = procGetDIBits.Call(
		hdcMem, hBitmap, 0, uintptr(height),
		uintptr(unsafe.Pointer(&pixelData[0])),
		uintptr(unsafe.Pointer(&bmi)),
		dibRGBColors,
	)
	if ret == 0 {
		return nil, fmt.Errorf("GetDIBits failed")
	}

	// Convert BGRA pixel data to image.NRGBA.
	img := image.NewNRGBA(image.Rect(0, 0, width, height))
	for i := 0; i < width*height; i++ {
		srcOff := i * 4
		dstOff := i * 4
		img.Pix[dstOff+0] = pixelData[srcOff+2] // R
		img.Pix[dstOff+1] = pixelData[srcOff+1] // G
		img.Pix[dstOff+2] = pixelData[srcOff+0] // B
		img.Pix[dstOff+3] = 255                  // A
	}

	// Scale down if wider than maxCaptureW.
	finalImg := scaleIfNeeded(img, maxCaptureW)

	// Encode to JPEG.
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, finalImg, &jpeg.Options{Quality: jpegQuality}); err != nil {
		return nil, fmt.Errorf("jpeg encode: %w", err)
	}

	jpegBytes := buf.Bytes()
	b64 := base64.StdEncoding.EncodeToString(jpegBytes)
	bounds := finalImg.Bounds()

	return &ScreenshotResult{
		ImageData:  jpegBytes,
		Base64:     b64,
		Width:      bounds.Dx(),
		Height:     bounds.Dy(),
		CapturedAt: time.Now(),
	}, nil
}

// scaleIfNeeded scales the image down proportionally if its width exceeds maxW.
func scaleIfNeeded(src *image.NRGBA, maxW int) image.Image {
	bounds := src.Bounds()
	srcW := bounds.Dx()
	srcH := bounds.Dy()
	if srcW <= maxW {
		return src
	}
	dstW := maxW
	dstH := srcH * maxW / srcW
	dst := image.NewNRGBA(image.Rect(0, 0, dstW, dstH))

	for dy := 0; dy < dstH; dy++ {
		sy := dy * srcH / dstH
		for dx := 0; dx < dstW; dx++ {
			sx := dx * srcW / dstW
			srcOff := (sy*srcW + sx) * 4
			dstOff := (dy*dstW + dx) * 4
			copy(dst.Pix[dstOff:dstOff+4], src.Pix[srcOff:srcOff+4])
		}
	}
	return dst
}

// enumMonitors returns the bounding rectangles for all connected monitors.
func enumMonitors() ([]rect, error) {
	var data monitorEnumData
	cb := windows.NewCallback(func(hMonitor uintptr, hdcMonitor uintptr, lprcMonitor uintptr, dwData uintptr) uintptr {
		var mi monitorInfo
		mi.CbSize = uint32(unsafe.Sizeof(mi))
		ret, _, _ := procGetMonitorInfoW.Call(hMonitor, uintptr(unsafe.Pointer(&mi)))
		if ret != 0 {
			data.monitors = append(data.monitors, mi.RcMonitor)
		}
		return 1 // continue enumeration
	})

	ret, _, err := procEnumDisplayMonitors.Call(0, 0, cb, 0)
	if ret == 0 {
		return nil, fmt.Errorf("EnumDisplayMonitors failed: %w", err)
	}
	return data.monitors, nil
}
