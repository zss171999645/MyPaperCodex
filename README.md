<p align="center">
  <img src="docs/assets/logo-rounded.png" alt="Paper Codex logo" width="132">
</p>

<h1 align="center">Paper Codex</h1>

<p align="center">
  A local-first macOS paper library with native PDF reading and Codex-backed research sessions.
</p>

<p align="center">
  <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://swift.org"><img alt="Swift" src="https://img.shields.io/badge/Swift-6.2-orange"></a>
  <img alt="Platform" src="https://img.shields.io/badge/macOS-14%2B-blue">
  <img alt="Status" src="https://img.shields.io/badge/status-active%20development-2ea44f">
  <img alt="License" src="https://img.shields.io/badge/license-not%20specified-lightgrey">
</p>

<p align="center">
  <a href="#intro-video">🎬 Intro Video</a> ·
  <a href="#screenshots">🖼️ Screenshots</a> ·
  <a href="#features">✨ Features</a> ·
  <a href="#installation">🚀 Installation</a> ·
  <a href="#quick-start">⚡ Quick Start</a> ·
  <a href="#development">🛠️ Development</a> ·
  <a href="#architecture">🧱 Architecture</a>
</p>

Paper Codex is a native macOS workspace for reading, organizing, and discussing academic papers. It keeps PDFs, folders, tags, notes, arXiv caches, thumbnails, reading sessions, and generated outputs on your machine, while using the Codex CLI when you want an AI research assistant inside a paper-specific workspace.

It is built for researchers who want the speed and feel of a local paper manager, plus grounded chat over the actual PDF, clickable citations back to source regions, and local arXiv discovery without a hosted product backend.

## Intro Video

Watch the detailed Remotion product walkthrough with animated UI focus moves: [docs/assets/videos/paper-codex-intro.mp4](docs/assets/videos/paper-codex-intro.mp4).

## Screenshots

<p align="center">
  <img src="docs/assets/screenshots/reader-chat.png" alt="Reader view with a PDF and Codex chat side by side">
  <br>
  <sub>Read a PDF, keep paper tabs open, and ask Codex questions with source-grounded context.</sub>
</p>

<table>
  <tr>
    <td width="50%">
      <img src="docs/assets/screenshots/library.png" alt="Paper library with folder tree, search, tags, and details">
    </td>
    <td width="50%">
      <img src="docs/assets/screenshots/discover.png" alt="arXiv Discover view with paper cards, thumbnails, tags, and local similarity scores">
    </td>
  </tr>
  <tr>
    <td><sub>Organize a local paper library with nested folders, tags, thumbnails, and paper details.</sub></td>
    <td><sub>Browse arXiv results with local caching, thumbnails, Chinese summaries, and save/open actions.</sub></td>
  </tr>
</table>

See the full visual tour in [docs/showcase.md](docs/showcase.md).

## Features

- 📚 **Local paper library** - import PDFs, organize them into nested folders, add tags, and keep durable metadata in SQLite.
- 📖 **Native PDF reader** - read with PDFKit, switch paper tabs, zoom smoothly, and preserve reader context.
- 🔎 **Source-grounded chat** - select text in the PDF, ask Codex, and keep citations tied to original page regions.
- 🧰 **Codex session workspaces** - each chat session writes a local workspace with PDFs, metadata, anchors, extracted text, and turn logs.
- 🎨 **Generated image support** - image-generation requests can surface directly in the chat, with in-app zoomable previews.
- 🔭 **Local arXiv Explore** - browse arXiv metadata directly, cache feeds/PDFs/thumbnails, and save papers into the local library.
- ✨ **Codex enrichment** - process Explore results for Chinese titles, summaries, contribution notes, tags, and useful links.
- 🧭 **Similarity ranking** - optionally rank arXiv results against local folders or tags using an OpenAI-compatible embedding provider.
- 🔒 **Local-first storage** - no Paper Codex account, cloud sync, or product API is required for the current version.

## Installation

### Requirements

- macOS 14 or newer
- Swift 6.2 toolchain
- Xcode command line tools
- [Codex CLI](https://github.com/openai/codex) for chat, enrichment, and image-generation workflows

Check the basic toolchain:

```bash
swift --version
codex --version
```

### Build the app bundle

```bash
git clone https://github.com/caopulan/PaperCodex.git
cd PaperCodex
scripts/build-app-bundle.sh
open "$HOME/Applications/PaperCodex.app"
```

By default, the build script installs the signed local app bundle at:

```text
~/Applications/PaperCodex.app
```

You can override the output path:

```bash
PAPER_CODEX_APP_PATH="$PWD/build/PaperCodex.app" scripts/build-app-bundle.sh
open "$PWD/build/PaperCodex.app"
```

## Quick Start

1. Open **Paper Codex**.
2. Import a PDF from the Library page, or open Discover and fetch recent arXiv papers.
3. Open a paper in the reader.
4. Select a sentence or paragraph in the PDF.
5. Ask Codex about the selected source in the right-hand chat panel.

Example prompts that work well:

```text
What is the central contribution of this paper? Please cite the source location.
```

```text
Compare this paper with the other papers in the current session. Which assumptions differ?
```

```text
Use imagegen to create a figure that explains this paper's training pipeline.
```

When image generation succeeds, Paper Codex copies the generated asset into the session workspace and renders it in the chat. Click the thumbnail to open an in-app zoomable preview instead of leaving the reader.

## Daily Workflow

### Organize a Local Library

Paper Codex stores saved PDFs and metadata locally. Use the Library sidebar as a folder tree, then narrow the paper list with search, folder scope, and reading actions.

```text
Library
├── All Papers
├── Diffusion Models
├── Multimodal Evaluation
└── Visual RL
```

### Read With Anchored Context

The reader keeps PDF reading and chat side by side. A source selection becomes part of the next message, so Codex can answer with context from the actual paper workspace rather than a loose paste.

### Discover From arXiv

Discover fetches arXiv metadata directly, caches results locally, and lets you process the current result set only when you need slower enrichment.

Useful Discover actions:

- Search by date range, keyword, category, and local similarity source.
- Download and cache PDF thumbnails.
- Translate titles.
- Generate Chinese summaries, contribution notes, tags, and links.
- Save papers into chosen folders.

### Keep AI Runs Inspectable

Codex runs are not hidden behind a remote service. Session files live on disk, and each turn keeps generated prompt context, output logs, and local workspace artifacts.

## Data Location

The default support directory is:

```text
~/Library/Application Support/PaperCodex
```

Typical contents:

```text
PaperCodex/
├── store.sqlite
├── papers/
├── sessions/
├── arxiv-cache/
├── thumbnails/
└── migrations/
```

For development or experiments, isolate app data with:

```bash
PAPER_CODEX_SUPPORT_ROOT="$PWD/.papercodex-dev" swift run PaperCodexApp
```

## Development

Build the debug app:

```bash
swift build
```

Run the app from SwiftPM:

```bash
swift run PaperCodexApp
```

Run the full verification suite:

```bash
swift run PaperCodexCoreChecks
```

Run focused checks:

```bash
swift run PaperCodexCoreChecks ui-layout-source
swift run PaperCodexCoreChecks codex
swift run PaperCodexCoreChecks arxiv-feed
```

Build the distributable local app bundle:

```bash
scripts/build-app-bundle.sh
```

## Architecture

Paper Codex is split into a SwiftUI macOS shell and a local core library.

```text
Sources/
├── PaperCodexApp/          # SwiftUI, PDFKit, app state, reader, library, Discover
├── PaperCodexCore/         # SQLite, indexing, arXiv, Codex runtime, parsing
├── PaperCodexCoreChecks/   # executable verification suite
└── CodeArxivFavoritesMigrator/
```

Core runtime pieces:

- `PaperRepository` manages the local SQLite store.
- `PDFIndexExtractor` extracts page text, spans, and anchors from text-layer PDFs.
- `SessionWorkspaceManager` writes per-session paper workspaces.
- `CodexAgentRuntime` invokes `codex exec` and `codex exec resume`.
- `LocalArxivClient` and `ArxivFeedCache` power local arXiv discovery.
- `SimilarityRanker` computes optional local similarity ordering.

## Configuration

Most user-facing configuration is available in the Settings page:

- app language and default Codex prompt language
- arXiv feed/cache preferences
- Codex enrichment model, thinking effort, and concurrency
- optional embedding provider base URL, API key, and model
- quick prompts for reader chat
- disposable cache cleanup

The app also respects:

```bash
PAPER_CODEX_SUPPORT_ROOT=/custom/support/root
PAPER_CODEX_OBSIDIAN_VAULT_ROOT="/Users/horizon/Documents/Obsidian-Main/世界模型"
PAPER_CODEX_CODEX_API_BASE_URL=https://your-codex-api.example/v1
PAPER_CODEX_CODEX_API_KEY=...
PAPER_CODEX_CODEX_API_MODEL=gpt-5.5
PAPER_CODEX_CODEX_API_ENDPOINT=chat_completions
PAPER_CODEX_APP_PATH=/custom/PaperCodex.app
PAPER_CODEX_BUILD_CONFIGURATION=release
PAPER_CODEX_BUNDLE_IDENTIFIER=local.paper-codex.app
PAPER_CODEX_CODESIGN_IDENTITY=-
```

### Obsidian catalog mode

This local fork can use the Obsidian vault as the source of truth for paper organization. When `PAPER_CODEX_OBSIDIAN_VAULT_ROOT` is set, or when the default vault path `~/Documents/Obsidian-Main/世界模型` exists, the Library list is loaded from `03-literature/papers/*.md` notes with `type: literature-note`.

In this mode Paper Codex does not own folders, tags, paper notes, watched folders, or arXiv saving. It reads Obsidian YAML, lazily caches PDFs under the app support directory for PDFKit reading, extracts temporary citation context for chat, and copies the corresponding Obsidian note into each session workspace as read-only context.

For this machine, run the Obsidian-backed reader with:

```bash
scripts/run-obsidian-reader.sh
```

### Codex API runtime

By default Paper Codex still uses the local Codex CLI. Set `PAPER_CODEX_CODEX_API_BASE_URL` to switch reader chat to an OpenAI-compatible HTTP API. `PAPER_CODEX_CODEX_API_ENDPOINT` supports `chat_completions` and `responses`; the default is `chat_completions`.

## Current Limitations

- macOS only; the UI currently depends on SwiftUI and PDFKit.
- OCR/scanned PDFs are not the primary target yet; PDFs need a usable text layer for strong anchors.
- Cloud sync, accounts, and multi-device state are intentionally out of scope for the current version.
- Codex-backed chat and enrichment require a working local Codex CLI setup.
- arXiv requests can be rate-limited; cached metadata is used when available.

## Troubleshooting

### Codex is unavailable

Confirm the CLI is installed and visible:

```bash
which codex
codex --version
codex exec --help
```

Paper Codex checks for `codex` in `PATH` and common install locations, including the Codex app bundle and Homebrew paths.

### Reset local development data

Use an isolated support root while testing:

```bash
rm -rf "$PWD/.papercodex-dev"
PAPER_CODEX_SUPPORT_ROOT="$PWD/.papercodex-dev" swift run PaperCodexApp
```

### Rebuild the installed app

```bash
scripts/build-app-bundle.sh
open "$HOME/Applications/PaperCodex.app"
```

## Contributing

Contributions are welcome. Before sending a change, run:

```bash
swift run PaperCodexCoreChecks
swift build
```

For UI or bundle-level changes, also run:

```bash
scripts/build-app-bundle.sh
```

Keep changes grounded in the local-first product boundary: local library, local arXiv/cache state, inspectable Codex workspaces, and native macOS reading.

## License

No open source license file is currently included in this repository. Add a `LICENSE` file before relying on Paper Codex as open source software.
