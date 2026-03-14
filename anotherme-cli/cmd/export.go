package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/spf13/cobra"
	"github.com/user/anotherme-cli/pkg/db"
)

var exportFormat string

// exportLayerNames maps layer index (1-5) to display names.
var exportLayerNames = []string{"Rhythm", "Knowledge", "Cognitive", "Expression", "Values"}

// layerKeysEN maps layer index (1-5) to JSON keys.
var layerKeysEN = []string{"1_rhythm", "2_knowledge", "3_cognitive", "4_expression", "5_values"}

var exportCmd = &cobra.Command{
	Use:   "export",
	Short: "Export personality data",
	Long:  "Export AnotherMe personality data in various formats.",
	RunE:  runExport,
}

func init() {
	exportCmd.Flags().StringVar(&exportFormat, "format", "card", "output format: minimal, card, json, archive")
	rootCmd.AddCommand(exportCmd)
}

// collected data passed between helpers
type exportData struct {
	layers   [5][]db.Trait
	memories []db.Memory
	insights []db.Insight
}

func runExport(cmd *cobra.Command, args []string) error {
	mgr, err := db.NewManager(dbPath)
	if err != nil {
		return fmt.Errorf("failed to open databases: %w", err)
	}
	defer mgr.Close()

	var data exportData

	// Fetch traits from all 5 layers
	for i := 1; i <= 5; i++ {
		layerDB := mgr.LayerDB(i)
		if layerDB == nil {
			if verbose {
				fmt.Fprintf(os.Stderr, "warning: layer %d database not available\n", i)
			}
			data.layers[i-1] = []db.Trait{}
			continue
		}
		traits, err := db.FetchTraits(layerDB, i)
		if err != nil {
			if verbose {
				fmt.Fprintf(os.Stderr, "warning: could not fetch traits for layer %d: %v\n", i, err)
			}
			data.layers[i-1] = []db.Trait{}
			continue
		}
		if traits == nil {
			traits = []db.Trait{}
		}
		data.layers[i-1] = traits
	}

	// Fetch memories
	memDB := mgr.MemoryDB()
	if memDB != nil {
		memories, err := db.FetchRecentMemories(memDB, 50)
		if err != nil {
			if verbose {
				fmt.Fprintf(os.Stderr, "warning: could not fetch memories: %v\n", err)
			}
		} else {
			data.memories = memories
		}
	}
	if data.memories == nil {
		data.memories = []db.Memory{}
	}

	// Fetch insights
	insightDB := mgr.InsightDB()
	if insightDB != nil {
		insights, err := db.FetchInsights(insightDB, 20)
		if err != nil {
			if verbose {
				fmt.Fprintf(os.Stderr, "warning: could not fetch insights: %v\n", err)
			}
		} else {
			data.insights = insights
		}
	}
	if data.insights == nil {
		data.insights = []db.Insight{}
	}

	switch exportFormat {
	case "minimal":
		return exportMinimal(data)
	case "card":
		return exportCard(data)
	case "json":
		return exportJSON(data)
	case "archive":
		return exportArchive(mgr, data)
	default:
		return fmt.Errorf("unknown format '%s': must be one of minimal, card, json, archive", exportFormat)
	}
}

// ── minimal ─────────────────────────────────────────────────────────────────

func exportMinimal(data exportData) error {
	// Only show layers 3, 4, 5 in minimal format
	for _, idx := range []int{2, 3, 4} { // 0-based indices for L3, L4, L5
		fmt.Printf("%s: ", exportLayerNames[idx])
		traits := data.layers[idx]
		for j, t := range traits {
			if j > 0 {
				fmt.Print(", ")
			}
			fmt.Printf("%s: %s", t.Dimension, t.Value)
		}
		if len(traits) == 0 {
			fmt.Print("(no data)")
		}
		fmt.Println()
	}
	return nil
}

// ── card ────────────────────────────────────────────────────────────────────

func exportCard(data exportData) error {
	fmt.Println("╭──────────────────────────────╮")
	fmt.Println("│    AnotherMe Persona Card     │")
	fmt.Println("╰──────────────────────────────╯")
	fmt.Println()

	for i := 0; i < 5; i++ {
		fmt.Printf("▸ %s (Layer %d)\n", exportLayerNames[i], i+1)
		traits := data.layers[i]
		if len(traits) == 0 {
			fmt.Println("  (no data)")
		} else {
			for _, t := range traits {
				fmt.Printf("  - %s: %s (confidence %.0f%%)\n", t.Dimension, t.Value, t.Confidence*100)
			}
		}
		fmt.Println()
	}

	// Memories
	fmt.Printf("▸ Recent Memories (%d total)\n", len(data.memories))
	if len(data.memories) == 0 {
		fmt.Println("  (no data)")
	} else {
		for _, m := range data.memories {
			fmt.Printf("  - (%s) %s\n", m.CreatedAt.Format("2006-01-02"), m.Content)
		}
	}
	fmt.Println()

	// Insights
	fmt.Printf("▸ Insights (%d total)\n", len(data.insights))
	if len(data.insights) == 0 {
		fmt.Println("  (no data)")
	} else {
		for _, ins := range data.insights {
			fmt.Printf("  - [%s] %s\n", ins.Type, ins.Title)
		}
	}
	fmt.Println()

	fmt.Printf("Exported at: %s\n", time.Now().Format("2006-01-02 15:04"))

	return nil
}

// ── json ────────────────────────────────────────────────────────────────────

type traitJSON struct {
	Dimension  string  `json:"dimension"`
	Value      string  `json:"value"`
	Confidence float64 `json:"confidence"`
}

type memoryJSON struct {
	Content    string  `json:"content"`
	Category   string  `json:"category"`
	Importance float64 `json:"importance"`
	CreatedAt  string  `json:"created_at"`
}

type insightJSON struct {
	Type      string `json:"type"`
	Title     string `json:"title"`
	Content   string `json:"content"`
	CreatedAt string `json:"created_at"`
}

type jsonExport struct {
	ExportTime string                       `json:"export_time"`
	Layers     map[string][]traitJSON       `json:"layers"`
	Memories   []memoryJSON                 `json:"memories"`
	Insights   []insightJSON                `json:"insights"`
	Activities []activityJSON               `json:"activities,omitempty"`
	Snapshots  []snapshotJSON               `json:"snapshots,omitempty"`
}

type activityJSON struct {
	Timestamp      string   `json:"timestamp"`
	AppName        string   `json:"app_name"`
	WindowTitle    string   `json:"window_title"`
	ContentSummary *string  `json:"content_summary"`
	Topics         []string `json:"topics"`
}

type snapshotJSON struct {
	SnapshotDate string  `json:"snapshot_date"`
	SummaryText  *string `json:"summary_text"`
	Trigger      string  `json:"trigger"`
}

func buildLayersJSON(data exportData) map[string][]traitJSON {
	layers := make(map[string][]traitJSON)
	for i := 0; i < 5; i++ {
		var traits []traitJSON
		for _, t := range data.layers[i] {
			traits = append(traits, traitJSON{
				Dimension:  t.Dimension,
				Value:      t.Value,
				Confidence: t.Confidence,
			})
		}
		if traits == nil {
			traits = []traitJSON{}
		}
		layers[layerKeysEN[i]] = traits
	}
	return layers
}

func buildMemoriesJSON(data exportData) []memoryJSON {
	var memories []memoryJSON
	for _, m := range data.memories {
		memories = append(memories, memoryJSON{
			Content:    m.Content,
			Category:   m.Category,
			Importance: m.Importance,
			CreatedAt:  m.CreatedAt.Format(time.RFC3339),
		})
	}
	if memories == nil {
		memories = []memoryJSON{}
	}
	return memories
}

func buildInsightsJSON(data exportData) []insightJSON {
	var insights []insightJSON
	for _, ins := range data.insights {
		insights = append(insights, insightJSON{
			Type:      ins.Type,
			Title:     ins.Title,
			Content:   ins.Content,
			CreatedAt: ins.CreatedAt.Format(time.RFC3339),
		})
	}
	if insights == nil {
		insights = []insightJSON{}
	}
	return insights
}

func exportJSON(data exportData) error {
	out := jsonExport{
		ExportTime: time.Now().UTC().Format(time.RFC3339),
		Layers:     buildLayersJSON(data),
		Memories:   buildMemoriesJSON(data),
		Insights:   buildInsightsJSON(data),
	}

	result, err := json.MarshalIndent(out, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal JSON: %w", err)
	}
	fmt.Println(string(result))
	return nil
}

// ── archive ─────────────────────────────────────────────────────────────────

func exportArchive(mgr *db.Manager, data exportData) error {
	out := jsonExport{
		ExportTime: time.Now().UTC().Format(time.RFC3339),
		Layers:     buildLayersJSON(data),
		Memories:   buildMemoriesJSON(data),
		Insights:   buildInsightsJSON(data),
	}

	// Fetch activities (last 100)
	actDB := mgr.ActivityDB()
	if actDB != nil {
		since := time.Now().AddDate(-1, 0, 0) // last year as a reasonable window
		activities, err := db.FetchActivities(actDB, since, 100)
		if err != nil {
			if verbose {
				fmt.Fprintf(os.Stderr, "warning: could not fetch activities: %v\n", err)
			}
		} else {
			var acts []activityJSON
			for _, a := range activities {
				var summary *string
				if a.ContentSummary != nil {
					s := *a.ContentSummary
					summary = &s
				}
				topics := a.Topics
				if topics == nil {
					topics = []string{}
				}
				acts = append(acts, activityJSON{
					Timestamp:      a.Timestamp.Format(time.RFC3339),
					AppName:        a.AppName,
					WindowTitle:    a.WindowTitle,
					ContentSummary: summary,
					Topics:         topics,
				})
			}
			if acts == nil {
				acts = []activityJSON{}
			}
			out.Activities = acts
		}
	}

	// Fetch snapshots
	snapshotDB := mgr.SnapshotDB()
	if snapshotDB != nil {
		snapshots, err := db.FetchSnapshots(snapshotDB, 20)
		if err != nil {
			if verbose {
				fmt.Fprintf(os.Stderr, "warning: could not fetch snapshots: %v\n", err)
			}
		} else {
			var snaps []snapshotJSON
			for _, s := range snapshots {
				snaps = append(snaps, snapshotJSON{
					SnapshotDate: s.SnapshotDate.Format(time.RFC3339),
					SummaryText:  s.SummaryText,
					Trigger:      s.Trigger,
				})
			}
			if snaps == nil {
				snaps = []snapshotJSON{}
			}
			out.Snapshots = snaps
		}
	}

	result, err := json.MarshalIndent(out, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal JSON: %w", err)
	}
	fmt.Println(string(result))
	return nil
}
