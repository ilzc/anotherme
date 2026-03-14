<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20CLI-blue" alt="Platform">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/swift-5.9-orange" alt="Swift">
  <img src="https://img.shields.io/badge/go-1.23-00ADD8" alt="Go">
</p>

<h1 align="center">AnotherMe</h1>

<p align="center">
  <strong>提取灵魂，数字复现。</strong>
</p>

<p align="center">
  中文 | <a href="README.md">English</a>
</p>

<p align="center">
  <a href="#-功能特性">功能特性</a> &bull;
  <a href="#-安装指南">安装指南</a> &bull;
  <a href="#%EF%B8%8F-项目架构">项目架构</a> &bull;
  <a href="#-开发指南">开发指南</a> &bull;
  <a href="#-隐私保护">隐私保护</a>
</p>

---

AnotherMe 通过 AI 从你的日常数字生活中**提取你之所以是你的本质**，并将其**重建为一个鲜活的数字复制体** — 你的性格、你的记忆、你的思维方式。

它静默地观察你的屏幕，将行为模式、知识体系、认知风格和价值观蒸馏为结构化的人格模型，并维护一个持续演化的记忆档案。最终的成果不是一个简单的模仿者 — 而是一个**真正理解你**的数字分身。

与它对话，它会以你的方式回应。将它接入外部系统，你的性格和记忆将随你迁移 — 跨应用、跨平台、跨设备。

### 这和其他 AI 有什么不同？

大多数 AI 助手对你一无所知。AnotherMe 构建的是一个**持久的、可迁移的身份层**，它能够：

- **记住**你一直在做什么、在学什么、在关心什么
- **以你的认知方式思考** — 你的决策模式、你解决问题的方法
- **用你的声音说话** — 你的词汇、你的语气、你的表达习惯
- **对接外部系统** — 通过 MCP 协议输出你的数字自我，在任何需要的地方复现

## ✨ 功能特性

### 灵魂提取引擎

- **智能屏幕采集**：隐私感知的多层门控管线
- **AI 视觉分析**：将原始截图转化为结构化的行为数据
- **持续人格建模**：覆盖五个维度 — 行为节律、知识版图、认知风格、表达方式、价值取向
- **自动记忆形成** — 重要时刻被铭记，琐碎细节自然消退

### 数字人格复现

- 多层人格画像**随你一同演化**
- 基于真实行为数据推导的心理评估（MBTI、大五人格），而非自评问卷
- 人格快照定格你在任意时间点的状态
- **可导出、可迁移** — 你的数字身份由你掌控

### AI 分身对话

- 与一个**内化了你的人格**的 AI 对话
- 上下文感知：调用你的近期活动、长期兴趣和深层性格特质
- 多会话对话，记忆跨会话持久化
- 浮动助手，即刻访问

### 活体记忆系统

- 记忆经历**提取、评分、整合、淘汰** — 如同人类记忆的运作方式
- 月度 AI 整合将数千个瞬间蒸馏为有意义的摘要
- 基于重要性生命周期的可搜索、可浏览记忆档案
- 你的经历超越任何单次对话而持续存在

### 跨平台支持

| 平台 | 技术栈 | 状态 |
|------|--------|------|
| macOS | Swift + SwiftUI | 可用 |
| Windows | Go + Wails + Vue 3 | 开发中 |
| CLI | Go | 可用 |

## 📦 安装指南

### macOS 应用

**系统要求：** macOS 14.0 (Sonoma) 或更高版本

#### 从 Release 安装

1. 从 [Releases](../../releases) 下载 `AnotherMe.dmg`
2. 将 `AnotherMe.app` 拖入 `/Applications`
3. 启动并授予所需权限：
   - **屏幕录制** — 用于捕获屏幕内容
   - **辅助功能** — 用于智能采样（输入活动检测）

#### 从源码编译

```bash
git clone https://github.com/user/anotherme.git
cd anotherme/AnotherMe

# 生成 Xcode 项目（如使用 XcodeGen）
xcodegen generate

# 在 Xcode 中打开
open AnotherMe.xcodeproj

# 或命令行编译
xcodebuild -project AnotherMe.xcodeproj -scheme AnotherMe -configuration Release build
```

### CLI 命令行工具

**系统要求：** Go 1.23+ 或下载预编译二进制

#### 从 Release 安装

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

# Windows — 从 Releases 下载 anotherme-cli-windows-amd64.exe
```

#### 从源码编译

```bash
cd anotherme-cli && go build -o anotherme .
```

#### 配置

```bash
# 设置 AI 提供商
anotherme config set provider.endpoint "https://api.openai.com/v1"
anotherme config set provider.api_key "sk-..."
anotherme config set provider.model "gpt-4o"

# 验证配置
anotherme status
```

#### 可用命令

| 命令 | 说明 |
|------|------|
| `anotherme chat` | 与 AI 分身交互式对话 |
| `anotherme ask "问题"` | 快速提问 |
| `anotherme query --today` | 查询今日活动记录 |
| `anotherme status` | 显示数据库和配置状态 |
| `anotherme export` | 导出数据（JSON/CSV） |
| `anotherme serve` | 启动 MCP 服务（IDE 集成） |

### Windows 应用

**系统要求：** Windows 10 (1903+) 或 Windows 11，WebView2 Runtime

> Windows 客户端正在积极开发中，预编译版本即将推出。

## 🏗️ 项目架构

```
anotherme/
├── AnotherMe/              # macOS 应用 (Swift + SwiftUI)
│   ├── App/                # 应用生命周期、状态管理
│   ├── Core/               # AI 客户端、数据库、模型、安全
│   ├── Features/           # 功能模块（采集、对话、建模等）
│   └── UI/                 # 共享 UI 组件
│
├── anotherme-cli/          # 跨平台 CLI (Go)
│   ├── cmd/                # CLI 命令
│   └── pkg/                # 共享包（agent, ai, db, mcp）
│
└── anotherme-windows/      # Windows 应用 (Go + Wails + Vue 3)
    ├── internal/           # Go 后端模块
    └── frontend/           # Vue 3 + Tailwind CSS
```

### 数据流

```
屏幕活动
   ↓
门控管线（隐私过滤）
   ↓
AI 视觉分析 → 活动记录 → 记忆提取
   ↓                        ↓
人格建模引擎            活体记忆档案
(节律 → 知识 → 认知           ↓
 → 表达 → 价值)         记忆整合
   ↓                        ↓
人格快照 ────────────→ AI 分身对话
                       (人格 + 记忆 + 上下文)
                              ↓
                       MCP / 外部系统
                       (可迁移的数字身份)
```

### 数据库

所有平台共享相同的 **SQLite** 数据库模式（WAL 模式）。数据本地存储于：

- **macOS / Linux：** `~/.local/share/anotherme/`
- **Windows：** `%APPDATA%\anotherme\`

## 🔧 开发指南

### 环境要求

| 组件 | 要求 |
|------|------|
| macOS 应用 | Xcode 16+, macOS 14+ SDK |
| CLI | Go 1.23+ |
| Windows 应用 | Go 1.23+, Node.js 18+, Wails CLI v2 |

### 编译

```bash
# macOS 应用
cd AnotherMe && xcodebuild -scheme AnotherMe -configuration Release build

# CLI
cd anotherme-cli && go build .

# Windows 应用
cd anotherme-windows && wails build
```

### 测试

```bash
cd anotherme-cli && go test ./...
```

### AI 提供商

AnotherMe 使用 **OpenAI 兼容 API**，需要支持**视觉/多模态**输入的模型用于截图分析。

推荐：`gpt-4o` 或同等多模态模型。也支持本地模型（如 Ollama）。

## 🔒 隐私保护

- **100% 本地化** — 所有数据留在本地设备，无云端上传，无遥测。
- **敏感应用拦截** — 银行、密码管理器等安全工具自动跳过。
- **关键词过滤** — 包含敏感关键词的窗口在分析前被过滤。
- **锁屏检测** — 屏幕锁定时自动暂停采集。

> **注意：** AI 分析步骤会将截图发送至你配置的 API 端点。如需最大化隐私保护，请使用本地部署的模型。

## 📄 许可证

[MIT License](LICENSE)
