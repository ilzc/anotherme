# AnotherMe CLI

Command-line interface for [AnotherMe](https://github.com/user/anotherme) — query, chat with, and export your personal AI personality data.

## Install

### From Release

Download the latest binary from [GitHub Releases](https://github.com/user/anotherme-cli/releases):

```bash
# macOS Apple Silicon
curl -L -o anotherme https://github.com/user/anotherme-cli/releases/latest/download/anotherme-darwin-arm64
chmod +x anotherme
sudo mv anotherme /usr/local/bin/

# macOS Intel
curl -L -o anotherme https://github.com/user/anotherme-cli/releases/latest/download/anotherme-darwin-amd64
chmod +x anotherme
sudo mv anotherme /usr/local/bin/

# Linux
curl -L -o anotherme https://github.com/user/anotherme-cli/releases/latest/download/anotherme-linux-amd64
chmod +x anotherme
sudo mv anotherme /usr/local/bin/
```

### From Source

```bash
go install github.com/user/anotherme-cli@latest
```

Or build locally:

```bash
git clone https://github.com/user/anotherme-cli.git
cd anotherme-cli
make build
# Binary at dist/anotherme
```

## Quick Start

```bash
# Check data status
anotherme status

# Query personality traits
anotherme query layers
anotherme query layers --layer 3

# Search memories
anotherme query memory "关键词"

# View recent activity
anotherme query activity --range today

# One-shot question
anotherme ask "我最近在关注什么？"

# Interactive chat
anotherme chat

# Export personality
anotherme export --format card
```

## Configuration

On macOS, the CLI automatically reads AI provider settings from the AnotherMe app (UserDefaults + Keychain). No extra configuration needed if the app is already set up.

### Manual Configuration

```bash
# Initialize config file
anotherme config init

# Set AI provider
anotherme config set api-key sk-xxx
anotherme config set endpoint https://api.openai.com/v1
anotherme config set model gpt-4o-mini

# View current config
anotherme config list
```

Config file location: `~/.config/anotherme/config.yaml`

### Environment Variables

| Variable | Description |
|----------|-------------|
| `ANOTHERME_API_KEY` | AI provider API key |
| `ANOTHERME_ENDPOINT` | API endpoint URL |
| `ANOTHERME_MODEL` | Model name |
| `ANOTHERME_DB_PATH` | Database directory path |

Environment variables override config file values.

## Commands

| Command | Description |
|---------|-------------|
| `status` | Show data summary (trait counts, memories, activities) |
| `query layers` | List personality traits from all or specific layers |
| `query memory <keyword>` | Search memories by keyword |
| `query activity` | Show activity summary for a time range |
| `chat` | Interactive conversation REPL |
| `ask <question>` | One-shot question |
| `export` | Export personality data (formats: minimal, card, json, archive) |
| `serve` | Start MCP server for Claude Code integration |
| `config` | Manage configuration (set, get, list, init) |

## MCP Server (Claude Code Integration)

AnotherMe can run as an [MCP](https://modelcontextprotocol.io/) server, providing personality-aware tools to Claude Code.

Add to `~/.claude/claude_code_config.json`:

```json
{
  "mcpServers": {
    "anotherme": {
      "command": "anotherme",
      "args": ["serve"],
      "env": {
        "ANOTHERME_DB_PATH": "~/Library/Application Support/AnotherMe/"
      }
    }
  }
}
```

Available MCP tools:

| Tool | Description |
|------|-------------|
| `chat` | Send a message using the full personality pipeline |
| `query_personality` | Query traits from the 5-layer model |
| `query_activity` | Query recent user activities |
| `recall_memory` | Search stored memories |
| `get_insights` | Retrieve AI-generated insights |
| `export_personality` | Export personality profile |

## Personality Layers

AnotherMe uses a 5-layer personality model:

| Layer | Name | Description |
|-------|------|-------------|
| L1 | Rhythm | Daily routines, work patterns, app usage |
| L2 | Knowledge | Topics of interest, knowledge graph |
| L3 | Cognitive | Problem-solving approach, decision speed, learning style |
| L4 | Expression | Writing style, vocabulary, tone |
| L5 | Values | Priorities, recurring themes, work-life balance |

## Database

The CLI reads from the same SQLite databases as the AnotherMe macOS app:

Default location: `~/Library/Application Support/AnotherMe/`

| File | Access | Description |
|------|--------|-------------|
| `activity.sqlite` | read-only | Screen capture activity logs |
| `memory.sqlite` | read-only | Stored memory points |
| `layer1_rhythms.sqlite` | read-only | Layer 1 rhythm traits |
| `layer2_knowledge.sqlite` | read-only | Layer 2 knowledge traits |
| `layer3_cognitive.sqlite` | read-only | Layer 3 cognitive traits |
| `layer4_expression.sqlite` | read-only | Layer 4 expression traits |
| `layer5_values.sqlite` | read-only | Layer 5 value traits |
| `insights.sqlite` | read-only | AI-generated insights |
| `snapshots.sqlite` | read-only | Personality snapshots |
| `chat.sqlite` | read-write | Chat sessions and messages |

## Build

```bash
make build          # Build for current platform
make build-all      # Cross-compile for all platforms
make clean          # Remove build artifacts
```

## License

MIT
