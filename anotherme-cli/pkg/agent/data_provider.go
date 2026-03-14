package agent

import (
	"fmt"
	"strings"
	"time"

	"github.com/user/anotherme-cli/pkg/db"
)

// DataProvider fetches and formats supplemental data from various layers.
type DataProvider struct {
	mgr *db.Manager
}

// NewDataProvider creates a new DataProvider.
func NewDataProvider(mgr *db.Manager) *DataProvider {
	return &DataProvider{mgr: mgr}
}

// FetchData fetches supplemental data based on the route's LayersNeeded and flags.
func (dp *DataProvider) FetchData(route *RouterResponse) (*LayerData, error) {
	data := &LayerData{}

	needed := make(map[int]bool)
	for _, l := range route.LayersNeeded {
		needed[l] = true
	}

	// Layer 1: rhythm traits
	if needed[1] {
		if text := dp.formatLayerTraits(1); text != "" {
			data.Layer1Text = &text
		}
	}

	// Layer 2: knowledge traits
	if needed[2] {
		if text := dp.formatLayerTraits(2); text != "" {
			data.Layer2Text = &text
		}
	}

	// Activity logs
	if route.NeedActivityLogs {
		if text := dp.formatActivityLogs(route.TimeRange); text != "" {
			data.ActivityLogsText = &text
		}
	}

	// Knowledge graph (placeholder — not yet implemented in db layer)
	if route.NeedKnowledgeGraph {
		// Knowledge graph data would be fetched here when available
	}

	return data, nil
}

// formatLayerTraits formats traits from a given layer as "- dimension: value (confidence XX%)" lines.
func (dp *DataProvider) formatLayerTraits(layer int) string {
	layerDB := dp.mgr.LayerDB(layer)
	if layerDB == nil {
		return ""
	}

	traits, err := db.FetchTraits(layerDB, layer)
	if err != nil || len(traits) == 0 {
		return ""
	}

	var sb strings.Builder
	for _, t := range traits {
		pct := int(t.Confidence * 100)
		sb.WriteString(fmt.Sprintf("- %s: %s (confidence %d%%)\n", t.Dimension, t.Value, pct))
	}

	return sb.String()
}

// formatActivityLogs fetches recent activities and formats them.
func (dp *DataProvider) formatActivityLogs(timeRange string) string {
	actDB := dp.mgr.ActivityDB()
	if actDB == nil {
		return ""
	}

	var since time.Time
	now := time.Now()

	switch timeRange {
	case "today":
		since = time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	case "last_7_days":
		since = now.AddDate(0, 0, -7)
	case "last_30_days":
		since = now.AddDate(0, 0, -30)
	default:
		since = now.AddDate(0, 0, -7) // default to last 7 days
	}

	activities, err := db.FetchActivities(actDB, since, 50)
	if err != nil || len(activities) == 0 {
		return ""
	}

	var sb strings.Builder
	for _, a := range activities {
		summary := ""
		if a.ContentSummary != nil {
			summary = *a.ContentSummary
		}

		topicsStr := ""
		if len(a.Topics) > 0 {
			topicsStr = " [topics: " + strings.Join(a.Topics, ", ") + "]"
		}

		sb.WriteString(fmt.Sprintf("- %s | %s | %s%s\n",
			a.Timestamp.Format("01-02 15:04"),
			a.AppName,
			summary,
			topicsStr,
		))
	}

	return sb.String()
}
