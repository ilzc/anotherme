package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/spf13/cobra"
	"github.com/user/anotherme-cli/pkg/db"
)

var queryCmd = &cobra.Command{
	Use:   "query",
	Short: "Query AnotherMe data",
	Long:  "Query personality traits, memories, and activities from the AnotherMe database.",
}

// ── query layers ────────────────────────────────────────────────────────────

var layerFlag int

var queryLayersCmd = &cobra.Command{
	Use:   "layers",
	Short: "List personality traits",
	Long:  "List personality traits from all layers or a specific layer (1-5).",
	RunE:  runQueryLayers,
}

func runQueryLayers(cmd *cobra.Command, args []string) error {
	if layerFlag < 0 || layerFlag > 5 {
		return fmt.Errorf("layer must be between 1 and 5 (or 0 for all layers)")
	}

	mgr, err := db.NewManager(dbPath)
	if err != nil {
		return fmt.Errorf("failed to open databases: %w", err)
	}
	defer mgr.Close()

	// Use package-level layerNames from status.go

	type layerResult struct {
		Layer     int        `json:"layer"`
		LayerName string     `json:"layer_name"`
		Traits    []db.Trait `json:"traits"`
	}

	var results []layerResult

	startLayer := 1
	endLayer := 5
	if layerFlag > 0 {
		startLayer = layerFlag
		endLayer = layerFlag
	}

	for i := startLayer; i <= endLayer; i++ {
		layerDB := mgr.LayerDB(i)
		if layerDB == nil {
			if verbose {
				fmt.Fprintf(os.Stderr, "warning: layer %d database not available\n", i)
			}
			results = append(results, layerResult{Layer: i, LayerName: layerNames[i-1], Traits: []db.Trait{}})
			continue
		}

		traits, err := db.FetchTraits(layerDB, i)
		if err != nil {
			if verbose {
				fmt.Fprintf(os.Stderr, "warning: could not fetch traits for layer %d: %v\n", i, err)
			}
			results = append(results, layerResult{Layer: i, LayerName: layerNames[i-1], Traits: []db.Trait{}})
			continue
		}
		if traits == nil {
			traits = []db.Trait{}
		}
		results = append(results, layerResult{Layer: i, LayerName: layerNames[i-1], Traits: traits})
	}

	if jsonOut {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		return enc.Encode(results)
	}

	for _, r := range results {
		fmt.Printf("Layer %d: %s (%d traits)\n", r.Layer, r.LayerName, len(r.Traits))
		if len(r.Traits) == 0 {
			fmt.Println("  (no traits)")
		} else {
			w := tabwriter.NewWriter(os.Stdout, 0, 4, 2, ' ', 0)
			fmt.Fprintf(w, "  Dimension\tValue\tConfidence\n")
			fmt.Fprintf(w, "  ---------\t-----\t----------\n")
			for _, t := range r.Traits {
				fmt.Fprintf(w, "  %s\t%s\t%.2f\n", t.Dimension, t.Value, t.Confidence)
			}
			w.Flush()
		}
		fmt.Println()
	}

	return nil
}

// ── query memory ────────────────────────────────────────────────────────────

var memoryLimitFlag int

var queryMemoryCmd = &cobra.Command{
	Use:   "memory [keyword]",
	Short: "Search memories by keyword",
	Long:  "Search through stored memories matching a keyword.",
	Args:  cobra.ExactArgs(1),
	RunE:  runQueryMemory,
}

func runQueryMemory(cmd *cobra.Command, args []string) error {
	keyword := args[0]

	mgr, err := db.NewManager(dbPath)
	if err != nil {
		return fmt.Errorf("failed to open databases: %w", err)
	}
	defer mgr.Close()

	memDB := mgr.MemoryDB()
	if memDB == nil {
		return fmt.Errorf("memory database not available")
	}

	memories, err := db.SearchMemories(memDB, keyword, memoryLimitFlag)
	if err != nil {
		return fmt.Errorf("failed to search memories: %w", err)
	}

	if jsonOut {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		return enc.Encode(memories)
	}

	if len(memories) == 0 {
		fmt.Printf("No memories found matching '%s'\n", keyword)
		return nil
	}

	fmt.Printf("Memories matching '%s' (%d results)\n", keyword, len(memories))
	fmt.Println(strings.Repeat("=", 50))
	fmt.Println()

	for i, m := range memories {
		fmt.Printf("[%d] %s\n", i+1, m.CreatedAt.Format(time.RFC3339))
		fmt.Printf("    %s\n", m.Content)
		fmt.Printf("    Category: %s  |  Source: %s  |  Importance: %.2f\n", m.Category, m.SourceType, m.Importance)
		fmt.Println()
	}

	return nil
}

// ── query activity ──────────────────────────────────────────────────────────

var activityRangeFlag string
var activityLimitFlag int

var queryActivityCmd = &cobra.Command{
	Use:   "activity",
	Short: "Show activity summary",
	Long:  "Display activity summary for a given time range: today, last_7_days, or last_30_days.",
	RunE:  runQueryActivity,
}

func runQueryActivity(cmd *cobra.Command, args []string) error {
	var since time.Time
	now := time.Now()

	switch activityRangeFlag {
	case "today":
		since = time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	case "last_7_days":
		since = now.AddDate(0, 0, -7)
	case "last_30_days":
		since = now.AddDate(0, 0, -30)
	default:
		return fmt.Errorf("invalid range '%s': must be one of today, last_7_days, last_30_days", activityRangeFlag)
	}

	mgr, err := db.NewManager(dbPath)
	if err != nil {
		return fmt.Errorf("failed to open databases: %w", err)
	}
	defer mgr.Close()

	actDB := mgr.ActivityDB()
	if actDB == nil {
		return fmt.Errorf("activity database not available")
	}

	activities, err := db.FetchActivities(actDB, since, activityLimitFlag)
	if err != nil {
		return fmt.Errorf("failed to fetch activities: %w", err)
	}

	if jsonOut {
		type activityOutput struct {
			Range      string            `json:"range"`
			Since      string            `json:"since"`
			Count      int               `json:"count"`
			Activities []db.ActivityRecord `json:"activities"`
		}
		out := activityOutput{
			Range:      activityRangeFlag,
			Since:      since.Format(time.RFC3339),
			Count:      len(activities),
			Activities: activities,
		}
		if out.Activities == nil {
			out.Activities = []db.ActivityRecord{}
		}
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		return enc.Encode(out)
	}

	fmt.Printf("Activity Summary: %s (since %s)\n", activityRangeFlag, since.Format("2006-01-02 15:04"))
	fmt.Println(strings.Repeat("=", 60))

	if len(activities) == 0 {
		fmt.Println("No activities found in this time range.")
		return nil
	}

	fmt.Printf("Total activities: %d\n\n", len(activities))

	w := tabwriter.NewWriter(os.Stdout, 0, 4, 2, ' ', 0)
	fmt.Fprintf(w, "Time\tCategory\tApp\tSummary\n")
	fmt.Fprintf(w, "----\t--------\t---\t-------\n")
	for _, a := range activities {
		summary := ""
		if a.ContentSummary != nil {
			summary = *a.ContentSummary
		}
		if len(summary) > 50 {
			summary = summary[:47] + "..."
		}
		fmt.Fprintf(w, "%s\t%s\t%s\t%s\n", a.Timestamp.Format("2006-01-02 15:04"), a.ActivityCategory, a.AppName, summary)
	}
	w.Flush()

	return nil
}

// ── init ────────────────────────────────────────────────────────────────────

func init() {
	rootCmd.AddCommand(queryCmd)

	// query layers
	queryLayersCmd.Flags().IntVar(&layerFlag, "layer", 0, "filter by layer number (1-5), 0 for all")
	queryCmd.AddCommand(queryLayersCmd)

	// query memory
	queryMemoryCmd.Flags().IntVar(&memoryLimitFlag, "limit", 20, "maximum number of results")
	queryCmd.AddCommand(queryMemoryCmd)

	// query activity
	queryActivityCmd.Flags().StringVar(&activityRangeFlag, "range", "today", "time range: today, last_7_days, last_30_days")
	queryActivityCmd.Flags().IntVar(&activityLimitFlag, "limit", 50, "maximum number of results")
	queryCmd.AddCommand(queryActivityCmd)
}
