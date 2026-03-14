package agent

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/user/anotherme-cli/pkg/ai"
	"github.com/user/anotherme-cli/pkg/db"
)

// Service orchestrates the full conversation flow:
// route query -> synthesize persona -> fetch context -> build prompt -> call LLM.
type Service struct {
	mgr                *db.Manager
	promptBuilder      *PromptBuilder
	dataProvider       *DataProvider
	memoryRetriever    *MemoryRetriever
	personaSynthesizer *PersonaSynthesizer
	language           string
}

// NewService creates a new conversation Service.
func NewService(mgr *db.Manager, cacheDir string, language string) *Service {
	return &Service{
		mgr:                mgr,
		promptBuilder:      &PromptBuilder{},
		dataProvider:       NewDataProvider(mgr),
		memoryRetriever:    NewMemoryRetriever(mgr.MemoryDB()),
		personaSynthesizer: NewPersonaSynthesizer(cacheDir, mgr),
		language:           language,
	}
}

// SendMessage performs the full orchestration for a user message and returns the agent reply.
func (s *Service) SendMessage(ctx context.Context, aiClient *ai.Client, routerClient *ai.Client, text string, sessionID string) (string, error) {
	// 1. Save user message to chat DB
	userMsg := db.ChatMessage{
		ID:        uuid.New().String(),
		SessionID: sessionID,
		Timestamp: time.Now(),
		Role:      "user",
		Content:   text,
	}
	if err := db.CreateMessage(s.mgr.ChatDB(), userMsg); err != nil {
		return "", fmt.Errorf("save user message: %w", err)
	}

	// 2. Load recent history (10 messages)
	allMessages, err := db.FetchSessionMessages(s.mgr.ChatDB(), sessionID)
	if err != nil {
		return "", fmt.Errorf("fetch session messages: %w", err)
	}
	recentMessages := allMessages
	if len(recentMessages) > 10 {
		recentMessages = recentMessages[len(recentMessages)-10:]
	}

	// 3. Route the question
	route := Route(ctx, routerClient, text, recentMessages)

	// 4. Fetch persona narrative + style guide
	narrative, _ := s.personaSynthesizer.FetchOrGenerate(ctx, aiClient, s.language)
	styleGuide, _ := s.personaSynthesizer.FetchOrGenerateStyleGuide(ctx, aiClient, s.language)

	// 5. Fetch context data based on route
	layerData, err := s.dataProvider.FetchData(route)
	if err != nil {
		layerData = &LayerData{}
	}

	// 6. Recall memories
	memories, _ := s.memoryRetriever.Recall(text, 10)
	memoriesText := FormatMemories(memories)

	// 7. Build system prompt
	systemPrompt := s.promptBuilder.Build(narrative, styleGuide, *layerData, memoriesText, route, s.language)

	// 8. Call LLM with system prompt + history
	chatMessages := buildLLMMessages(systemPrompt, recentMessages)

	resp, err := aiClient.ChatCompletion(ctx, ai.ChatRequest{
		Messages:    chatMessages,
		Temperature: 0.7,
	})
	if err != nil {
		return "", fmt.Errorf("LLM call failed: %w", err)
	}

	if len(resp.Choices) == 0 {
		return "", fmt.Errorf("empty response from LLM")
	}

	replyText := resp.Choices[0].Message.Content

	// 9. Save agent reply to chat DB
	agentMsg := db.ChatMessage{
		ID:               uuid.New().String(),
		SessionID:        sessionID,
		Timestamp:        time.Now(),
		Role:             "agent",
		Content:          replyText,
		ReferencedLayers: route.LayersNeeded,
	}
	if err := db.CreateMessage(s.mgr.ChatDB(), agentMsg); err != nil {
		return "", fmt.Errorf("save agent message: %w", err)
	}

	// 10. Return reply text
	return replyText, nil
}

// SendMessageStream performs the same orchestration as SendMessage but streams the response.
func (s *Service) SendMessageStream(ctx context.Context, aiClient *ai.Client, routerClient *ai.Client, text string, sessionID string, callback ai.StreamCallback) error {
	// 1. Save user message to chat DB
	userMsg := db.ChatMessage{
		ID:        uuid.New().String(),
		SessionID: sessionID,
		Timestamp: time.Now(),
		Role:      "user",
		Content:   text,
	}
	if err := db.CreateMessage(s.mgr.ChatDB(), userMsg); err != nil {
		return fmt.Errorf("save user message: %w", err)
	}

	// 2. Load recent history (10 messages)
	allMessages, err := db.FetchSessionMessages(s.mgr.ChatDB(), sessionID)
	if err != nil {
		return fmt.Errorf("fetch session messages: %w", err)
	}
	recentMessages := allMessages
	if len(recentMessages) > 10 {
		recentMessages = recentMessages[len(recentMessages)-10:]
	}

	// 3. Route the question
	route := Route(ctx, routerClient, text, recentMessages)

	// 4. Fetch persona narrative + style guide
	narrative, _ := s.personaSynthesizer.FetchOrGenerate(ctx, aiClient, s.language)
	styleGuide, _ := s.personaSynthesizer.FetchOrGenerateStyleGuide(ctx, aiClient, s.language)

	// 5. Fetch context data based on route
	layerData, err := s.dataProvider.FetchData(route)
	if err != nil {
		layerData = &LayerData{}
	}

	// 6. Recall memories
	memories, _ := s.memoryRetriever.Recall(text, 10)
	memoriesText := FormatMemories(memories)

	// 7. Build system prompt
	systemPrompt := s.promptBuilder.Build(narrative, styleGuide, *layerData, memoriesText, route, s.language)

	// 8. Stream LLM response
	chatMessages := buildLLMMessages(systemPrompt, recentMessages)

	fullText, err := aiClient.ChatCompletionStream(ctx, ai.ChatRequest{
		Messages:    chatMessages,
		Temperature: 0.7,
	}, callback)
	if err != nil {
		return fmt.Errorf("LLM stream failed: %w", err)
	}

	// 9. Save agent reply to chat DB
	agentMsg := db.ChatMessage{
		ID:               uuid.New().String(),
		SessionID:        sessionID,
		Timestamp:        time.Now(),
		Role:             "agent",
		Content:          fullText,
		ReferencedLayers: route.LayersNeeded,
	}
	if err := db.CreateMessage(s.mgr.ChatDB(), agentMsg); err != nil {
		return fmt.Errorf("save agent message: %w", err)
	}

	return nil
}

// buildLLMMessages converts system prompt + chat history into LLM message format.
// Maps "agent" role to "assistant" as required by OpenAI-compatible APIs.
func buildLLMMessages(systemPrompt string, history []db.ChatMessage) []ai.Message {
	msgs := []ai.Message{
		{Role: "system", Content: systemPrompt},
	}
	for _, msg := range history {
		role := msg.Role
		if role == "agent" {
			role = "assistant"
		}
		msgs = append(msgs, ai.Message{Role: role, Content: msg.Content})
	}
	return msgs
}
