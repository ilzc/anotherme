package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"github.com/user/anotherme-cli/pkg/agent"
	"github.com/user/anotherme-cli/pkg/config"
	"github.com/user/anotherme-cli/pkg/db"
	"github.com/user/anotherme-cli/pkg/mcp"
)

var serveCmd = &cobra.Command{
	Use:   "serve",
	Short: "Start MCP server (stdio transport)",
	Long:  "Start AnotherMe as an MCP server for Claude Code integration. Uses stdio transport.",
	RunE:  runServe,
}

func init() {
	rootCmd.AddCommand(serveCmd)
}

func runServe(cmd *cobra.Command, args []string) error {
	// 1. Open DB
	mgr, err := db.NewManager(dbPath)
	if err != nil {
		return fmt.Errorf("failed to open databases: %w", err)
	}
	defer mgr.Close()

	// 2. Set up AI clients
	chatClient, routerClient, err := setupAIClients()
	if err != nil {
		return fmt.Errorf("failed to set up AI clients: %w", err)
	}

	// 3. Create agent service
	cfg := config.LoadOrDefault()
	service := agent.NewService(mgr, cfg.CacheDir, cfg.ResponseLanguage())

	// 4. Create and run MCP server
	server := mcp.NewServer(mgr, chatClient, routerClient, service)

	fmt.Fprintln(os.Stderr, "AnotherMe MCP server starting (stdio transport)")
	return server.Run()
}
