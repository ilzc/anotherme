package config

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"gopkg.in/yaml.v3"
)

// Config holds the top-level application configuration.
type Config struct {
	DBPath    string                    `yaml:"db_path"`
	Providers []Provider                `yaml:"providers"`
	Functions map[string]FunctionConfig `yaml:"functions"`
	CacheDir  string                    `yaml:"cache_dir"`
	Language  string                    `yaml:"language"`
}

// Provider describes an AI provider endpoint.
type Provider struct {
	Name     string `yaml:"name"`
	Endpoint string `yaml:"endpoint"`
	APIKey   string `yaml:"api_key"`
	Model    string `yaml:"model"`
}

// FunctionConfig maps a logical function to one or more providers.
type FunctionConfig struct {
	Providers   []string `yaml:"providers"`
	Temperature float64  `yaml:"temperature"`
}

// DefaultConfigPath returns the platform-specific default config file path.
func DefaultConfigPath() string {
	switch runtime.GOOS {
	case "windows":
		return filepath.Join(os.Getenv("APPDATA"), "anotherme", "config.yaml")
	default: // darwin, linux
		home, _ := os.UserHomeDir()
		return filepath.Join(home, ".config", "anotherme", "config.yaml")
	}
}

// defaultDBPath returns the platform-specific default database directory.
func defaultDBPath() string {
	home, _ := os.UserHomeDir()
	switch runtime.GOOS {
	case "darwin":
		return filepath.Join(home, "Library", "Application Support", "AnotherMe")
	case "windows":
		return filepath.Join(os.Getenv("APPDATA"), "AnotherMe")
	default: // linux
		return filepath.Join(home, ".local", "share", "anotherme")
	}
}

// expandTilde replaces a leading ~ with the user's home directory.
func expandTilde(p string) string {
	if strings.HasPrefix(p, "~/") || p == "~" {
		home, err := os.UserHomeDir()
		if err != nil {
			return p
		}
		return filepath.Join(home, p[1:])
	}
	return p
}

// Load reads a YAML config file from the given path.
func Load(path string) (*Config, error) {
	path = expandTilde(path)

	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}

	cfg.DBPath = expandTilde(cfg.DBPath)
	cfg.CacheDir = expandTilde(cfg.CacheDir)

	applyEnvOverrides(&cfg)
	applyDefaults(&cfg)

	return &cfg, nil
}

// LoadOrDefault tries the default config path and returns a usable Config
// even when the file is missing. If no providers are configured, it attempts
// to migrate configuration from the AnotherMe macOS Swift app.
func LoadOrDefault() *Config {
	cfg, err := Load(DefaultConfigPath())
	if err != nil {
		cfg = &Config{}
		applyEnvOverrides(cfg)
		applyDefaults(cfg)
	}

	// If no providers configured, try migrating from the Swift app.
	if len(cfg.Providers) == 0 {
		if migrated := MigrateFromSwiftApp(); migrated != nil && len(migrated.Providers) > 0 {
			cfg.Providers = migrated.Providers
			if migrated.Functions != nil {
				cfg.Functions = migrated.Functions
			}
		}
	}

	return cfg
}

// applyEnvOverrides applies environment variable overrides to the config.
func applyEnvOverrides(cfg *Config) {
	if v := os.Getenv("ANOTHERME_DB_PATH"); v != "" {
		cfg.DBPath = expandTilde(v)
	}

	apiKey := os.Getenv("ANOTHERME_API_KEY")
	endpoint := os.Getenv("ANOTHERME_ENDPOINT")
	model := os.Getenv("ANOTHERME_MODEL")

	if apiKey != "" || endpoint != "" || model != "" {
		// Apply overrides to all existing providers; if none exist, create one.
		if len(cfg.Providers) == 0 {
			cfg.Providers = []Provider{{Name: "default"}}
		}
		for i := range cfg.Providers {
			if apiKey != "" {
				cfg.Providers[i].APIKey = apiKey
			}
			if endpoint != "" {
				cfg.Providers[i].Endpoint = endpoint
			}
			if model != "" {
				cfg.Providers[i].Model = model
			}
		}
	}
}

// DefaultCacheDir returns the platform-specific default cache directory.
func DefaultCacheDir() string {
	home, _ := os.UserHomeDir()
	switch runtime.GOOS {
	case "darwin":
		return filepath.Join(home, "Library", "Caches", "AnotherMe")
	case "windows":
		return filepath.Join(os.Getenv("LOCALAPPDATA"), "AnotherMe", "cache")
	default: // linux
		return filepath.Join(home, ".cache", "anotherme")
	}
}

// applyDefaults fills in zero-value fields with sensible defaults.
func applyDefaults(cfg *Config) {
	if cfg.DBPath == "" {
		cfg.DBPath = defaultDBPath()
	}
	if cfg.CacheDir == "" {
		cfg.CacheDir = DefaultCacheDir()
	}
}

// GetProvider looks up a provider by name. Returns nil if not found.
func GetProvider(cfg *Config, name string) *Provider {
	for i := range cfg.Providers {
		if cfg.Providers[i].Name == name {
			return &cfg.Providers[i]
		}
	}
	return nil
}

// Save writes the config to the given YAML file path, creating parent directories as needed.
func Save(cfg *Config, path string) error {
	path = expandTilde(path)

	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("create config directory: %w", err)
	}

	data, err := yaml.Marshal(cfg)
	if err != nil {
		return fmt.Errorf("marshal config: %w", err)
	}

	if err := os.WriteFile(path, data, 0o644); err != nil {
		return fmt.Errorf("write config file: %w", err)
	}

	return nil
}

// langMap maps language code prefixes to human-readable language names.
var langMap = map[string]string{
	"zh": "Chinese",
	"en": "English",
	"ja": "Japanese",
	"ko": "Korean",
	"fr": "French",
	"de": "German",
	"es": "Spanish",
}

// ResponseLanguage returns the configured language for AI responses.
// Priority: ANOTHERME_LANGUAGE env > config file > LANG/LC_ALL auto-detect > "English".
func (c *Config) ResponseLanguage() string {
	if v := os.Getenv("ANOTHERME_LANGUAGE"); v != "" {
		return v
	}
	if c.Language != "" {
		return c.Language
	}
	// Auto-detect from environment locale
	for _, envKey := range []string{"LC_ALL", "LANG"} {
		if v := os.Getenv(envKey); v != "" {
			// e.g. "zh_CN.UTF-8" -> "zh"
			code := strings.SplitN(v, "_", 2)[0]
			code = strings.SplitN(code, ".", 2)[0]
			if name, ok := langMap[code]; ok {
				return name
			}
		}
	}
	return "English"
}

// GetFunctionProviders resolves the provider names listed in a FunctionConfig
// to their full Provider objects, preserving order.
func GetFunctionProviders(cfg *Config, functionName string) []Provider {
	fc, ok := cfg.Functions[functionName]
	if !ok {
		return nil
	}

	providers := make([]Provider, 0, len(fc.Providers))
	for _, name := range fc.Providers {
		if p := GetProvider(cfg, name); p != nil {
			providers = append(providers, *p)
		}
	}
	return providers
}
