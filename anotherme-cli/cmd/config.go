package cmd

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"
	"github.com/user/anotherme-cli/pkg/config"
	"gopkg.in/yaml.v3"
)

var configCmd = &cobra.Command{
	Use:   "config",
	Short: "Manage AnotherMe configuration",
	Long:  "View and modify AnotherMe CLI configuration settings.",
	PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
		// Override root's PersistentPreRunE — config commands don't need the database.
		return nil
	},
}

var configSetCmd = &cobra.Command{
	Use:   "set <key> <value>",
	Short: "Set a configuration value",
	Long:  "Set a configuration key. Supported keys: db-path, api-key, endpoint, model, cache-dir",
	Args:  cobra.ExactArgs(2),
	RunE:  runConfigSet,
}

var configGetCmd = &cobra.Command{
	Use:   "get <key>",
	Short: "Get a configuration value",
	Long:  "Get the value of a configuration key. Supported keys: db-path, api-key, endpoint, model, cache-dir",
	Args:  cobra.ExactArgs(1),
	RunE:  runConfigGet,
}

var configListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all configuration",
	Long:  "Display the full configuration as YAML.",
	RunE:  runConfigList,
}

var configInitCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize configuration",
	Long:  "Show configuration file location and create a default config if none exists.",
	RunE:  runConfigInit,
}

func init() {
	configCmd.AddCommand(configSetCmd)
	configCmd.AddCommand(configGetCmd)
	configCmd.AddCommand(configListCmd)
	configCmd.AddCommand(configInitCmd)
	rootCmd.AddCommand(configCmd)
}

func resolveConfigPath() string {
	path := cfgFile
	if path == "" {
		path = config.DefaultConfigPath()
	}
	// Expand ~
	if len(path) >= 2 && path[:2] == "~/" {
		home, err := os.UserHomeDir()
		if err == nil {
			path = filepath.Join(home, path[2:])
		}
	}
	return path
}

func loadOrCreateConfig() *config.Config {
	path := resolveConfigPath()
	cfg, err := config.Load(path)
	if err != nil {
		// Return a new default config
		cfg = &config.Config{}
	}
	return cfg
}

func ensureFirstProvider(cfg *config.Config) {
	if len(cfg.Providers) == 0 {
		cfg.Providers = []config.Provider{{Name: "default", Endpoint: "https://api.openai.com/v1", Model: "gpt-4o-mini"}}
	}
}

func runConfigSet(cmd *cobra.Command, args []string) error {
	key := args[0]
	value := args[1]

	cfg := loadOrCreateConfig()
	path := resolveConfigPath()

	switch key {
	case "db-path":
		cfg.DBPath = value
	case "api-key":
		ensureFirstProvider(cfg)
		cfg.Providers[0].APIKey = value
	case "endpoint":
		ensureFirstProvider(cfg)
		cfg.Providers[0].Endpoint = value
	case "model":
		ensureFirstProvider(cfg)
		cfg.Providers[0].Model = value
	case "cache-dir":
		cfg.CacheDir = value
	default:
		return fmt.Errorf("unknown config key '%s'. Supported: db-path, api-key, endpoint, model, cache-dir", key)
	}

	if err := config.Save(cfg, path); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	fmt.Printf("Set %s = %s\n", key, value)
	return nil
}

func runConfigGet(cmd *cobra.Command, args []string) error {
	key := args[0]
	cfg := loadOrCreateConfig()

	var value string
	switch key {
	case "db-path":
		value = cfg.DBPath
	case "api-key":
		if len(cfg.Providers) > 0 {
			value = cfg.Providers[0].APIKey
		}
	case "endpoint":
		if len(cfg.Providers) > 0 {
			value = cfg.Providers[0].Endpoint
		}
	case "model":
		if len(cfg.Providers) > 0 {
			value = cfg.Providers[0].Model
		}
	case "cache-dir":
		value = cfg.CacheDir
	default:
		return fmt.Errorf("unknown config key '%s'. Supported: db-path, api-key, endpoint, model, cache-dir", key)
	}

	if value == "" {
		fmt.Println("(not set)")
	} else {
		fmt.Println(value)
	}
	return nil
}

func runConfigList(cmd *cobra.Command, args []string) error {
	cfg := loadOrCreateConfig()

	data, err := yaml.Marshal(cfg)
	if err != nil {
		return fmt.Errorf("failed to marshal config: %w", err)
	}

	fmt.Printf("# Config file: %s\n", resolveConfigPath())
	fmt.Println(string(data))
	return nil
}

func runConfigInit(cmd *cobra.Command, args []string) error {
	path := resolveConfigPath()

	fmt.Printf("Config file location: %s\n", path)

	// Check if file exists
	if _, err := os.Stat(path); err == nil {
		fmt.Println("Config file already exists.")
		fmt.Println()
		// Show current config
		cfg := loadOrCreateConfig()
		data, err := yaml.Marshal(cfg)
		if err == nil {
			fmt.Println("Current configuration:")
			fmt.Println(string(data))
		}
		return nil
	}

	// Create default config
	cfg := &config.Config{
		Providers: []config.Provider{
			{
				Name:     "default",
				Endpoint: "https://api.openai.com/v1",
				Model:    "gpt-4o-mini",
			},
		},
		Functions: map[string]config.FunctionConfig{
			"chat":   {Providers: []string{"default"}, Temperature: 0.7},
			"router": {Providers: []string{"default"}, Temperature: 0.3},
		},
	}

	if err := config.Save(cfg, path); err != nil {
		return fmt.Errorf("failed to create config: %w", err)
	}

	fmt.Println("Created default config file.")
	fmt.Println("Run 'anotherme config set api-key <your-api-key>' to configure your AI provider.")
	return nil
}
