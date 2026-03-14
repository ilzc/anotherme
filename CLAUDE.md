# CLAUDE.md — AnotherMe Project Guide

## Project Overview

AnotherMe is a privacy-first AI digital twin desktop app. It captures screenshots, analyzes behavior with AI vision, builds a 5-layer personality model, and provides a personalized AI chat experience.

## Repository Structure

```
AnotherMe/           # macOS app — Swift + SwiftUI, macOS 14+
anotherme-cli/       # CLI tool — Go 1.23, also serves as MCP server
anotherme-windows/   # Windows app — Go + Wails v2 + Vue 3 + Tailwind CSS
GRDB.swift/          # SQLite library (git submodule)
docs/                # Internal dev docs (gitignored — NOT committed to public repo)
```

## Build Commands

```bash
# macOS app
cd AnotherMe && xcodebuild -project AnotherMe.xcodeproj -scheme AnotherMe -configuration Release build

# CLI
cd anotherme-cli && go build .

# CLI tests
cd anotherme-cli && go test ./...

# Windows app (requires Windows + Wails CLI)
cd anotherme-windows && wails build
```

## Key Architecture Decisions

### Capture Pipeline (4 Gates)
1. **System state** — skip if screen locked, screensaver active, or system idle
2. **Hard block** — skip sensitive apps (banking, password managers)
3. **Soft filter** — skip windows with sensitive keywords
4. **Pixel dedup** — skip if screen unchanged (per-display 32x32 grayscale thumbnail comparison)

### 5-Layer Personality Model
- L1: Behavioral Rhythms (daily patterns, app usage)
- L2: Knowledge & Interests (topics, depth, co-occurrences)
- L3: Cognitive Style (decision patterns, MBTI/Big Five)
- L4: Expression Style (writing samples, vocabulary)
- L5: Values & Priorities (time allocation, value inference)

### Database
- 10 separate SQLite databases (WAL mode): activity, layer1-5, snapshots, insights, chat, memory
- Default path: `~/.local/share/anotherme/` (macOS/Linux), `%APPDATA%\anotherme\` (Windows)
- CLI packages in `anotherme-cli/pkg/` are shared with Windows app via `replace` directive in go.mod

### AI Provider
- Uses OpenAI-compatible API (vision/multimodal required for screenshot analysis)
- macOS app: native Swift HTTP client
- CLI: `pkg/ai/` client (text-only)
- Windows app: direct HTTP for vision requests (bypasses CLI's text-only client)

## Important Conventions

### UI Language
- macOS and Windows UI are in **Chinese (zh-Hans)**
- "固定间隔" is called **"最小采集间隔"** (minimum capture interval) — it applies to ALL capture modes, not just interval mode
- CLI output is in English

### Capture Interval Semantics
- `intervalSeconds` is a **shared minimum interval** across all 3 capture modes (interval, event-driven, smart sampling)
- Two captures are never closer than `intervalSeconds` apart, regardless of trigger source
- Smart sampling scales up from `intervalSeconds`: active = 1x, idle = 3x, deepIdle = skip

### Modeling Scheduler
- Has a 1-hour cooldown (`thresholdCooldown = 3600`) between threshold-triggered runs to prevent over-analysis
- Daily analysis runs at configurable hour (default 23:00)
- Weekly analysis on configurable day (default Monday)

### Screen Unlock Resume
- `postScreenResumed()` resets `consecutiveUnchangedCount = 0` before posting notification
- This ensures capture resumes after Touch ID / Apple Watch unlock (which don't generate CGEvents)

## Code Signing & Release

### Xcode Signing
- `CODE_SIGN_IDENTITY = "-"` (ad-hoc signing for open-source)
- `DEVELOPMENT_TEAM = ""` (no personal team ID)
- `CODE_SIGN_STYLE = Manual`
- **Never commit personal Apple Team ID or provisioning profiles**

### GitHub Actions
- `.github/workflows/ci.yml` — builds macOS app, CLI (build+test+vet), Windows backend
- `.github/workflows/release.yml` — triggered by `v*` tags, builds and publishes:
  - macOS: `.dmg` (unsigned)
  - CLI: 4 platform binaries + checksums
  - Windows: `.exe` via Wails

### Release Process
```bash
git tag v0.1.0
git push origin v0.1.0
# GitHub Actions will build all platforms and create a Release
```

## .gitignore Essentials

The following MUST stay ignored — never force-add these:
- `docs/` (internal design docs: PRD, TDD — do NOT expose to public repo)
- `.DS_Store`, `xcuserdata/`, `DerivedData/`, `.build/`
- `.env`, `*.p12`, `*.cer`, `*.mobileprovision`, `config.yaml`, `credentials.json`
- `*.sqlite`, `*.db` (user data)
- `node_modules/`, `dist/`, `vendor/`
- `.claude/` (contains local workspace settings)

## Common Pitfalls

- **CLI `pkg/` not `internal/`**: CLI packages were promoted from `internal/` to `pkg/` for cross-project import. Always import as `github.com/user/anotherme-cli/pkg/...`
- **Windows vision requests**: Don't use CLI's `ai.Client` for multimodal — it's text-only. Use direct HTTP POST to the vision endpoint.
- **DB access**: CLI's `db.Manager` opens databases **read-only**. Pipeline and ModelingEngine must open their own read-write connections via `db.Manager.DBPath()`.
- **UUID generation**: Use `uuid.New().String()` (google/uuid), not time-based custom implementations.
- **PowerShell notifications**: Escape single quotes (`'` → `''`) and XML entities in toast notification strings.
