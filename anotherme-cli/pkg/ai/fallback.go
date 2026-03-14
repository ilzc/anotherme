package ai

import (
	"context"
	"fmt"

	"github.com/user/anotherme-cli/pkg/config"
)

// FallbackClient tries multiple providers in order until one succeeds.
type FallbackClient struct {
	providers []providerEntry
}

type providerEntry struct {
	name   string
	client *Client
}

// NewFallbackClient creates a FallbackClient from a list of providers.
func NewFallbackClient(providers []config.Provider) *FallbackClient {
	entries := make([]providerEntry, len(providers))
	for i, p := range providers {
		entries[i] = providerEntry{
			name:   p.Name,
			client: NewClient(p.Endpoint, p.APIKey, p.Model),
		}
	}
	return &FallbackClient{providers: entries}
}

// ChatCompletion tries each provider in order. It returns the response,
// the name of the provider that succeeded, and any error.
// If all providers fail, the last error is returned.
func (fc *FallbackClient) ChatCompletion(ctx context.Context, req ChatRequest) (*ChatResponse, string, error) {
	var lastErr error

	for _, pe := range fc.providers {
		resp, err := pe.client.ChatCompletion(ctx, req)
		if err != nil {
			lastErr = fmt.Errorf("provider %s: %w", pe.name, err)
			continue
		}
		return resp, pe.name, nil
	}

	if lastErr == nil {
		lastErr = fmt.Errorf("no providers configured")
	}
	return nil, "", lastErr
}
