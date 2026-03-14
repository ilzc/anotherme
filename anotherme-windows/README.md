# AnotherMe Windows

AnotherMe 的 Windows 桌面客户端。通过屏幕截图采集分析用户行为，构建 5 层人格模型，提供 AI 数字分身对话。

基于 Go + [Wails](https://wails.io/) + Vue 3 构建。

## 系统要求

- Windows 10 1903+ (Build 18362) 或 Windows 11
- Go 1.23+
- Node.js 18+
- [Wails CLI v2](https://wails.io/docs/gettingstarted/installation)
- WebView2 Runtime（Windows 11 自带，Windows 10 需[手动安装](https://developer.microsoft.com/en-us/microsoft-edge/webview2/)）

## 安装

### 1. 安装 Wails CLI

```bash
go install github.com/wailsapp/wails/v2/cmd/wails@latest
wails doctor  # 检查环境是否就绪
```

### 2. 克隆项目

```bash
git clone https://github.com/user/anotherme.git
cd anotherme/anotherme-windows
```

### 3. 安装前端依赖

```bash
cd frontend
npm install
cd ..
```

### 4. 开发模式运行

```bash
wails dev
```

浏览器和桌面窗口会同时打开，支持热重载。

### 5. 构建发布版本

```bash
wails build
# 输出: build/bin/AnotherMe.exe
```

## 首次使用

### 配置 AI 模型

启动后进入 **设置** 页面，配置 AI 提供商：

1. 填写 **Endpoint**（如 `https://api.openai.com/v1`）
2. 填写 **API Key**
3. 填写 **Model**（如 `gpt-4o`，需支持 Vision）
4. 点击 **测试连接** 验证
5. 点击 **保存**

支持任何 OpenAI 兼容 API（OpenAI、Claude、通义千问、DeepSeek 等）。

> 截图分析需要支持 Vision（图片输入）的模型。

### 开始采集

设置页面或系统托盘中点击 **开始采集**。应用会：

1. 按设定间隔截取屏幕（默认 5 分钟）
2. 调用 AI 分析截图内容（应用、活动、话题、用户表达）
3. 将分析结果存入本地 SQLite 数据库
4. 积累足够数据后自动运行人格建模

### 采集模式

| 模式 | 说明 |
|------|------|
| **定时采集** | 固定间隔（30 秒 ~ 10 分钟），默认 5 分钟 |
| **事件驱动** | 切换应用、切换窗口时自动触发 |
| **智能采集** | 根据用户活跃度自适应调频 |

## 功能

### Dashboard

查看今日活动时间线、采集统计、人格概览。

### AI 对话

与你的数字分身聊天。AI 基于 5 层人格数据 + 记忆系统，以"你自己"的口吻回复。

支持流式输出，实时显示回复内容。

### 人格详情

查看 5 层人格分析结果：

| 层级 | 名称 | 分析内容 |
|------|------|---------|
| L1 | 行为节奏 | 作息类型、专注模式、工作日/周末差异 |
| L2 | 知识图谱 | 知识广度/深度、学习方式、兴趣演变 |
| L3 | 认知风格 | 解决问题方式、决策速度、抽象思维 |
| L4 | 表达风格 | 句子长度、正式度、幽默感、特征词 |
| L5 | 价值取向 | 时间分配、工作生活平衡、技术哲学 |

### 记忆系统

AI 自动从屏幕活动中提取记忆点，用于对话时引用（"你上周不是在研究 XXX 吗"）。

- 自动提取 + 去重
- 重要度衰减 + 月度合并
- 容量控制（300 条上限）

### 悬浮助手

桌面右下角可拖拽的浮动气泡，点击打开快速对话面板。

### 导出

支持 4 种导出格式：

| 格式 | 用途 |
|------|------|
| **极简文本** | ChatGPT Custom Instructions |
| **人格卡片** | Chatbot 预设 / System Prompt |
| **结构化 JSON** | Agent 平台 API 集成 |
| **全量归档** | 备份 / 迁移 |

## 隐私与安全

**所有数据保存在本地，不上传任何服务器。**

### 敏感场景保护

- **硬拦截**：密码管理器、银行客户端、加密货币钱包等应用自动跳过
- **软过滤**：浏览器访问银行/支付页面时，通过窗口标题关键词检测并跳过
- **锁屏暂停**：检测到屏幕锁定或屏保时自动暂停采集
- **空闲检测**：用户无操作超过 3 分钟且屏幕无变化时暂停
- **每日上限**：默认每天最多 200 次 AI 分析调用

### 自定义黑名单

在设置页面可添加/移除需要屏蔽的进程名。

### 数据存储

数据目录：`%APPDATA%\AnotherMe\`

| 文件 | 说明 |
|------|------|
| `activity.sqlite` | 屏幕活动记录 |
| `memory.sqlite` | 记忆点 |
| `layer1_rhythms.sqlite` | 行为节奏特征 |
| `layer2_knowledge.sqlite` | 知识图谱特征 |
| `layer3_cognitive.sqlite` | 认知风格特征 |
| `layer4_expression.sqlite` | 表达风格特征 |
| `layer5_values.sqlite` | 价值取向特征 |
| `chat.sqlite` | 聊天记录 |
| `snapshots.sqlite` | 人格快照 |
| `insights.sqlite` | AI 洞察 |

API Key 通过 Windows Credential Manager 安全存储。

## 与 macOS 版的关系

AnotherMe 有三个组件：

```
macOS 桌面应用 (Swift)     ← 原始版本
Windows 桌面应用 (Go+Wails) ← 本项目
CLI 工具 (Go)              ← 跨平台命令行
```

三者共享相同的 SQLite 数据库 schema，数据可互通。Windows 版复用 CLI 的数据库访问层、AI 客户端和聊天逻辑。

## 项目结构

```
anotherme-windows/
├── main.go                     # 应用入口
├── app.go                      # Wails 绑定 + 服务编排
├── types.go                    # 共享类型
├── internal/
│   ├── capture/                # 屏幕截图采集
│   │   ├── screenshot.go       # GDI BitBlt 截图 (Windows)
│   │   ├── dedup.go            # 像素级去重 (32x32 灰度)
│   │   └── scheduler.go        # 采集调度 (3 种模式)
│   ├── monitor/                # 系统监控
│   │   ├── window.go           # 前台窗口追踪
│   │   ├── input.go            # 用户输入活跃度
│   │   ├── screen_state.go     # 锁屏/屏保/空闲检测
│   │   └── security.go         # 敏感场景过滤
│   ├── analysis/               # AI 分析
│   │   ├── prompts.go          # 全部 AI Prompt 模板
│   │   ├── pipeline.go         # 截图分析队列
│   │   ├── modeling.go         # 5 层人格建模引擎
│   │   ├── memory_extractor.go # 记忆提取
│   │   └── consolidator.go     # 记忆整合
│   ├── notification/           # Windows Toast 通知
│   └── credential/             # Windows 凭据管理
├── frontend/                   # Vue 3 + Tailwind CSS
│   └── src/
│       ├── views/              # 5 个页面
│       ├── components/         # 8 个组件
│       ├── stores/             # 3 个 Pinia Store
│       └── api/                # API 层 + Mock
└── go.mod
```

## 开发

```bash
# 开发模式（热重载）
wails dev

# 仅编译 Go 后端
go build ./...

# 仅编译前端
cd frontend && npm run build

# 代码检查
go vet ./...

# 构建发布版
wails build
```

### 依赖的共享包

Windows 客户端通过 `replace` 指令引用本地的 CLI 共享包：

```
# go.mod
replace github.com/user/anotherme-cli => ../anotherme-cli
```

修改 CLI 的 `pkg/` 包后，Windows 项目会自动使用最新代码。

## 常见问题

### WebView2 Runtime 未安装

Windows 10 用户可能遇到此问题。下载安装：
https://developer.microsoft.com/en-us/microsoft-edge/webview2/

### 截图权限

与 macOS 不同，Windows 截图**不需要特殊权限**。但以管理员权限运行的窗口可能无法被非管理员进程截取。

### AI 分析失败

检查设置页的 AI 模型配置。常见原因：
- API Key 无效或过期
- Endpoint 不可达
- 模型不支持 Vision（图片输入）
- 超出 API 调用额度

连续失败 3 次后自动暂停，系统托盘会显示通知。

### 数据迁移

macOS 和 Windows 使用相同的 SQLite schema。将 macOS 的 `~/Library/Application Support/AnotherMe/` 下所有 `.sqlite` 文件复制到 Windows 的 `%APPDATA%\AnotherMe\` 即可。

## License

MIT
