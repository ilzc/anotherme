package ai

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// Client is an OpenAI-compatible HTTP client for a single provider.
type Client struct {
	endpoint   string
	apiKey     string
	model      string
	httpClient *http.Client
}

// ChatRequest is the request body for the chat completions API.
type ChatRequest struct {
	Model       string    `json:"model"`
	Messages    []Message `json:"messages"`
	Temperature float64   `json:"temperature,omitempty"`
	Stream      bool      `json:"stream,omitempty"`
}

// Message represents a single chat message.
type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// ChatResponse is the response body from the chat completions API.
type ChatResponse struct {
	Choices []Choice `json:"choices"`
}

// Choice is one completion choice.
type Choice struct {
	Message Message `json:"message"`
}

// NewClient creates a new AI client for the given provider.
func NewClient(endpoint, apiKey, model string) *Client {
	return &Client{
		endpoint: strings.TrimRight(endpoint, "/"),
		apiKey:   apiKey,
		model:    model,
		httpClient: &http.Client{
			Timeout: 120 * time.Second,
		},
	}
}

// ChatCompletion sends a non-streaming chat completion request.
func (c *Client) ChatCompletion(ctx context.Context, req ChatRequest) (*ChatResponse, error) {
	if req.Model == "" {
		req.Model = c.model
	}
	req.Stream = false

	body, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	url := c.endpoint + "/chat/completions"
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("send request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("API error (status %d): %s", resp.StatusCode, string(respBody))
	}

	var chatResp ChatResponse
	if err := json.Unmarshal(respBody, &chatResp); err != nil {
		return nil, fmt.Errorf("unmarshal response: %w", err)
	}

	return &chatResp, nil
}
