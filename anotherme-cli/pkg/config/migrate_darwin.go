//go:build darwin

package config

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// swiftProvider mirrors the Swift app's AIModelProvider JSON structure.
type swiftProvider struct {
	ID            string            `json:"id"`
	DisplayName   string            `json:"displayName"`
	Endpoint      string            `json:"endpoint"`
	APIKey        string            `json:"apiKey"`
	ModelName     string            `json:"modelName"`
	CustomHeaders map[string]string `json:"customHeaders"`
}

// swiftAssignment mirrors the Swift app's AIFunctionAssignment JSON structure.
type swiftAssignment struct {
	ProviderIDs []string `json:"providerIDs"`
	Temperature float64  `json:"temperature"`
}

const keychainService = "com.anotherme"

// MigrateFromSwiftApp attempts to read AI provider configuration from the
// AnotherMe macOS app's UserDefaults and Keychain.
// Returns nil if the Swift app config is not found or unreadable.
func MigrateFromSwiftApp() *Config {
	domain := findAppDomain()
	if domain == "" {
		return nil
	}

	providers := readProvidersFromDefaults(domain)
	if len(providers) == 0 {
		return nil
	}

	// Enrich providers with API keys from Keychain.
	for i, p := range providers {
		if key := readKeychainAPIKey(p.ID); key != "" {
			providers[i].APIKey = key
		}
	}

	// Convert Swift providers to Config providers.
	cfgProviders := make([]Provider, 0, len(providers))
	for _, sp := range providers {
		name := sp.DisplayName
		if name == "" {
			name = sp.ID
		}
		cfgProviders = append(cfgProviders, Provider{
			Name:     name,
			Endpoint: sp.Endpoint,
			APIKey:   sp.APIKey,
			Model:    sp.ModelName,
		})
	}

	cfg := &Config{
		Providers: cfgProviders,
	}

	// Read function assignments.
	assignments := readAssignmentsFromDefaults(domain)
	if len(assignments) > 0 {
		functions := make(map[string]FunctionConfig, len(assignments))
		for funcName, sa := range assignments {
			// Map Swift provider IDs to display names used as Provider.Name.
			providerNames := make([]string, 0, len(sa.ProviderIDs))
			for _, pid := range sa.ProviderIDs {
				mapped := false
				for _, sp := range providers {
					if sp.ID == pid {
						name := sp.DisplayName
						if name == "" {
							name = sp.ID
						}
						providerNames = append(providerNames, name)
						mapped = true
						break
					}
				}
				if !mapped {
					providerNames = append(providerNames, pid)
				}
			}
			functions[funcName] = FunctionConfig{
				Providers:   providerNames,
				Temperature: sa.Temperature,
			}
		}
		cfg.Functions = functions
	}

	return cfg
}

// findAppDomain discovers the macOS preferences domain for the AnotherMe Swift app.
func findAppDomain() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}

	prefsDir := filepath.Join(home, "Library", "Preferences")

	// Try known domains first.
	candidates := []string{
		"com.anotherme.app",
	}
	for _, c := range candidates {
		plist := filepath.Join(prefsDir, c+".plist")
		if _, err := os.Stat(plist); err == nil {
			return c
		}
	}

	// Glob for any plist containing "AnotherMe" (case-insensitive search).
	entries, err := os.ReadDir(prefsDir)
	if err != nil {
		return ""
	}
	for _, e := range entries {
		name := e.Name()
		lower := strings.ToLower(name)
		if strings.Contains(lower, "anotherme") && strings.HasSuffix(lower, ".plist") {
			// Strip the .plist suffix to get the domain.
			return strings.TrimSuffix(name, ".plist")
		}
	}

	return ""
}

// readDefaultsData reads a raw Data value from a UserDefaults plist key using plutil.
// Swift's JSONEncoder writes Data values, which plutil -extract with "raw" format
// returns as base64-encoded content.
func readDefaultsData(domain, key string) ([]byte, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}

	plistPath := filepath.Join(home, "Library", "Preferences", domain+".plist")

	// plutil -extract <key> raw -o - <plist>
	// For Data values this outputs base64-encoded bytes.
	cmd := exec.Command("plutil", "-extract", key, "raw", "-o", "-", plistPath)
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("plutil extract %s: %w", key, err)
	}

	raw := strings.TrimSpace(string(output))
	if raw == "" {
		return nil, fmt.Errorf("empty value for key %s", key)
	}

	// Try base64 decode (Data values are base64-encoded by plutil).
	decoded, err := base64.StdEncoding.DecodeString(raw)
	if err != nil {
		// If base64 fails, the value might already be a plain string (e.g. XML type).
		// Try using it as-is.
		return []byte(raw), nil
	}

	return decoded, nil
}

// readProvidersFromDefaults reads the ai.providers key from UserDefaults.
func readProvidersFromDefaults(domain string) []swiftProvider {
	data, err := readDefaultsData(domain, "ai.providers")
	if err != nil {
		return nil
	}

	var providers []swiftProvider
	if err := json.Unmarshal(data, &providers); err != nil {
		return nil
	}

	return providers
}

// readAssignmentsFromDefaults reads the ai.assignments key from UserDefaults.
func readAssignmentsFromDefaults(domain string) map[string]swiftAssignment {
	data, err := readDefaultsData(domain, "ai.assignments")
	if err != nil {
		return nil
	}

	var assignments map[string]swiftAssignment
	if err := json.Unmarshal(data, &assignments); err != nil {
		return nil
	}

	return assignments
}

// readKeychainAPIKey reads an API key from the macOS Keychain using the security CLI tool.
func readKeychainAPIKey(providerID string) string {
	account := fmt.Sprintf("ai.provider.%s.apikey", providerID)

	cmd := exec.Command("security", "find-generic-password",
		"-s", keychainService,
		"-a", account,
		"-w",
	)
	output, err := cmd.Output()
	if err != nil {
		return ""
	}

	return strings.TrimSpace(string(output))
}
