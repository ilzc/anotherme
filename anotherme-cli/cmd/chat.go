package cmd

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"time"

	"github.com/google/uuid"
	"github.com/spf13/cobra"
	"github.com/user/anotherme-cli/pkg/agent"
	"github.com/user/anotherme-cli/pkg/ai"
	"github.com/user/anotherme-cli/pkg/config"
	"github.com/user/anotherme-cli/pkg/db"
)

var chatSessionID string

var chatCmd = &cobra.Command{
	Use:   "chat",
	Short: "Start an interactive chat REPL",
	Long:  "Enter an interactive conversation loop with AnotherMe. Type /quit or /exit to leave.",
	RunE:  runChat,
}

func init() {
	chatCmd.Flags().StringVar(&chatSessionID, "session", "", "resume an existing session by ID")
	rootCmd.AddCommand(chatCmd)
}

func runChat(cmd *cobra.Command, args []string) error {
	// 1. Set up AI clients
	chatClient, routerClient, err := setupAIClients()
	if err != nil {
		return err
	}

	// 2. Open DB
	mgr, err := db.NewManager(dbPath)
	if err != nil {
		return fmt.Errorf("failed to open databases: %w", err)
	}
	defer mgr.Close()

	// 3. Create agent service
	cfg := config.LoadOrDefault()
	service := agent.NewService(mgr, cfg.CacheDir, cfg.ResponseLanguage())

	// 4. Create or resume session
	sessionID := chatSessionID
	if sessionID == "" {
		sessionID = uuid.New().String()
		session := db.ChatSession{
			ID:        sessionID,
			CreatedAt: time.Now(),
			Title:     "CLI Chat",
		}
		if err := db.CreateSession(mgr.ChatDB(), session); err != nil {
			return fmt.Errorf("failed to create chat session: %w", err)
		}
	}

	// 5. Print welcome message
	fmt.Printf("AnotherMe CLI v%s\n", cliVersion)
	fmt.Printf("Database: %s\n", dbPath)
	fmt.Println("Type a message to start chatting. Type /quit to exit.")
	fmt.Println()

	// 6. Read loop
	scanner := bufio.NewScanner(os.Stdin)
	ctx := context.Background()

	for {
		fmt.Print("> ")
		if !scanner.Scan() {
			break
		}
		line := scanner.Text()

		if line == "/quit" || line == "/exit" {
			break
		}
		if line == "" {
			continue
		}

		err := service.SendMessageStream(ctx, chatClient, routerClient, line, sessionID, func(chunk string) {
			fmt.Print(chunk)
		})
		if err != nil {
			fmt.Fprintf(os.Stderr, "\nError: %v\n", err)
			continue
		}
		fmt.Println()
	}

	if err := scanner.Err(); err != nil {
		return fmt.Errorf("input error: %w", err)
	}

	return nil
}

// setupAIClients creates AI clients from config or environment variables.
func setupAIClients() (*ai.Client, *ai.Client, error) {
	cfg := config.LoadOrDefault()
	chatProviders := config.GetFunctionProviders(cfg, "chat")
	routerProviders := config.GetFunctionProviders(cfg, "router")

	// If no config, try env vars
	if len(chatProviders) == 0 {
		apiKey := os.Getenv("ANOTHERME_API_KEY")
		endpoint := os.Getenv("ANOTHERME_ENDPOINT")
		model := os.Getenv("ANOTHERME_MODEL")

		// Also check config providers directly
		if apiKey == "" && len(cfg.Providers) > 0 && cfg.Providers[0].APIKey != "" {
			apiKey = cfg.Providers[0].APIKey
			endpoint = cfg.Providers[0].Endpoint
			model = cfg.Providers[0].Model
		}

		if apiKey == "" {
			return nil, nil, fmt.Errorf("AI not configured. Run 'anotherme config set api-key <key>' or set ANOTHERME_API_KEY")
		}
		if endpoint == "" {
			endpoint = "https://api.openai.com/v1"
		}
		if model == "" {
			model = "gpt-4o-mini"
		}
		chatProviders = []config.Provider{{Name: "env", Endpoint: endpoint, APIKey: apiKey, Model: model}}
		routerProviders = chatProviders
	}

	if len(routerProviders) == 0 {
		routerProviders = chatProviders
	}

	// Use the first provider for direct clients (SendMessage/SendMessageStream expect *ai.Client)
	chatClient := ai.NewClient(chatProviders[0].Endpoint, chatProviders[0].APIKey, chatProviders[0].Model)
	routerClient := ai.NewClient(routerProviders[0].Endpoint, routerProviders[0].APIKey, routerProviders[0].Model)

	return chatClient, routerClient, nil
}
