package agent

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/user/anotherme-cli/pkg/ai"
	"github.com/user/anotherme-cli/pkg/db"
)

// RouterResponse holds the classification result for a user query.
type RouterResponse struct {
	Intent             string  `json:"intent"`               // memory_recall, self_awareness, decision_support, ghostwriting, association_discovery, prediction
	LayersNeeded       []int   `json:"layers_needed"`        // [1,2,3,4,5]
	TimeRange          string  `json:"time_range"`           // today, last_7_days, last_30_days, all
	QueryType          string  `json:"query_type"`           // classification label
	NeedActivityLogs   bool    `json:"need_activity_logs"`
	NeedKnowledgeGraph bool    `json:"need_knowledge_graph"`
	FormatHint         *string `json:"format_hint"`
}

const routerPrompt = `You are the AnotherMe query router. Based on the user's question, determine which data layers and data sources need to be queried.

## Available Data Layers

- Layer 1 (Daily Behavior): App usage time, screen activity summaries, daily rhythm patterns
- Layer 2 (Interests & Preferences): Topics of interest, content preferences, learning directions
- Layer 3 (Personality Traits): Personality trait snapshots, communication style, decision patterns
- Layer 4 (Values & Beliefs): Core value rankings, goal priorities, life principles
- Layer 5 (Deep Narrative): Life themes, self-perception, long-term narratives

## Additional Data Sources

- activity_logs: Raw screenshot analysis records (app name, activity category, content summary)
- knowledge_graph: Knowledge graph nodes and relationships (connections between concepts, people, projects)

## Intent Types

- memory_recall: Recalling past activities or events ("What did I do yesterday")
- self_awareness: Understanding one's own habits, personality, preferences ("What kind of person am I")
- decision_support: Helping make decisions ("Should I choose A or B")
- ghostwriting: Writing content in the user's style ("Write an email for me")
- association_discovery: Finding connections between things ("How are my work and interests related")
- prediction: Predicting or inferring trends ("I might in the future...")

## Output Format

Strictly return the following JSON without adding any extra text:

{
  "intent": "memory_recall|self_awareness|decision_support|ghostwriting|association_discovery|prediction",
  "layers_needed": [1],
  "time_range": "today|last_7_days|last_30_days|all",
  "query_type": "A short classification label, e.g.: daily recall, personality analysis, writing assistance",
  "need_activity_logs": false,
  "need_knowledge_graph": false,
  "format_hint": null
}

## Format Hint (format_hint)

When the user's question involves a specific communication scenario, describe the reply format requirements in format_hint using a natural language sentence.
Examples:
- "Reply to my WeChat" → "WeChat message, split into 2-3 short messages, 1-2 sentences each, separate each with ---"
- "Write an email for me" → "Email format, needs greeting and sign-off, professional tone"
- "Post on my social media" → "Social media post, one paragraph, short and opinionated"
- "Reply to this comment" → "Comment reply, brief and direct, 1-2 sentences"

If it's a general chat (not a ghostwriting scenario), set format_hint to null.
format_hint is free text; any new platform can be described naturally without enumeration.
When the scenario requires multiple messages (e.g., chat messages), specify "separate each with ---" in format_hint.

## Routing Principles

1. Minimize data layers: Prefer selecting 1-2 most relevant layers, avoid querying all
2. Narrow time range: Use today over last_7_days when possible, use last_7_days over last_30_days when possible
3. activity_logs should only be enabled when raw screen activity is needed
4. knowledge_graph should only be enabled when concept associations or cross-topic analysis is needed`

// Route calls AI to classify the user question and determine intent and data layers needed.
// Returns defaultRoute() on any error — never fails.
func Route(ctx context.Context, aiClient *ai.Client, question string, recentMessages []db.ChatMessage) *RouterResponse {
	messages := []ai.Message{
		{Role: "system", Content: routerPrompt},
	}

	// Include recent conversation context
	for _, msg := range recentMessages {
		messages = append(messages, ai.Message{
			Role:    msg.Role,
			Content: msg.Content,
		})
	}

	messages = append(messages, ai.Message{
		Role:    "user",
		Content: question,
	})

	req := ai.ChatRequest{
		Messages:    messages,
		Temperature: 0.1,
	}

	resp, err := aiClient.ChatCompletion(ctx, req)
	if err != nil {
		return defaultRoute()
	}

	if len(resp.Choices) == 0 {
		return defaultRoute()
	}

	content := resp.Choices[0].Message.Content

	var route RouterResponse
	if err := json.Unmarshal([]byte(content), &route); err != nil {
		return defaultRoute()
	}

	// Validate required fields
	if route.Intent == "" {
		return defaultRoute()
	}
	if len(route.LayersNeeded) == 0 {
		route.LayersNeeded = []int{1, 2, 3, 4, 5}
	}
	if route.TimeRange == "" {
		route.TimeRange = "last_7_days"
	}

	return &route
}

// defaultRoute returns a safe fallback route for when routing fails.
func defaultRoute() *RouterResponse {
	return &RouterResponse{
		Intent:             "self_awareness",
		LayersNeeded:       []int{1, 2, 3, 4, 5},
		TimeRange:          "last_7_days",
		QueryType:          "general question",
		NeedActivityLogs:   false,
		NeedKnowledgeGraph: false,
		FormatHint:         nil,
	}
}

// intentLabel returns a description for a given intent (unused externally but handy for debugging).
func intentLabel(intent string) string {
	labels := map[string]string{
		"memory_recall":         "Memory Recall",
		"self_awareness":        "Self-Awareness",
		"decision_support":      "Decision Support",
		"ghostwriting":          "Ghostwriting",
		"association_discovery": "Association Discovery",
		"prediction":            "Prediction",
	}
	if l, ok := labels[intent]; ok {
		return l
	}
	return fmt.Sprintf("Unknown intent (%s)", intent)
}
