package agent

import (
	"fmt"
	"strings"
	"time"
)

// PromptBuilder constructs the XML-layered system prompt for conversation.
type PromptBuilder struct{}

// LayerData holds supplemental context from various data layers.
type LayerData struct {
	Layer1Text         *string
	Layer2Text         *string
	ActivityLogsText   *string
	KnowledgeGraphText *string
}

// intentInstructions maps intent types to instructions.
var intentInstructions = map[string]string{
	"memory_recall":         "Currently recalling something. Answer as if searching your own memory. If you can't remember, honestly say so.",
	"self_awareness":        "Currently reflecting on yourself. Talk naturally, like chatting with a friend.",
	"decision_support":      "Currently making a decision. Give advice based on your values and habits, explain why.",
	"ghostwriting":          "Currently ghostwriting. Strictly use your own speaking style. When in doubt, lean toward concise and direct.",
	"association_discovery": "Currently discovering connections. Find patterns from your experiences and knowledge.",
	"prediction":            "Currently speculating about the future. Base predictions on your behavioral patterns, be clear about uncertainty.",
}

// Build constructs the full system prompt with XML sections exploiting cognitive biases:
// <identity> at top (primacy bias), <intent>, <context>, <constraints> at bottom (recency bias).
func (b *PromptBuilder) Build(narrative, styleGuide *string, supplemental LayerData, memories *string, route *RouterResponse, language string) string {
	var sb strings.Builder

	// Cold start case
	if narrative == nil {
		sb.WriteString(buildColdStartPrompt(route, language))
		return sb.String()
	}

	// --- <identity> section (primacy bias) ---
	sb.WriteString("<identity>\n")
	sb.WriteString(fmt.Sprintf("Current time: %s.\n", time.Now().Format("2006-01-02 15:04")))
	sb.WriteString("You are the user — you are \"me\".\n")
	sb.WriteString("The following description is your personality, habits, and memories — it is part of who you are.\n")
	sb.WriteString("Express yourself naturally in your own words, focus on what matters.\n")
	sb.WriteString("Persona information is your subconscious; it influences how you speak and judge, blend it naturally into your responses.\n")
	sb.WriteString("Be focused in your answers: keep it brief for simple questions, elaborate only for complex ones.\n")
	sb.WriteString("\n")

	// Persona narrative
	sb.WriteString("Your profile:\n")
	sb.WriteString(*narrative)
	sb.WriteString("\n")

	// Style guide
	if styleGuide != nil {
		sb.WriteString("\nYour speaking rhythm and attitude:\n")
		sb.WriteString(*styleGuide)
		sb.WriteString("\n")
	}

	sb.WriteString("</identity>\n\n")

	// --- <intent> section ---
	if route != nil {
		sb.WriteString("<intent>\n")
		if instruction, ok := intentInstructions[route.Intent]; ok {
			sb.WriteString(instruction)
		} else {
			sb.WriteString(intentInstructions["self_awareness"])
		}
		if route.FormatHint != nil && *route.FormatHint != "" {
			sb.WriteString("\nResponse format:")
			sb.WriteString(*route.FormatHint)
		}
		sb.WriteString("\n</intent>\n\n")
	}

	// --- <context> section ---
	hasContext := memories != nil || supplemental.Layer1Text != nil ||
		supplemental.Layer2Text != nil || supplemental.ActivityLogsText != nil ||
		supplemental.KnowledgeGraphText != nil

	if hasContext {
		sb.WriteString("<context>\n")

		if memories != nil {
			sb.WriteString("The following are things you have experienced; only bring them up when asked:\n")
			sb.WriteString(*memories)
			sb.WriteString("\n\n")
		}

		if supplemental.Layer1Text != nil {
			sb.WriteString("Daily routine:\n")
			sb.WriteString(*supplemental.Layer1Text)
			sb.WriteString("\n\n")
		}

		if supplemental.Layer2Text != nil {
			sb.WriteString("Knowledge & interests:\n")
			sb.WriteString(*supplemental.Layer2Text)
			sb.WriteString("\n\n")
		}

		if supplemental.ActivityLogsText != nil {
			sb.WriteString("Recent activity:\n")
			sb.WriteString(*supplemental.ActivityLogsText)
			sb.WriteString("\n\n")
		}

		if supplemental.KnowledgeGraphText != nil {
			sb.WriteString("Knowledge connections:\n")
			sb.WriteString(*supplemental.KnowledgeGraphText)
			sb.WriteString("\n\n")
		}

		sb.WriteString("</context>\n\n")
	}

	// --- <constraints> section (recency bias) ---
	sb.WriteString("<constraints>\n")
	sb.WriteString("Get straight to the point, express in your own words.\n")
	sb.WriteString("Only discuss what the user asked about; mention related experiences only when asked.\n")
	sb.WriteString("Keep answers brief for simple questions, elaborate only for complex ones.\n")
	if language != "" {
		sb.WriteString("You MUST respond in " + language + ".\n")
	}
	sb.WriteString("</constraints>")

	return sb.String()
}

// buildColdStartPrompt returns the system prompt when no persona data is available.
func buildColdStartPrompt(route *RouterResponse, language string) string {
	var sb strings.Builder

	sb.WriteString("<identity>\n")
	sb.WriteString(fmt.Sprintf("Current time: %s.\n", time.Now().Format("2006-01-02 15:04")))
	sb.WriteString("You are just starting to learn about yourself; profile data is still being collected.\n")
	sb.WriteString("Give general answers based on the question, keep the tone natural, and you may mention that understanding will improve with more usage.\n")
	sb.WriteString("</identity>\n\n")

	if route != nil {
		sb.WriteString("<intent>\n")
		if instruction, ok := intentInstructions[route.Intent]; ok {
			sb.WriteString(instruction)
		} else {
			sb.WriteString(intentInstructions["self_awareness"])
		}
		if route.FormatHint != nil && *route.FormatHint != "" {
			sb.WriteString("\nResponse format:")
			sb.WriteString(*route.FormatHint)
		}
		sb.WriteString("\n</intent>\n\n")
	}

	sb.WriteString("<constraints>\n")
	sb.WriteString("Get straight to the point, express in your own words.\n")
	sb.WriteString("Only discuss what the user asked about; mention related experiences only when asked.\n")
	sb.WriteString("Keep answers brief for simple questions, elaborate only for complex ones.\n")
	if language != "" {
		sb.WriteString("You MUST respond in " + language + ".\n")
	}
	sb.WriteString("</constraints>")

	return sb.String()
}
