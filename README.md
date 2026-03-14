<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20CLI-blue" alt="Platform">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/swift-5.9-orange" alt="Swift">
  <img src="https://img.shields.io/badge/go-1.23-00ADD8" alt="Go">
</p>

<h1 align="center">AnotherMe</h1>

<p align="center">
  <strong>Extract Your Soul, Recreate It Digitally.</strong>
</p>

<p align="center">
  <a href="README_CN.md">中文</a> | English
</p>

<p align="center">
  <a href="#-features">Features</a> &bull;
  <a href="#-installation">Installation</a> &bull;
  <a href="#%EF%B8%8F-architecture">Architecture</a> &bull;
  <a href="#-development">Development</a> &bull;
  <a href="#-privacy">Privacy</a>
</p>

---

AnotherMe uses AI to **extract the essence of who you are** from your everyday digital life and **reconstruct it as a living digital replica** — your personality, your memories, your way of thinking.

It silently observes your screen, distills behavioral patterns, knowledge, cognitive style, and values into a structured personality model, and maintains a continuously evolving memory archive. The result is a digital twin that doesn't just mimic you — it **understands** you.

Talk to it, and it responds the way you would. Connect it to external systems, and your personality and memories travel with you — across apps, platforms, and devices.

### What makes this different?

Most AI assistants know nothing about you. AnotherMe builds a **persistent, portable identity layer** that can:

- **Remember** what you've been doing, learning, and caring about
- **Think** in your cognitive style — your decision patterns, your problem-solving approach
- **Speak** in your voice — your vocabulary, your tone, your communication habits
- **Integrate** with external systems via MCP protocol, exporting your digital self wherever it's needed

## ✨ Features

### Soul Extraction Engine

- **Smart screen capture** with privacy-aware multi-layer gate pipeline
- **AI vision analysis** transforms raw screenshots into structured behavioral data
- **Continuous personality modeling** across five dimensions: rhythms, knowledge, cognition, expression, and values
- **Automatic memory formation** — important moments are remembered, trivial ones fade naturally

### Digital Personality Reconstruction

- Multi-layer personality profile that **evolves over time** as you do
- Psychological assessments (MBTI, Big Five) derived from real behavioral data, not self-reported surveys
- Personality snapshots that capture who you are at any point in time
- **Exportable and portable** — your digital identity is yours to take anywhere

### AI Twin Chat

- Chat with an AI that has **internalized your personality**
- Context-aware: draws on your recent activities, long-term interests, and deep personality traits
- Multi-session conversations with persistent memory
- Floating assistant for instant access

### Living Memory System

- Memories are **extracted, scored, consolidated, and pruned** — just like human memory
- Monthly AI-powered consolidation distills thousands of moments into meaningful summaries
- Searchable, browsable memory archive with importance-based lifecycle
- Your experiences persist beyond any single conversation

### Cross-Platform

| Platform | Technology | Status |
|----------|-----------|--------|
| macOS | Swift + SwiftUI | Available |
| Windows | Go + Wails + Vue 3 | In Development |
| CLI | Go | Available |

## 📦 Installation

### macOS App

**Requirements:** macOS 14.0 (Sonoma) or later

#### From Release

1. Download `AnotherMe.dmg` from [Releases](../../releases)
2. Drag `AnotherMe.app` to `/Applications`
3. Launch and grant required permissions:
   - **Screen Recording** — for capturing screen content
   - **Accessibility** — for smart sampling (input activity detection)

#### Build from Source

```bash
git clone https://github.com/user/anotherme.git
cd anotherme/AnotherMe

# Generate Xcode project (if using XcodeGen)
xcodegen generate

# Open in Xcode
open AnotherMe.xcodeproj

# Or build from command line
xcodebuild -project AnotherMe.xcodeproj -scheme AnotherMe -configuration Release build
```

### CLI Tool

**Requirements:** Go 1.23+ or download pre-built binary

#### From Release

```bash
# macOS (Apple Silicon)
curl -L -o anotherme https://github.com/user/anotherme/releases/latest/download/anotherme-cli-darwin-arm64
chmod +x anotherme && sudo mv anotherme /usr/local/bin/

# macOS (Intel)
curl -L -o anotherme https://github.com/user/anotherme/releases/latest/download/anotherme-cli-darwin-amd64
chmod +x anotherme && sudo mv anotherme /usr/local/bin/

# Linux
curl -L -o anotherme https://github.com/user/anotherme/releases/latest/download/anotherme-cli-linux-amd64
chmod +x anotherme && sudo mv anotherme /usr/local/bin/

# Windows — download anotherme-cli-windows-amd64.exe from Releases
```

#### Build from Source

```bash
cd anotherme-cli && go build -o anotherme .
```

#### Configuration

```bash
# Set up AI provider
anotherme config set provider.endpoint "https://api.openai.com/v1"
anotherme config set provider.api_key "sk-..."
anotherme config set provider.model "gpt-4o"

# Verify
anotherme status
```

#### Commands

| Command | Description |
|---------|-------------|
| `anotherme chat` | Interactive chat with your AI twin |
| `anotherme ask "question"` | Quick one-shot question |
| `anotherme query --today` | Query today's activity records |
| `anotherme status` | Show database and config status |
| `anotherme export` | Export data in JSON/CSV format |
| `anotherme serve` | Start MCP server for IDE integration |

### Windows App

**Requirements:** Windows 10 (1903+) or Windows 11, WebView2 Runtime

> Windows client is in active development. Pre-built releases will be available soon.

## 🏗️ Architecture

```
anotherme/
├── AnotherMe/              # macOS app (Swift + SwiftUI)
│   ├── App/                # App lifecycle, state management
│   ├── Core/               # AI client, database, models, security
│   ├── Features/           # Feature modules (Capture, Chat, Modeling, etc.)
│   └── UI/                 # Shared UI components
│
├── anotherme-cli/          # Cross-platform CLI (Go)
│   ├── cmd/                # CLI commands
│   └── pkg/                # Shared packages (agent, ai, db, mcp)
│
└── anotherme-windows/      # Windows app (Go + Wails + Vue 3)
    ├── internal/           # Go backend modules
    └── frontend/           # Vue 3 + Tailwind CSS
```

### Data Flow

```
Screen Activity
      ↓
Gate Pipeline (privacy filters)
      ↓
AI Vision Analysis → Activity Records → Memory Extraction
      ↓                                        ↓
Personality Modeling Engine              Living Memory Archive
(Rhythms → Knowledge → Cognition              ↓
 → Expression → Values)              Memory Consolidation
      ↓                                        ↓
Personality Snapshot ──────────────→ AI Twin Chat
                                    (personality + memory + context)
                                           ↓
                                    MCP / External Systems
                                    (portable digital identity)
```

### Database

All platforms share the same **SQLite** schema (WAL mode). Data stored locally at:

- **macOS / Linux:** `~/.local/share/anotherme/`
- **Windows:** `%APPDATA%\anotherme\`

## 🔧 Development

### Prerequisites

| Component | Requirement |
|-----------|------------|
| macOS App | Xcode 16+, macOS 14+ SDK |
| CLI | Go 1.23+ |
| Windows App | Go 1.23+, Node.js 18+, Wails CLI v2 |

### Build

```bash
# macOS app
cd AnotherMe && xcodebuild -scheme AnotherMe -configuration Release build

# CLI
cd anotherme-cli && go build .

# Windows app
cd anotherme-windows && wails build
```

### Test

```bash
cd anotherme-cli && go test ./...
```

### AI Provider

AnotherMe uses **OpenAI-compatible APIs**. You need a model that supports **vision/multimodal** input for screenshot analysis.

Recommended: `gpt-4o` or equivalent multimodal model. Local models (e.g., Ollama) are also supported.

## 🔒 Privacy

- **100% Local** — All data stays on your device. No cloud uploads, no telemetry.
- **Sensitive App Blocking** — Banking apps, password managers, and security tools are automatically skipped.
- **Keyword Filtering** — Screens with sensitive keywords are filtered out before analysis.
- **Screen Lock Detection** — Capture pauses automatically when the screen is locked.

> **Note:** The AI analysis step sends screenshots to your configured API endpoint. For maximum privacy, use a locally-hosted model.

## 📄 License

[MIT License](LICENSE)
