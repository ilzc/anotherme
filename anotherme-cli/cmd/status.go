package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"text/tabwriter"
	"time"

	"github.com/spf13/cobra"
	"github.com/user/anotherme-cli/pkg/db"
)

type statusOutput struct {
	Layers          map[string]int `json:"layers"`
	TotalTraits     int            `json:"total_traits"`
	TotalMemories   int            `json:"total_memories"`
	TotalActivities int            `json:"total_activities"`
	TotalInsights   int            `json:"total_insights"`
	LatestCapture   string         `json:"latest_capture"`
}

// layerNames maps layer index (0-4) to human-readable names.
var layerNames = []string{"Rhythm", "Knowledge", "Cognitive", "Expression", "Value"}

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show summary of AnotherMe data",
	Long:  "Display trait counts per layer, total memories, activities, insights, and latest capture time.",
	RunE:  runStatus,
}

func init() {
	rootCmd.AddCommand(statusCmd)
}

func runStatus(cmd *cobra.Command, args []string) error {
	mgr, err := db.NewManager(dbPath)
	if err != nil {
		return fmt.Errorf("failed to open databases: %w", err)
	}
	defer mgr.Close()

	// Count traits per layer
	layerCounts := make(map[string]int)
	totalTraits := 0

	for i := 1; i <= 5; i++ {
		layerDB := mgr.LayerDB(i)
		if layerDB == nil {
			layerCounts[layerNames[i-1]] = 0
			continue
		}
		count, err := db.CountTraits(layerDB, i)
		if err != nil {
			if verbose {
				fmt.Fprintf(os.Stderr, "warning: could not count traits for layer %d: %v\n", i, err)
			}
			layerCounts[layerNames[i-1]] = 0
			continue
		}
		layerCounts[layerNames[i-1]] = count
		totalTraits += count
	}

	// Count memories
	totalMemories := 0
	memDB := mgr.MemoryDB()
	if memDB != nil {
		count, err := db.CountMemories(memDB)
		if err != nil {
			if verbose {
				fmt.Fprintf(os.Stderr, "warning: could not count memories: %v\n", err)
			}
		} else {
			totalMemories = count
		}
	}

	// Count activities
	totalActivities := 0
	var latestCapture time.Time
	actDB := mgr.ActivityDB()
	if actDB != nil {
		count, err := db.CountActivities(actDB)
		if err != nil {
			if verbose {
				fmt.Fprintf(os.Stderr, "warning: could not count activities: %v\n", err)
			}
		} else {
			totalActivities = count
		}

		latest, err := db.LatestActivity(actDB)
		if err == nil && latest != nil {
			latestCapture = latest.Timestamp
		} else if verbose && err != nil {
			fmt.Fprintf(os.Stderr, "warning: could not get latest activity: %v\n", err)
		}
	}

	// Count insights
	totalInsights := 0
	insightDB := mgr.InsightDB()
	if insightDB != nil {
		count, err := db.CountInsights(insightDB)
		if err != nil {
			if verbose {
				fmt.Fprintf(os.Stderr, "warning: could not count insights: %v\n", err)
			}
		} else {
			totalInsights = count
		}
	}

	// Format latest capture time
	latestStr := "N/A"
	if !latestCapture.IsZero() {
		latestStr = latestCapture.Format(time.RFC3339)
	}

	// Output
	if jsonOut {
		out := statusOutput{
			Layers:          layerCounts,
			TotalTraits:     totalTraits,
			TotalMemories:   totalMemories,
			TotalActivities: totalActivities,
			TotalInsights:   totalInsights,
			LatestCapture:   latestStr,
		}
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		return enc.Encode(out)
	}

	// Human-readable table
	fmt.Println("AnotherMe Status")
	fmt.Println("=================")
	fmt.Println()

	w := tabwriter.NewWriter(os.Stdout, 0, 4, 2, ' ', 0)

	fmt.Fprintln(w, "PERSONALITY LAYERS")
	fmt.Fprintln(w, "Layer\tTraits")
	fmt.Fprintln(w, "-----\t------")
	for i, name := range layerNames {
		fmt.Fprintf(w, "L%d: %s\t%d\n", i+1, name, layerCounts[name])
	}
	fmt.Fprintf(w, "Total\t%d\n", totalTraits)
	w.Flush()

	fmt.Println()

	w = tabwriter.NewWriter(os.Stdout, 0, 4, 2, ' ', 0)
	fmt.Fprintln(w, "DATA SUMMARY")
	fmt.Fprintln(w, "Category\tCount")
	fmt.Fprintln(w, "--------\t-----")
	fmt.Fprintf(w, "Memories\t%d\n", totalMemories)
	fmt.Fprintf(w, "Activities\t%d\n", totalActivities)
	fmt.Fprintf(w, "Insights\t%d\n", totalInsights)
	w.Flush()

	fmt.Println()
	fmt.Printf("Latest Capture: %s\n", latestStr)

	return nil
}
