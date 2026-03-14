package cmd

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/spf13/cobra"
	"github.com/user/anotherme-cli/pkg/agent"
	"github.com/user/anotherme-cli/pkg/config"
	"github.com/user/anotherme-cli/pkg/db"
)

var askStream bool

var askCmd = &cobra.Command{
	Use:   "ask [question]",
	Short: "Ask a one-shot question",
	Long:  "Send a single question to AnotherMe and print the response.",
	Args:  cobra.ExactArgs(1),
	RunE:  runAsk,
}

func init() {
	askCmd.Flags().BoolVar(&askStream, "stream", true, "stream output in real-time")
	rootCmd.AddCommand(askCmd)
}

func runAsk(cmd *cobra.Command, args []string) error {
	question := args[0]

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

	// 4. Create temporary session
	sessionID := uuid.New().String()
	session := db.ChatSession{
		ID:        sessionID,
		CreatedAt: time.Now(),
		Title:     "CLI Ask",
	}
	if err := db.CreateSession(mgr.ChatDB(), session); err != nil {
		return fmt.Errorf("failed to create chat session: %w", err)
	}

	ctx := context.Background()

	// 5. Send message
	if askStream {
		err = service.SendMessageStream(ctx, chatClient, routerClient, question, sessionID, func(chunk string) {
			fmt.Print(chunk)
		})
		if err != nil {
			return fmt.Errorf("stream failed: %w", err)
		}
		fmt.Println()
	} else {
		reply, err := service.SendMessage(ctx, chatClient, routerClient, question, sessionID)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		fmt.Println(reply)
	}

	return nil
}
