<p align="center">
  <img src="docs/assets/logo-rounded.png" alt="Paper Codex 标志" width="132">
</p>

<h1 align="center">Paper Codex</h1>

<p align="center">
  本地优先的 macOS 论文文库、PDF 阅读器和 Codex 研究会话工作台。
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

<p align="center">
  <a href="https://swift.org"><img alt="Swift" src="https://img.shields.io/badge/Swift-6.2-orange"></a>
  <img alt="平台" src="https://img.shields.io/badge/macOS-14%2B-blue">
  <img alt="状态" src="https://img.shields.io/badge/status-active%20development-2ea44f">
  <img alt="许可证" src="https://img.shields.io/badge/license-not%20specified-lightgrey">
</p>

<p align="center">
  <a href="#介绍视频">🎬 介绍视频</a> ·
  <a href="#界面预览">🖼️ 界面预览</a> ·
  <a href="#核心功能">✨ 核心功能</a> ·
  <a href="#安装">🚀 安装</a> ·
  <a href="#快速开始">⚡ 快速开始</a> ·
  <a href="#开发">🛠️ 开发</a> ·
  <a href="#架构">🧱 架构</a>
</p>

Paper Codex 是一个原生 macOS 论文工作台，用来阅读、整理和讨论学术论文。PDF、文件夹、标签、笔记、arXiv 缓存、缩略图、阅读会话和生成结果都保存在本机；当你需要 AI 研究助手时，它会在具体论文的本地工作区里调用 Codex CLI。

它面向需要高频阅读论文的研究者：既有本地论文管理器的速度和手感，也有基于真实 PDF 内容的对话、可回跳到原文区域的引用，以及以本机缓存为中心的 arXiv 发现流程。

## 介绍视频

观看带动态 UI 聚焦镜头的详细版 Remotion 产品介绍视频：[docs/assets/videos/paper-codex-intro.mp4](docs/assets/videos/paper-codex-intro.mp4)。

## 界面预览

<p align="center">
  <img src="docs/assets/screenshots/reader-chat.png" alt="PDF 阅读器与 Codex 对话并排显示">
  <br>
  <sub>在同一窗口中阅读 PDF、保留论文标签页，并用原文上下文向 Codex 提问。</sub>
</p>

<table>
  <tr>
    <td width="50%">
      <img src="docs/assets/screenshots/library.png" alt="带文件夹树、搜索、标签和详情面板的论文文库">
    </td>
    <td width="50%">
      <img src="docs/assets/screenshots/discover.png" alt="带论文卡片、缩略图、标签和相似度分数的 arXiv 发现页">
    </td>
  </tr>
  <tr>
    <td><sub>用嵌套文件夹、标签、缩略图和详情面板整理本地论文库。</sub></td>
    <td><sub>浏览 arXiv 结果、本地缓存 PDF 缩略图、查看中文总结，并把论文保存到文库。</sub></td>
  </tr>
</table>

更多界面说明见 [docs/showcase.zh-CN.md](docs/showcase.zh-CN.md)。

## 核心功能

- 📚 **本地论文文库**：导入 PDF，用嵌套文件夹和标签组织论文，并把元数据持久化到 SQLite。
- 📖 **原生 PDF 阅读器**：基于 PDFKit 阅读论文，支持论文标签页、缩放和阅读上下文保持。
- 🔎 **原文锚定对话**：选择 PDF 中的文本后向 Codex 提问，回答中的引用可绑定到原始页面区域。
- 🧰 **Codex 会话工作区**：每个会话都会写入本地工作区，包含 PDF、元数据、锚点、抽取文本和 turn 日志。
- 🎨 **生成图像支持**：imagegen 生成结果可以直接出现在对话中，并支持应用内放大预览。
- 🔭 **本地 arXiv 探索**：直接读取 arXiv 元数据，缓存 feed、PDF 和缩略图，并把论文保存到本地文库。
- ✨ **Codex 增强处理**：为探索结果生成中文标题、总结、贡献说明、标签和相关链接。
- 🧭 **相似度排序**：可选地用 OpenAI-compatible embedding provider，将 arXiv 结果按本地文件夹或标签相似度排序。
- 🔒 **本地优先存储**：当前版本以单机工作区为核心，账号、云同步和产品后端 API 留给后续版本。

## 安装

### 环境要求

- macOS 14 或更新版本
- Swift 6.2 toolchain
- Xcode command line tools
- [Codex CLI](https://github.com/openai/codex)，用于对话、增强处理和图像生成工作流

先检查基础工具：

```bash
swift --version
codex --version
```

### 构建 app bundle

```bash
git clone https://github.com/caopulan/PaperCodex.git
cd PaperCodex
scripts/build-app-bundle.sh
open "$HOME/Applications/PaperCodex.app"
```

默认情况下，构建脚本会把本地签名后的 app bundle 安装到：

```text
~/Applications/PaperCodex.app
```

也可以覆盖输出位置：

```bash
PAPER_CODEX_APP_PATH="$PWD/build/PaperCodex.app" scripts/build-app-bundle.sh
open "$PWD/build/PaperCodex.app"
```

## 快速开始

1. 打开 **Paper Codex**。
2. 在文库页导入 PDF，或在 Discover 中抓取近期 arXiv 论文。
3. 在阅读器里打开一篇论文。
4. 选中 PDF 中的一句话或一段文字。
5. 在右侧对话面板中询问 Codex。

适合的提示词示例：

```text
这篇论文的核心贡献是什么？请引用原文位置。
```

```text
对比这篇论文和当前 session 里的其他论文，哪些假设不一样？
```

```text
用 imagegen 生成一张图，解释这篇论文的训练流程。
```

图像生成成功后，Paper Codex 会把生成资产复制进当前 session 工作区，并直接渲染在对话中。点击缩略图即可在应用内打开可缩放预览，阅读流程保持在同一个窗口里。

## 日常工作流

### 整理论文文库

Paper Codex 会在本地保存 PDF 和元数据。你可以用文库侧栏的文件夹树组织论文，再通过搜索、文件夹范围和阅读动作收窄当前列表。

```text
Library
├── All Papers
├── Diffusion Models
├── Multimodal Evaluation
└── Visual RL
```

### 带原文上下文阅读

阅读器把 PDF 和对话放在同一个工作面板里。PDF 中的选区会成为下一轮提问的一部分，Codex 会基于真实论文工作区和结构化上下文回答。

### 从 arXiv 发现论文

Discover 直接抓取 arXiv 元数据并本地缓存结果；需要更慢的 Codex 增强时，再对当前结果集进行处理。

常用 Discover 动作：

- 按日期范围、关键词、类别和本地相似度来源搜索。
- 下载并缓存 PDF 缩略图。
- 翻译标题。
- 生成中文总结、贡献说明、标签和链接。
- 把论文保存到指定文件夹。

### 让 AI 运行可检查

Codex 运行以本地文件记录呈现。会话文件保存在磁盘上，每轮交互都会保留 prompt 上下文、输出日志和本地工作区产物。

## 数据位置

默认支持目录是：

```text
~/Library/Application Support/PaperCodex
```

典型内容：

```text
PaperCodex/
├── store.sqlite
├── papers/
├── sessions/
├── arxiv-cache/
├── thumbnails/
└── migrations/
```

开发或实验时，可以用独立数据目录隔离状态：

```bash
PAPER_CODEX_SUPPORT_ROOT="$PWD/.papercodex-dev" swift run PaperCodexApp
```

## 开发

构建 debug app：

```bash
swift build
```

通过 SwiftPM 运行 app：

```bash
swift run PaperCodexApp
```

运行完整验证套件：

```bash
swift run PaperCodexCoreChecks
```

运行聚焦检查：

```bash
swift run PaperCodexCoreChecks ui-layout-source
swift run PaperCodexCoreChecks codex
swift run PaperCodexCoreChecks arxiv-feed
```

构建可打开的本地 app bundle：

```bash
scripts/build-app-bundle.sh
```

## 架构

Paper Codex 由 SwiftUI macOS 外壳和本地核心库组成。

```text
Sources/
├── PaperCodexApp/          # SwiftUI, PDFKit, app state, reader, library, Discover
├── PaperCodexCore/         # SQLite, indexing, arXiv, Codex runtime, parsing
├── PaperCodexCoreChecks/   # executable verification suite
└── CodeArxivFavoritesMigrator/
```

核心运行模块：

- `PaperRepository` 管理本地 SQLite 存储。
- `PDFIndexExtractor` 从带文本层的 PDF 中抽取页面文本、span 和 anchor。
- `SessionWorkspaceManager` 写入每个 session 的论文工作区。
- `CodexAgentRuntime` 调用 `codex exec` 和 `codex exec resume`。
- `LocalArxivClient` 与 `ArxivFeedCache` 支撑本地 arXiv 发现。
- `SimilarityRanker` 计算可选的本地相似度排序。

## 配置

多数用户侧配置都在设置页：

- app 语言和默认 Codex prompt 语言
- arXiv feed/cache 偏好
- Codex 增强模型、thinking effort 和并发数
- 可选 embedding provider 的 base URL、API key 和模型
- 阅读器对话 quick prompts
- 一次性缓存清理

app 也会读取：

```bash
PAPER_CODEX_SUPPORT_ROOT=/custom/support/root
PAPER_CODEX_APP_PATH=/custom/PaperCodex.app
PAPER_CODEX_BUILD_CONFIGURATION=release
PAPER_CODEX_BUNDLE_IDENTIFIER=local.paper-codex.app
PAPER_CODEX_CODESIGN_IDENTITY=-
```

## 当前限制

- 仅支持 macOS；当前 UI 依赖 SwiftUI 和 PDFKit。
- OCR/扫描版 PDF 属于后续重点；高质量锚定需要 PDF 有可用文本层。
- 云同步、账号和多设备状态位于后续规划。
- Codex 对话和增强处理需要本地 Codex CLI 可用。
- arXiv 请求可能被限速；有缓存时会优先使用本地元数据。

## 故障排查

### Codex 状态

确认 CLI 已安装并能被找到：

```bash
which codex
codex --version
codex exec --help
```

Paper Codex 会在 `PATH` 和常见安装位置中查找 `codex`，包括 Codex app bundle 和 Homebrew 路径。

### 重置本地开发数据

测试时建议使用独立支持目录：

```bash
rm -rf "$PWD/.papercodex-dev"
PAPER_CODEX_SUPPORT_ROOT="$PWD/.papercodex-dev" swift run PaperCodexApp
```

### 重新构建已安装 app

```bash
scripts/build-app-bundle.sh
open "$HOME/Applications/PaperCodex.app"
```

## 贡献

欢迎贡献。提交变更前请运行：

```bash
swift run PaperCodexCoreChecks
swift build
```

如果修改 UI 或 app bundle 层，也请运行：

```bash
scripts/build-app-bundle.sh
```

请保持项目边界清晰：本地论文库、本地 arXiv/cache 状态、可检查的 Codex 工作区，以及原生 macOS 阅读体验。

## 许可证

当前仓库尚未包含开源许可证文件。在把 Paper Codex 作为开源软件依赖或分发前，请先添加 `LICENSE` 文件。
