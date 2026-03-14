package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/user/anotherme-cli/pkg/db"
)

// ToolDef is the MCP tool definition returned by tools/list.
type ToolDef struct {
	Name        string      `json:"name"`
	Description string      `json:"description"`
	InputSchema interface{} `json:"inputSchema"`
}

// layerNames maps layer index (0-4) to human-readable names.
var layerNames = []string{"Rhythm", "Knowledge", "Cognitive", "Expression", "Value"}

// getToolDefinitions returns the 6 MCP tool definitions.
func getToolDefinitions() []ToolDef {
	return []ToolDef{
		{
			Name:        "chat",
			Description: "Send a message to AnotherMe and get a reply. Uses the full personality-aware conversation pipeline.",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"message": map[string]interface{}{
						"type":        "string",
						"description": "The message to send",
					},
					"session_id": map[string]interface{}{
						"type":        "string",
						"description": "Optional session ID to continue a conversation. A new session is created if omitted.",
					},
				},
				"required": []string{"message"},
			},
		},
		{
			Name:        "query_personality",
			Description: "Query personality traits from AnotherMe's 5-layer personality model. Layers: 1=Rhythm, 2=Knowledge, 3=Cognitive, 4=Expression, 5=Value.",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"layer": map[string]interface{}{
						"type":        "integer",
						"description": "Layer number (1-5) to query. Omit to get all layers.",
						"minimum":     1,
						"maximum":     5,
					},
					"format": map[string]interface{}{
						"type":        "string",
						"description": "Output format: 'summary' for a brief overview, 'detailed' for full trait data.",
						"enum":        []string{"summary", "detailed"},
						"default":     "summary",
					},
				},
			},
		},
		{
			Name:        "query_activity",
			Description: "Query recent user activities captured by AnotherMe, including app usage, window titles, and content summaries.",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"range": map[string]interface{}{
						"type":        "string",
						"description": "Time range to query.",
						"enum":        []string{"today", "last_7_days", "last_30_days"},
					},
					"limit": map[string]interface{}{
						"type":        "integer",
						"description": "Maximum number of activities to return.",
						"default":     20,
					},
				},
				"required": []string{"range"},
			},
		},
		{
			Name:        "recall_memory",
			Description: "Search through AnotherMe's stored memories by keyword. Returns memories ranked by importance.",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"query": map[string]interface{}{
						"type":        "string",
						"description": "Keyword or phrase to search for in memories.",
					},
					"limit": map[string]interface{}{
						"type":        "integer",
						"description": "Maximum number of memories to return.",
						"default":     5,
					},
				},
				"required": []string{"query"},
			},
		},
		{
			Name:        "get_insights",
			Description: "Retrieve AI-generated insights about the user's personality, behavior patterns, and trends.",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"limit": map[string]interface{}{
						"type":        "integer",
						"description": "Maximum number of insights to return.",
						"default":     10,
					},
				},
			},
		},
		{
			Name:        "export_personality",
			Description: "Export the user's personality profile in different formats. Aggregates traits from all 5 layers.",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"format": map[string]interface{}{
						"type":        "string",
						"description": "Export format: 'minimal' for a one-paragraph summary, 'card' for a structured profile card, 'json' for raw data.",
						"enum":        []string{"minimal", "card", "json"},
						"default":     "card",
					},
				},
			},
		},
	}
}

// dispatchTool routes a tool call to the appropriate handler.
func dispatchTool(s *Server, name string, args json.RawMessage) (string, error) {
	switch name {
	case "chat":
		return toolChat(s, args)
	case "query_personality":
		return toolQueryPersonality(s, args)
	case "query_activity":
		return toolQueryActivity(s, args)
	case "recall_memory":
		return toolRecallMemory(s, args)
	case "get_insights":
		return toolGetInsights(s, args)
	case "export_personality":
		return toolExportPersonality(s, args)
	default:
		return "", fmt.Errorf("unknown tool: %s", name)
	}
}

// ── chat ──────────────────────────────────────────────────────────────────────

func toolChat(s *Server, args json.RawMessage) (string, error) {
	var params struct {
		Message   string `json:"message"`
		SessionID string `json:"session_id"`
	}
	if err := json.Unmarshal(args, &params); err != nil {
		return "", fmt.Errorf("invalid arguments: %w", err)
	}
	if params.Message == "" {
		return "", fmt.Errorf("message is required")
	}

	sessionID := params.SessionID
	if sessionID == "" {
		sessionID = uuid.New().String()
		session := db.ChatSession{
			ID:        sessionID,
			CreatedAt: time.Now(),
			Title:     "MCP Chat",
		}
		if err := db.CreateSession(s.mgr.ChatDB(), session); err != nil {
			return "", fmt.Errorf("create session: %w", err)
		}
	}

	ctx := context.Background()
	reply, err := s.service.SendMessage(ctx, s.chatClient, s.routerClient, params.Message, sessionID)
	if err != nil {
		return "", fmt.Errorf("send message: %w", err)
	}

	return reply, nil
}

// ── query_personality ─────────────────────────────────────────────────────────

func toolQueryPersonality(s *Server, args json.RawMessage) (string, error) {
	var params struct {
		Layer  *int   `json:"layer"`
		Format string `json:"format"`
	}
	if err := json.Unmarshal(args, &params); err != nil {
		return "", fmt.Errorf("invalid arguments: %w", err)
	}
	if params.Format == "" {
		params.Format = "summary"
	}

	startLayer := 1
	endLayer := 5
	if params.Layer != nil {
		l := *params.Layer
		if l < 1 || l > 5 {
			return "", fmt.Errorf("layer must be between 1 and 5")
		}
		startLayer = l
		endLayer = l
	}

	var sb strings.Builder

	for i := startLayer; i <= endLayer; i++ {
		layerDB := s.mgr.LayerDB(i)
		if layerDB == nil {
			sb.WriteString(fmt.Sprintf("Layer %d (%s): not available\n", i, layerNames[i-1]))
			continue
		}

		traits, err := db.FetchTraits(layerDB, i)
		if err != nil {
			sb.WriteString(fmt.Sprintf("Layer %d (%s): error fetching traits: %v\n", i, layerNames[i-1], err))
			continue
		}

		if params.Format == "summary" {
			sb.WriteString(fmt.Sprintf("Layer %d (%s): %d traits\n", i, layerNames[i-1], len(traits)))
			for _, t := range traits {
				sb.WriteString(fmt.Sprintf("  - %s: %s (confidence: %.2f)\n", t.Dimension, t.Value, t.Confidence))
			}
		} else {
			sb.WriteString(fmt.Sprintf("Layer %d (%s): %d traits\n", i, layerNames[i-1], len(traits)))
			for _, t := range traits {
				sb.WriteString(fmt.Sprintf("  [%s]\n", t.Dimension))
				sb.WriteString(fmt.Sprintf("    Value: %s\n", t.Value))
				sb.WriteString(fmt.Sprintf("    Confidence: %.4f\n", t.Confidence))
				if t.Description != nil {
					sb.WriteString(fmt.Sprintf("    Description: %s\n", *t.Description))
				}
				if t.EvidenceCount != nil {
					sb.WriteString(fmt.Sprintf("    Evidence Count: %d\n", *t.EvidenceCount))
				}
				if t.FirstObserved != nil {
					sb.WriteString(fmt.Sprintf("    First Observed: %s\n", t.FirstObserved.Format(time.RFC3339)))
				}
				sb.WriteString(fmt.Sprintf("    Last Updated: %s\n", t.LastUpdated.Format(time.RFC3339)))
			}
		}
		sb.WriteString("\n")
	}

	return sb.String(), nil
}

// ── query_activity ────────────────────────────────────────────────────────────

func toolQueryActivity(s *Server, args json.RawMessage) (string, error) {
	var params struct {
		Range string `json:"range"`
		Limit int    `json:"limit"`
	}
	if err := json.Unmarshal(args, &params); err != nil {
		return "", fmt.Errorf("invalid arguments: %w", err)
	}
	if params.Limit <= 0 {
		params.Limit = 20
	}

	now := time.Now()
	var since time.Time
	switch params.Range {
	case "today":
		since = time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	case "last_7_days":
		since = now.AddDate(0, 0, -7)
	case "last_30_days":
		since = now.AddDate(0, 0, -30)
	default:
		return "", fmt.Errorf("invalid range '%s': must be today, last_7_days, or last_30_days", params.Range)
	}

	actDB := s.mgr.ActivityDB()
	if actDB == nil {
		return "", fmt.Errorf("activity database not available")
	}

	activities, err := db.FetchActivities(actDB, since, params.Limit)
	if err != nil {
		return "", fmt.Errorf("fetch activities: %w", err)
	}

	if len(activities) == 0 {
		return fmt.Sprintf("No activities found for range '%s'.", params.Range), nil
	}

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Activities (%s): %d results\n\n", params.Range, len(activities)))

	for _, a := range activities {
		sb.WriteString(fmt.Sprintf("[%s] %s - %s\n", a.Timestamp.Format("2006-01-02 15:04"), a.AppName, a.ActivityCategory))
		if a.WindowTitle != "" {
			sb.WriteString(fmt.Sprintf("  Window: %s\n", a.WindowTitle))
		}
		if a.ContentSummary != nil && *a.ContentSummary != "" {
			sb.WriteString(fmt.Sprintf("  Summary: %s\n", *a.ContentSummary))
		}
		if len(a.Topics) > 0 {
			sb.WriteString(fmt.Sprintf("  Topics: %s\n", strings.Join(a.Topics, ", ")))
		}
		sb.WriteString("\n")
	}

	return sb.String(), nil
}

// ── recall_memory ─────────────────────────────────────────────────────────────

func toolRecallMemory(s *Server, args json.RawMessage) (string, error) {
	var params struct {
		Query string `json:"query"`
		Limit int    `json:"limit"`
	}
	if err := json.Unmarshal(args, &params); err != nil {
		return "", fmt.Errorf("invalid arguments: %w", err)
	}
	if params.Query == "" {
		return "", fmt.Errorf("query is required")
	}
	if params.Limit <= 0 {
		params.Limit = 5
	}

	memDB := s.mgr.MemoryDB()
	if memDB == nil {
		return "", fmt.Errorf("memory database not available")
	}

	memories, err := db.SearchMemories(memDB, params.Query, params.Limit)
	if err != nil {
		return "", fmt.Errorf("search memories: %w", err)
	}

	if len(memories) == 0 {
		return fmt.Sprintf("No memories found matching '%s'.", params.Query), nil
	}

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Memories matching '%s': %d results\n\n", params.Query, len(memories)))

	for i, m := range memories {
		sb.WriteString(fmt.Sprintf("[%d] %s\n", i+1, m.CreatedAt.Format(time.RFC3339)))
		sb.WriteString(fmt.Sprintf("    %s\n", m.Content))
		sb.WriteString(fmt.Sprintf("    Category: %s | Importance: %.2f", m.Category, m.Importance))
		if len(m.Keywords) > 0 {
			sb.WriteString(fmt.Sprintf(" | Keywords: %s", strings.Join(m.Keywords, ", ")))
		}
		sb.WriteString("\n\n")
	}

	return sb.String(), nil
}

// ── get_insights ──────────────────────────────────────────────────────────────

func toolGetInsights(s *Server, args json.RawMessage) (string, error) {
	var params struct {
		Limit int `json:"limit"`
	}
	if err := json.Unmarshal(args, &params); err != nil {
		return "", fmt.Errorf("invalid arguments: %w", err)
	}
	if params.Limit <= 0 {
		params.Limit = 10
	}

	insightDB := s.mgr.InsightDB()
	if insightDB == nil {
		return "", fmt.Errorf("insight database not available")
	}

	insights, err := db.FetchInsights(insightDB, params.Limit)
	if err != nil {
		return "", fmt.Errorf("fetch insights: %w", err)
	}

	if len(insights) == 0 {
		return "No insights available.", nil
	}

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Insights: %d results\n\n", len(insights)))

	for i, ins := range insights {
		sb.WriteString(fmt.Sprintf("[%d] %s (%s)\n", i+1, ins.Title, ins.Type))
		sb.WriteString(fmt.Sprintf("    Date: %s\n", ins.CreatedAt.Format(time.RFC3339)))
		sb.WriteString(fmt.Sprintf("    %s\n", ins.Content))
		if len(ins.RelatedLayers) > 0 {
			layerStrs := make([]string, len(ins.RelatedLayers))
			for j, l := range ins.RelatedLayers {
				if l >= 1 && l <= 5 {
					layerStrs[j] = fmt.Sprintf("L%d(%s)", l, layerNames[l-1])
				} else {
					layerStrs[j] = fmt.Sprintf("L%d", l)
				}
			}
			sb.WriteString(fmt.Sprintf("    Related Layers: %s\n", strings.Join(layerStrs, ", ")))
		}
		sb.WriteString("\n")
	}

	return sb.String(), nil
}

// ── export_personality ────────────────────────────────────────────────────────

func toolExportPersonality(s *Server, args json.RawMessage) (string, error) {
	var params struct {
		Format string `json:"format"`
	}
	if err := json.Unmarshal(args, &params); err != nil {
		return "", fmt.Errorf("invalid arguments: %w", err)
	}
	if params.Format == "" {
		params.Format = "card"
	}

	// Collect traits from all 5 layers
	allLayers := make([]layerExport, 0, 5)

	for i := 1; i <= 5; i++ {
		ld := layerExport{Layer: i, LayerName: layerNames[i-1]}
		layerDB := s.mgr.LayerDB(i)
		if layerDB != nil {
			traits, err := db.FetchTraits(layerDB, i)
			if err == nil {
				ld.Traits = traits
			}
		}
		if ld.Traits == nil {
			ld.Traits = []db.Trait{}
		}
		allLayers = append(allLayers, ld)
	}

	switch params.Format {
	case "minimal":
		return formatMinimal(allLayers), nil
	case "card":
		return formatCard(allLayers), nil
	case "json":
		return formatJSON(allLayers)
	default:
		return "", fmt.Errorf("invalid format '%s': must be minimal, card, or json", params.Format)
	}
}

type layerExport struct {
	Layer     int        `json:"layer"`
	LayerName string     `json:"layer_name"`
	Traits    []db.Trait `json:"traits"`
}

func formatMinimal(layers []layerExport) string {
	var parts []string
	for _, l := range layers {
		if len(l.Traits) == 0 {
			continue
		}
		traitStrs := make([]string, 0, len(l.Traits))
		for _, t := range l.Traits {
			traitStrs = append(traitStrs, fmt.Sprintf("%s=%s", t.Dimension, t.Value))
		}
		parts = append(parts, fmt.Sprintf("%s: %s", l.LayerName, strings.Join(traitStrs, ", ")))
	}

	if len(parts) == 0 {
		return "No personality data available."
	}

	return "Personality Profile: " + strings.Join(parts, ". ") + "."
}

func formatCard(layers []layerExport) string {
	var sb strings.Builder
	sb.WriteString("=== AnotherMe Personality Profile ===\n\n")

	totalTraits := 0
	for _, l := range layers {
		totalTraits += len(l.Traits)
	}
	sb.WriteString(fmt.Sprintf("Total traits: %d across %d layers\n\n", totalTraits, len(layers)))

	for _, l := range layers {
		sb.WriteString(fmt.Sprintf("--- Layer %d: %s (%d traits) ---\n", l.Layer, l.LayerName, len(l.Traits)))
		if len(l.Traits) == 0 {
			sb.WriteString("  (no traits)\n")
		} else {
			for _, t := range l.Traits {
				sb.WriteString(fmt.Sprintf("  %s: %s (%.2f)\n", t.Dimension, t.Value, t.Confidence))
			}
		}
		sb.WriteString("\n")
	}

	return sb.String()
}

func formatJSON(layers []layerExport) (string, error) {
	// Build a clean JSON export
	type traitExport struct {
		Dimension   string  `json:"dimension"`
		Value       string  `json:"value"`
		Confidence  float64 `json:"confidence"`
		Description *string `json:"description,omitempty"`
	}

	type layerOutput struct {
		Layer     int           `json:"layer"`
		LayerName string        `json:"layer_name"`
		Traits    []traitExport `json:"traits"`
	}

	output := make([]layerOutput, len(layers))
	for i, l := range layers {
		lo := layerOutput{
			Layer:     l.Layer,
			LayerName: l.LayerName,
			Traits:    make([]traitExport, len(l.Traits)),
		}
		for j, t := range l.Traits {
			lo.Traits[j] = traitExport{
				Dimension:   t.Dimension,
				Value:       t.Value,
				Confidence:  t.Confidence,
				Description: t.Description,
			}
		}
		output[i] = lo
	}

	data, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		return "", fmt.Errorf("marshal JSON: %w", err)
	}
	return string(data), nil
}
