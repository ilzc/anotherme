package agent

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/user/anotherme-cli/pkg/ai"
	"github.com/user/anotherme-cli/pkg/db"
)

const (
	narrativeCacheFile   = "persona_narrative.json"
	styleGuideCacheFile  = "persona_style_guide.json"
	cacheMaxAge          = 24 * time.Hour
)

// PersonaSynthesizer generates and caches persona narrative and style guide from L3/L4/L5 traits.
type PersonaSynthesizer struct {
	cacheDir string
	mgr      *db.Manager
}

type personaCache struct {
	TraitHash string `json:"trait_hash"`
	Timestamp string `json:"timestamp"`
	Content   string `json:"content"`
}

// NewPersonaSynthesizer creates a new PersonaSynthesizer.
func NewPersonaSynthesizer(cacheDir string, mgr *db.Manager) *PersonaSynthesizer {
	return &PersonaSynthesizer{
		cacheDir: cacheDir,
		mgr:      mgr,
	}
}

// FetchOrGenerate returns a cached persona narrative if fresh, otherwise regenerates it.
// Returns nil for cold start (no trait data available).
func (ps *PersonaSynthesizer) FetchOrGenerate(ctx context.Context, aiClient *ai.Client, language string) (*string, error) {
	input, hash, err := ps.buildSynthesisInput()
	if err != nil {
		return nil, err
	}
	if input == "" {
		// Cold start: no trait data
		return nil, nil
	}

	// Include language in hash so cache invalidates on language change
	hash = computeHash(hash + "|lang:" + language)

	// Check cache
	if cached := ps.loadCache(narrativeCacheFile, hash); cached != nil {
		return cached, nil
	}

	// Generate via AI
	prompt := synthesisPrompt(language)
	resp, err := aiClient.ChatCompletion(ctx, ai.ChatRequest{
		Messages: []ai.Message{
			{Role: "system", Content: prompt},
			{Role: "user", Content: input},
		},
		Temperature: 0.3,
	})
	if err != nil {
		return nil, fmt.Errorf("generate persona narrative: %w", err)
	}

	if len(resp.Choices) == 0 {
		return nil, fmt.Errorf("empty response from AI for persona narrative")
	}

	content := resp.Choices[0].Message.Content
	ps.saveCache(narrativeCacheFile, hash, content)

	return &content, nil
}

// FetchOrGenerateStyleGuide returns a cached style guide if fresh, otherwise regenerates it.
// Returns nil for cold start (no trait data available).
func (ps *PersonaSynthesizer) FetchOrGenerateStyleGuide(ctx context.Context, aiClient *ai.Client, language string) (*string, error) {
	input, hash, err := ps.buildStyleInput()
	if err != nil {
		return nil, err
	}
	if input == "" {
		return nil, nil
	}

	// Include language in hash so cache invalidates on language change
	hash = computeHash(hash + "|lang:" + language)

	// Check cache
	if cached := ps.loadCache(styleGuideCacheFile, hash); cached != nil {
		return cached, nil
	}

	// Generate via AI
	prompt := styleDistillationPrompt(language)
	resp, err := aiClient.ChatCompletion(ctx, ai.ChatRequest{
		Messages: []ai.Message{
			{Role: "system", Content: prompt},
			{Role: "user", Content: input},
		},
		Temperature: 0.3,
	})
	if err != nil {
		return nil, fmt.Errorf("generate style guide: %w", err)
	}

	if len(resp.Choices) == 0 {
		return nil, fmt.Errorf("empty response from AI for style guide")
	}

	content := resp.Choices[0].Message.Content
	ps.saveCache(styleGuideCacheFile, hash, content)

	return &content, nil
}

// loadCache reads a cache file and returns the content if the hash matches and it's fresh.
func (ps *PersonaSynthesizer) loadCache(filename, currentHash string) *string {
	path := filepath.Join(ps.cacheDir, filename)
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}

	var cache personaCache
	if err := json.Unmarshal(data, &cache); err != nil {
		return nil
	}

	if cache.TraitHash != currentHash {
		return nil
	}

	ts, err := time.Parse(time.RFC3339, cache.Timestamp)
	if err != nil {
		return nil
	}

	if time.Since(ts) > cacheMaxAge {
		return nil
	}

	return &cache.Content
}

// saveCache writes the persona/style content to a cache file.
func (ps *PersonaSynthesizer) saveCache(filename, hash, content string) {
	_ = os.MkdirAll(ps.cacheDir, 0755)

	cache := personaCache{
		TraitHash: hash,
		Timestamp: time.Now().Format(time.RFC3339),
		Content:   content,
	}

	data, err := json.MarshalIndent(cache, "", "  ")
	if err != nil {
		return
	}

	path := filepath.Join(ps.cacheDir, filename)
	_ = os.WriteFile(path, data, 0644)
}

// l3DimensionLabels maps L3 cognitive trait dimensions to labels.
var l3DimensionLabels = map[string]string{
	"problem_solving_approach": "Problem-Solving Approach",
	"information_processing":   "Information Processing",
	"decision_speed":           "Decision Speed",
	"learning_method":          "Learning Method",
	"abstraction_level":        "Abstraction Level",
	"multitask_tendency":       "Multitasking Tendency",
	"work_rhythm":              "Work Rhythm",
}

// l5DimensionLabels maps L5 value trait dimensions to labels.
var l5DimensionLabels = map[string]string{
	"time_allocation_priority": "Time Allocation Priority",
	"recurring_themes":         "Recurring Focus Areas",
	"work_life_balance":        "Work-Life Balance",
	"self_improvement_index":   "Self-Improvement Drive",
	"priority_ordering":        "Task Prioritization",
	"technology_philosophy":    "Technology Attitude",
}

// buildSynthesisInput collects L3/L4/L5 traits and formats them as input for persona synthesis.
// Returns empty string and empty hash if no data is available.
func (ps *PersonaSynthesizer) buildSynthesisInput() (string, string, error) {
	var parts []string

	// L3 cognitive traits
	if l3DB := ps.mgr.LayerDB(3); l3DB != nil {
		traits, err := db.FetchTraits(l3DB, 3)
		if err == nil && len(traits) > 0 {
			var l3Parts []string
			for _, t := range traits {
				if t.Confidence < 0.5 {
					continue
				}
				if t.Description != nil && *t.Description != "" {
					l3Parts = append(l3Parts, *t.Description)
				} else {
					label := t.Dimension
					if l, ok := l3DimensionLabels[t.Dimension]; ok {
						label = l
					}
					l3Parts = append(l3Parts, fmt.Sprintf("%s: %s", label, t.Value))
				}
			}
			if len(l3Parts) > 0 {
				parts = append(parts, "Cognitive traits:\n"+strings.Join(l3Parts, "\n"))
			}
		}
	}

	// L4 expression traits
	if l4DB := ps.mgr.LayerDB(4); l4DB != nil {
		traits, err := db.FetchTraits(l4DB, 4)
		if err == nil && len(traits) > 0 {
			var l4Parts []string
			for _, t := range traits {
				switch t.Dimension {
				case "style_anchor":
					l4Parts = append(l4Parts, "Style anchor:"+t.Value)
				case "key_differentiators":
					var diffs []map[string]string
					if err := json.Unmarshal([]byte(t.Value), &diffs); err == nil {
						for _, diff := range diffs {
							l4Parts = append(l4Parts, fmt.Sprintf("- %s：%s", diff["trait"], diff["pattern"]))
						}
					} else {
						l4Parts = append(l4Parts, "Key traits:"+t.Value)
					}
				case "curated_examples":
					var examples []struct {
						Text    string `json:"text"`
						Context string `json:"context"`
					}
					if err := json.Unmarshal([]byte(t.Value), &examples); err == nil {
						for _, ex := range examples {
							l4Parts = append(l4Parts, fmt.Sprintf("Sample [%s]: %s", ex.Context, ex.Text))
						}
					}
				default:
					l4Parts = append(l4Parts, fmt.Sprintf("%s: %s", t.Dimension, t.Value))
				}
			}
			if len(l4Parts) > 0 {
				parts = append(parts, "Expression traits:\n"+strings.Join(l4Parts, "\n"))
			}
		}
	}

	// L5 value traits
	if l5DB := ps.mgr.LayerDB(5); l5DB != nil {
		traits, err := db.FetchTraits(l5DB, 5)
		if err == nil && len(traits) > 0 {
			var l5Parts []string
			for _, t := range traits {
				if t.Confidence < 0.5 {
					continue
				}
				if t.Description != nil && *t.Description != "" {
					l5Parts = append(l5Parts, *t.Description)
				} else {
					label := t.Dimension
					if l, ok := l5DimensionLabels[t.Dimension]; ok {
						label = l
					}
					l5Parts = append(l5Parts, fmt.Sprintf("%s: %s", label, t.Value))
				}
			}
			if len(l5Parts) > 0 {
				parts = append(parts, "Value traits:\n"+strings.Join(l5Parts, "\n"))
			}
		}
	}

	if len(parts) == 0 {
		return "", "", nil
	}

	input := strings.Join(parts, "\n\n")
	hash := computeHash(input)
	return input, hash, nil
}

// buildStyleInput collects L4 expression traits for style distillation.
func (ps *PersonaSynthesizer) buildStyleInput() (string, string, error) {
	l4DB := ps.mgr.LayerDB(4)
	if l4DB == nil {
		return "", "", nil
	}

	traits, err := db.FetchTraits(l4DB, 4)
	if err != nil || len(traits) == 0 {
		return "", "", nil
	}

	var parts []string
	for _, t := range traits {
		switch t.Dimension {
		case "style_anchor":
			parts = append(parts, "Style anchor:"+t.Value)
		case "key_differentiators":
			var diffs []map[string]string
			if err := json.Unmarshal([]byte(t.Value), &diffs); err == nil {
				for _, diff := range diffs {
					parts = append(parts, fmt.Sprintf("- %s：%s", diff["trait"], diff["pattern"]))
				}
			} else {
				parts = append(parts, "Key traits:"+t.Value)
			}
		case "curated_examples":
			var examples []struct {
				Text    string `json:"text"`
				Context string `json:"context"`
			}
			if err := json.Unmarshal([]byte(t.Value), &examples); err == nil {
				for _, ex := range examples {
					parts = append(parts, fmt.Sprintf("Sample [%s]: %s", ex.Context, ex.Text))
				}
			}
		default:
			parts = append(parts, fmt.Sprintf("%s: %s", t.Dimension, t.Value))
		}
	}

	if len(parts) == 0 {
		return "", "", nil
	}

	input := strings.Join(parts, "\n")
	hash := computeHash(input)
	return input, hash, nil
}

func computeHash(input string) string {
	h := sha256.Sum256([]byte(input))
	return fmt.Sprintf("%x", h[:8])
}

// LanguageDirective returns the language instruction to append to prompts.
func LanguageDirective(language string) string {
	if language == "" {
		return ""
	}
	return "\n\nIMPORTANT: You MUST respond in " + language + "."
}

func synthesisPrompt(language string) string {
	return `You are a persona profile synthesis expert. Your task is to synthesize structured user profile data into a natural language personality narrative.
Requirements:
1. Output a plain text narrative in three natural paragraphs (no headings, no lists, no markdown):
   - First paragraph: Thinking patterns and behavioral tendencies
   - Second paragraph: Speaking style and language habits, include 2-3 typical short phrases
   - Third paragraph: Value orientation and priorities
2. Write in second person ("you")
3. Be specific and opinionated, avoid generic statements
4. Do not output raw data
5. Keep it between 150-300 words
6. If the data shows contradictions, preserve the contradictions` + LanguageDirective(language)
}

func styleDistillationPrompt(language string) string {
	return `You are a language style analysis expert. Your task is to distill abstract style rules from the user's real speech samples and expression traits.
Requirements:
1. Analyze the provided speech samples and expression traits, extract abstract style patterns
2. Output rules for the following dimensions: sentence structure preferences, word choice tendencies, tone and attitude characteristics, expressions this person avoids
3. Output plain text, do not use markdown
4. Never quote original speech samples verbatim
5. Keep it between 100-200 words
6. Describe in third person` + LanguageDirective(language)
}

// sortTraitsByConfidence sorts traits by confidence descending (unused externally but available).
func sortTraitsByConfidence(traits []db.Trait) {
	sort.Slice(traits, func(i, j int) bool {
		return traits[i].Confidence > traits[j].Confidence
	})
}
