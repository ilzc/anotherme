package cmd

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"
)

var (
	dbPath    string
	cfgFile   string
	verbose   bool
	jsonOut   bool
	cliVersion string
)

func SetVersion(v string) {
	cliVersion = v
}

var rootCmd = &cobra.Command{
	Use:   "anotherme",
	Short: "AnotherMe CLI - query and inspect your personal AI data",
	Long: `AnotherMe CLI provides command-line access to your AnotherMe data,
including personality layers, memories, activities, and insights.`,
	Version: "dev",
	PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
		// Expand ~ in dbPath
		if len(dbPath) > 0 && dbPath[0] == '~' {
			home, err := os.UserHomeDir()
			if err != nil {
				return fmt.Errorf("cannot resolve home directory: %w", err)
			}
			dbPath = filepath.Join(home, dbPath[1:])
		}

		// Validate db-path exists
		info, err := os.Stat(dbPath)
		if err != nil {
			if os.IsNotExist(err) {
				return fmt.Errorf("database path does not exist: %s", dbPath)
			}
			return fmt.Errorf("cannot access database path: %w", err)
		}
		if !info.IsDir() {
			return fmt.Errorf("database path is not a directory: %s", dbPath)
		}

		return nil
	},
}

func Execute() {
	rootCmd.Version = cliVersion
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func init() {
	defaultDBPath := filepath.Join("~", "Library", "Application Support", "AnotherMe")
	defaultConfig := filepath.Join("~", ".config", "anotherme", "config.yaml")

	rootCmd.PersistentFlags().StringVar(&dbPath, "db-path", defaultDBPath, "path to AnotherMe database directory")
	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", defaultConfig, "path to config file")
	rootCmd.PersistentFlags().BoolVar(&verbose, "verbose", false, "enable verbose output")
	rootCmd.PersistentFlags().BoolVar(&jsonOut, "json", false, "output in JSON format")
}
