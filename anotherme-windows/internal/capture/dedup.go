package capture

import (
	"bytes"
	"image"
	"image/jpeg"
	"sync"
)

const (
	thumbnailSize    = 32
	defaultThreshold = 0.05
	defaultTolerance = 10
)

// Deduplicator tracks per-display thumbnails and determines whether a new
// frame is a duplicate of the previous one using pixel-level comparison
// on downscaled grayscale thumbnails.
type Deduplicator struct {
	threshold  float64        // fraction of changed pixels to consider different (default 0.05)
	tolerance  int            // per-pixel intensity difference to count as changed (default 10)
	lastFrames map[int][]byte // displayIndex -> 32x32 grayscale bytes
	mu         sync.Mutex
}

// NewDeduplicator creates a Deduplicator with default settings
// (5% threshold, 10 per-pixel tolerance).
func NewDeduplicator() *Deduplicator {
	return &Deduplicator{
		threshold:  defaultThreshold,
		tolerance:  defaultTolerance,
		lastFrames: make(map[int][]byte),
	}
}

// IsDuplicate returns true if the given JPEG image data is considered a
// duplicate of the previously seen frame for the specified display index.
// The first frame for a display is never considered a duplicate.
func (d *Deduplicator) IsDuplicate(displayIndex int, imageData []byte) bool {
	thumb, err := toGrayscaleThumbnail(imageData)
	if err != nil {
		// If we cannot decode, treat as non-duplicate so it gets captured.
		return false
	}

	d.mu.Lock()
	defer d.mu.Unlock()

	prev, exists := d.lastFrames[displayIndex]
	d.lastFrames[displayIndex] = thumb

	if !exists {
		return false
	}

	changed := 0
	total := thumbnailSize * thumbnailSize
	for i := 0; i < total; i++ {
		diff := int(thumb[i]) - int(prev[i])
		if diff < 0 {
			diff = -diff
		}
		if diff > d.tolerance {
			changed++
		}
	}

	changeRatio := float64(changed) / float64(total)
	return changeRatio < d.threshold
}

// Reset clears all stored frames, so subsequent calls to IsDuplicate
// will treat the next frame as new.
func (d *Deduplicator) Reset() {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.lastFrames = make(map[int][]byte)
}

// toGrayscaleThumbnail decodes JPEG image data, resizes to 32x32 using
// nearest-neighbor sampling, and converts to grayscale (1024 bytes).
func toGrayscaleThumbnail(jpegData []byte) ([]byte, error) {
	img, err := jpeg.Decode(bytes.NewReader(jpegData))
	if err != nil {
		return nil, err
	}

	bounds := img.Bounds()
	srcW := bounds.Dx()
	srcH := bounds.Dy()

	thumb := make([]byte, thumbnailSize*thumbnailSize)
	for ty := 0; ty < thumbnailSize; ty++ {
		sy := bounds.Min.Y + ty*srcH/thumbnailSize
		for tx := 0; tx < thumbnailSize; tx++ {
			sx := bounds.Min.X + tx*srcW/thumbnailSize
			r, g, b, _ := img.At(sx, sy).RGBA()
			// Convert to 8-bit grayscale using luminance formula.
			gray := uint8((19595*r + 38470*g + 7471*b + 1<<15) >> 24)
			thumb[ty*thumbnailSize+tx] = gray
		}
	}
	return thumb, nil
}

// SetThreshold sets the change-ratio threshold. Frames with fewer changed
// pixels than this fraction are considered duplicates.
func (d *Deduplicator) SetThreshold(t float64) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.threshold = t
}

// SetTolerance sets the per-pixel intensity tolerance. Pixel differences
// at or below this value are ignored.
func (d *Deduplicator) SetTolerance(t int) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.tolerance = t
}

// Ensure jpeg is registered as a decoder (it is by import side-effect).
var _ image.Image
