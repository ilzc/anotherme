package mcp

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"

	"github.com/user/anotherme-cli/pkg/agent"
	"github.com/user/anotherme-cli/pkg/ai"
	"github.com/user/anotherme-cli/pkg/db"
)

// Request is a JSON-RPC 2.0 request.
type Request struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

// Response is a JSON-RPC 2.0 response.
type Response struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Result  interface{}     `json:"result,omitempty"`
	Error   *RPCError       `json:"error,omitempty"`
}

// RPCError is a JSON-RPC 2.0 error object.
type RPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// Server is the MCP server that communicates over stdio.
type Server struct {
	mgr          *db.Manager
	chatClient   *ai.Client
	routerClient *ai.Client
	service      *agent.Service

	logger *log.Logger
}

// NewServer creates a new MCP server.
func NewServer(mgr *db.Manager, chatClient, routerClient *ai.Client, service *agent.Service) *Server {
	return &Server{
		mgr:          mgr,
		chatClient:   chatClient,
		routerClient: routerClient,
		service:      service,
		logger:       log.New(os.Stderr, "[mcp] ", log.LstdFlags),
	}
}

// Run starts the server, reading JSON-RPC requests from stdin and writing responses to stdout.
func (s *Server) Run() error {
	scanner := bufio.NewScanner(os.Stdin)
	// Allow large messages (up to 10 MB)
	scanner.Buffer(make([]byte, 0, 64*1024), 10*1024*1024)
	encoder := json.NewEncoder(os.Stdout)

	s.logger.Println("MCP server started")

	for scanner.Scan() {
		line := scanner.Bytes()
		if len(line) == 0 {
			continue
		}

		var req Request
		if err := json.Unmarshal(line, &req); err != nil {
			s.logger.Printf("invalid JSON: %v", err)
			resp := Response{
				JSONRPC: "2.0",
				Error:   &RPCError{Code: -32700, Message: "Parse error"},
			}
			if err := encoder.Encode(resp); err != nil {
				s.logger.Printf("write error: %v", err)
			}
			continue
		}

		resp := s.handleRequest(&req)
		if resp == nil {
			// Notification (no id), no response needed
			continue
		}

		if err := encoder.Encode(resp); err != nil {
			s.logger.Printf("write error: %v", err)
		}
	}

	if err := scanner.Err(); err != nil && err != io.EOF {
		return fmt.Errorf("stdin read error: %w", err)
	}

	s.logger.Println("MCP server stopped")
	return nil
}

func (s *Server) handleRequest(req *Request) *Response {
	s.logger.Printf("method=%s", req.Method)

	switch req.Method {
	case "initialize":
		return s.handleInitialize(req)
	case "initialized":
		// Notification, no response
		return nil
	case "notifications/initialized":
		// Notification, no response
		return nil
	case "tools/list":
		return s.handleToolsList(req)
	case "tools/call":
		return s.handleToolsCall(req)
	default:
		return &Response{
			JSONRPC: "2.0",
			ID:      req.ID,
			Error:   &RPCError{Code: -32601, Message: fmt.Sprintf("Method not found: %s", req.Method)},
		}
	}
}

func (s *Server) handleInitialize(req *Request) *Response {
	result := map[string]interface{}{
		"protocolVersion": "2024-11-05",
		"capabilities": map[string]interface{}{
			"tools": map[string]interface{}{},
		},
		"serverInfo": map[string]interface{}{
			"name":    "anotherme",
			"version": "1.0.0",
		},
	}

	return &Response{
		JSONRPC: "2.0",
		ID:      req.ID,
		Result:  result,
	}
}

func (s *Server) handleToolsList(req *Request) *Response {
	tools := getToolDefinitions()

	result := map[string]interface{}{
		"tools": tools,
	}

	return &Response{
		JSONRPC: "2.0",
		ID:      req.ID,
		Result:  result,
	}
}

func (s *Server) handleToolsCall(req *Request) *Response {
	var params struct {
		Name      string          `json:"name"`
		Arguments json.RawMessage `json:"arguments"`
	}

	if err := json.Unmarshal(req.Params, &params); err != nil {
		return &Response{
			JSONRPC: "2.0",
			ID:      req.ID,
			Error:   &RPCError{Code: -32602, Message: "Invalid params: " + err.Error()},
		}
	}

	s.logger.Printf("tool call: %s", params.Name)

	result, err := dispatchTool(s, params.Name, params.Arguments)
	if err != nil {
		return &Response{
			JSONRPC: "2.0",
			ID:      req.ID,
			Result: map[string]interface{}{
				"content": []map[string]interface{}{
					{"type": "text", "text": fmt.Sprintf("Error: %v", err)},
				},
				"isError": true,
			},
		}
	}

	return &Response{
		JSONRPC: "2.0",
		ID:      req.ID,
		Result: map[string]interface{}{
			"content": []map[string]interface{}{
				{"type": "text", "text": result},
			},
		},
	}
}
