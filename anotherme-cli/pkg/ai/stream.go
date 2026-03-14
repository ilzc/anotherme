package ai

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// StreamCallback is called for each content chunk during streaming.
type StreamCallback func(chunk string)

// StreamDelta represents a single SSE event payload.
type StreamDelta struct {
	Choices []StreamChoice `json:"choices"`
}

// StreamChoice is one choice within a streaming delta.
type StreamChoice struct {
	Delta struct {
		Content string `json:"content"`
	} `json:"delta"`
	FinishReason *string `json:"finish_reason"`
}

// ChatCompletionStream sends a streaming chat completion request.
// It calls callback for every content chunk and returns the full
// accumulated text when the stream finishes.
func (c *Client) ChatCompletionStream(ctx context.Context, req ChatRequest, callback StreamCallback) (string, error) {
	if req.Model == "" {
		req.Model = c.model
	}
	req.Stream = true

	body, err := json.Marshal(req)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	url := c.endpoint + "/chat/completions"
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("create request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+c.apiKey)

	// Use a separate client without the global timeout so the stream
	// can stay open as long as the server keeps sending data.
	streamClient := &http.Client{}
	resp, err := streamClient.Do(httpReq)
	if err != nil {
		return "", fmt.Errorf("send request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		respBody, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("API error (status %d): %s", resp.StatusCode, string(respBody))
	}

	var accumulated strings.Builder
	scanner := bufio.NewScanner(resp.Body)

	for scanner.Scan() {
		line := scanner.Text()

		// SSE lines start with "data: "
		if !strings.HasPrefix(line, "data: ") {
			continue
		}

		data := strings.TrimPrefix(line, "data: ")

		// End-of-stream marker
		if data == "[DONE]" {
			break
		}

		var delta StreamDelta
		if err := json.Unmarshal([]byte(data), &delta); err != nil {
			continue // skip malformed chunks
		}

		for _, choice := range delta.Choices {
			if choice.Delta.Content != "" {
				accumulated.WriteString(choice.Delta.Content)
				if callback != nil {
					callback(choice.Delta.Content)
				}
			}
		}
	}

	if err := scanner.Err(); err != nil {
		return accumulated.String(), fmt.Errorf("read stream: %w", err)
	}

	return accumulated.String(), nil
}
