# Paper Codex App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first usable macOS Paper Codex App with local paper management, PDF reading, source anchors, citation markers, and Codex session workspace orchestration.

**Architecture:** Use a Swift Package with a `PaperCodexCore` library and a `PaperCodexApp` SwiftUI executable. Core owns models, SQLite persistence, prompt building, citation parsing, PDF indexing, and Codex workspace/process orchestration; the App target owns SwiftUI/PDFKit views and user interaction. Tests use real Swift code, temporary SQLite databases, generated fixture PDFs, and real filesystem workspaces.

**Tech Stack:** Swift 6.2, Swift Package Manager, SwiftUI, PDFKit, SQLite3, XCTest/Swift Testing-compatible `XCTest`, Codex CLI through child processes.

---

## File Structure

- `Package.swift`: package manifest for app, core library, and tests.
- `Sources/PaperCodexCore/Models.swift`: value models for papers, categories, tags, spans, anchors, sessions, citations, and chat messages.
- `Sources/PaperCodexCore/SQLiteDatabase.swift`: minimal SQLite wrapper with explicit errors and prepared statements.
- `Sources/PaperCodexCore/PaperRepository.swift`: schema migration and CRUD for papers, categories, tags, spans, anchors, sessions, and chat messages.
- `Sources/PaperCodexCore/CitationParser.swift`: parse `[[cite:...]]` markers into structured citations.
- `Sources/PaperCodexCore/PromptBuilder.swift`: build Codex prompts with user text, selected anchors, relevant spans, paper metadata, and citation contract.
- `Sources/PaperCodexCore/SessionWorkspaceManager.swift`: create and update per-session Codex workspaces.
- `Sources/PaperCodexCore/CodexCLI.swift`: verify Codex availability and run/resume sessions through `codex exec`.
- `Sources/PaperCodexCore/PDFIndexExtractor.swift`: extract text-layer page and span records from real PDFs.
- `Sources/PaperCodexApp/PaperCodexApp.swift`: app entry point.
- `Sources/PaperCodexApp/AppModel.swift`: observable app state and orchestration.
- `Sources/PaperCodexApp/LibraryView.swift`: two-column paper library page.
- `Sources/PaperCodexApp/ReaderView.swift`: left PDF reader and right chat page.
- `Sources/PaperCodexApp/PDFKitView.swift`: `NSViewRepresentable` wrapper for PDFKit selection and highlights.
- `Sources/PaperCodexApp/ChatView.swift`: session dropdown, New button, messages, and composer.
- `Tests/PaperCodexCoreTests/*.swift`: real unit/integration tests for core behavior.

## Task 1: Package Skeleton and Models

**Files:**
- Create: `Package.swift`
- Create: `Sources/PaperCodexCore/Models.swift`
- Create: `Tests/PaperCodexCoreTests/ModelsTests.swift`

- [ ] **Step 1: Write failing model tests**

Create `Tests/PaperCodexCoreTests/ModelsTests.swift` with tests that construct `Paper`, `Span`, `Anchor`, and `PaperSession`, verify stable ID strings, and verify Codable round trips.

Run: `swift test --filter ModelsTests`

Expected: FAIL because the package and models do not exist.

- [ ] **Step 2: Create package and model implementation**

Create the Swift package with a core library, app executable, and test target. Implement immutable value models with explicit fields from the design spec.

- [ ] **Step 3: Run model tests**

Run: `swift test --filter ModelsTests`

Expected: PASS with all model tests passing.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/PaperCodexCore/Models.swift Tests/PaperCodexCoreTests/ModelsTests.swift
git commit -m "feat: add paper codex core models"
```

## Task 2: SQLite Persistence

**Files:**
- Create: `Sources/PaperCodexCore/SQLiteDatabase.swift`
- Create: `Sources/PaperCodexCore/PaperRepository.swift`
- Create: `Tests/PaperCodexCoreTests/PaperRepositoryTests.swift`

- [ ] **Step 1: Write failing repository tests**

Create tests that open a temporary SQLite database, migrate schema, insert categories, tags, papers, paper-tag links, paper-category links, spans, anchors, sessions, and chat messages, then verify round trips.

Run: `swift test --filter PaperRepositoryTests`

Expected: FAIL because repository types do not exist.

- [ ] **Step 2: Implement SQLite wrapper and repository**

Implement schema migration with tables for papers, categories, tags, paper_categories, paper_tags, spans, anchors, sessions, session_papers, and chat_messages. Store bbox arrays and string arrays as JSON text.

- [ ] **Step 3: Run repository tests**

Run: `swift test --filter PaperRepositoryTests`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/PaperCodexCore/SQLiteDatabase.swift Sources/PaperCodexCore/PaperRepository.swift Tests/PaperCodexCoreTests/PaperRepositoryTests.swift
git commit -m "feat: add sqlite paper repository"
```

## Task 3: Citations, Prompts, and Session Workspaces

**Files:**
- Create: `Sources/PaperCodexCore/CitationParser.swift`
- Create: `Sources/PaperCodexCore/PromptBuilder.swift`
- Create: `Sources/PaperCodexCore/SessionWorkspaceManager.swift`
- Create: `Tests/PaperCodexCoreTests/CitationParserTests.swift`
- Create: `Tests/PaperCodexCoreTests/PromptBuilderTests.swift`
- Create: `Tests/PaperCodexCoreTests/SessionWorkspaceManagerTests.swift`

- [ ] **Step 1: Write failing citation parser tests**

Verify parsing `[[cite:paper:abc:p5:b17]]` and `[[cite:paper:abc:p5:a20260427003115]]`, preserving plain response text, and reporting broken malformed markers.

Run: `swift test --filter CitationParserTests`

Expected: FAIL because parser does not exist.

- [ ] **Step 2: Implement citation parser**

Implement deterministic marker parsing without hiding malformed citation markers.

- [ ] **Step 3: Write failing prompt builder tests**

Verify prompts include user text, selected source anchor blocks, relevant spans, paper metadata, workspace path guidance, and the citation contract.

Run: `swift test --filter PromptBuilderTests`

Expected: FAIL because prompt builder does not exist.

- [ ] **Step 4: Implement prompt builder**

Build a single prompt string for Codex from typed request data.

- [ ] **Step 5: Write failing workspace tests**

Verify a session workspace creates `session.json`, `prompt_contract.md`, `papers/{paper_id}/metadata.json`, `spans.jsonl`, `anchors.jsonl`, and `turns/`.

Run: `swift test --filter SessionWorkspaceManagerTests`

Expected: FAIL because workspace manager does not exist.

- [ ] **Step 6: Implement session workspace manager**

Create filesystem output from real model values and fail loudly when files cannot be written.

- [ ] **Step 7: Run task tests**

Run: `swift test --filter CitationParserTests && swift test --filter PromptBuilderTests && swift test --filter SessionWorkspaceManagerTests`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/PaperCodexCore/CitationParser.swift Sources/PaperCodexCore/PromptBuilder.swift Sources/PaperCodexCore/SessionWorkspaceManager.swift Tests/PaperCodexCoreTests/CitationParserTests.swift Tests/PaperCodexCoreTests/PromptBuilderTests.swift Tests/PaperCodexCoreTests/SessionWorkspaceManagerTests.swift
git commit -m "feat: add codex prompt and citation core"
```

## Task 4: PDF Text-Layer Indexing

**Files:**
- Create: `Sources/PaperCodexCore/PDFIndexExtractor.swift`
- Create: `Tests/PaperCodexCoreTests/PDFIndexExtractorTests.swift`

- [ ] **Step 1: Write failing PDF extractor tests**

Generate a real fixture PDF with selectable text, run extraction, and verify page text plus at least one span with page number, text, bbox, and confidence.

Run: `swift test --filter PDFIndexExtractorTests`

Expected: FAIL because extractor does not exist.

- [ ] **Step 2: Implement PDF text-layer extraction**

Use PDFKit to read `PDFDocument`, reject PDFs with no extractable text, and create page/span records with bbox values from page selections where available.

- [ ] **Step 3: Run PDF extractor tests**

Run: `swift test --filter PDFIndexExtractorTests`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/PaperCodexCore/PDFIndexExtractor.swift Tests/PaperCodexCoreTests/PDFIndexExtractorTests.swift
git commit -m "feat: add pdf text layer indexing"
```

## Task 5: Codex CLI Boundary

**Files:**
- Create: `Sources/PaperCodexCore/CodexCLI.swift`
- Create: `Tests/PaperCodexCoreTests/CodexCLITests.swift`

- [ ] **Step 1: Write failing CLI tests**

Verify `CodexCLI` detects the local `codex` binary, builds `codex exec` and `codex exec resume` arguments correctly, and reports a clear setup error when the binary path is missing.

Run: `swift test --filter CodexCLITests`

Expected: FAIL because CLI wrapper does not exist.

- [ ] **Step 2: Implement CLI wrapper**

Implement process invocation with explicit stdout/stderr capture and no broad catch-all behavior.

- [ ] **Step 3: Run CLI tests**

Run: `swift test --filter CodexCLITests`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/PaperCodexCore/CodexCLI.swift Tests/PaperCodexCoreTests/CodexCLITests.swift
git commit -m "feat: add codex cli boundary"
```

## Task 6: macOS App UI

**Files:**
- Create: `Sources/PaperCodexApp/PaperCodexApp.swift`
- Create: `Sources/PaperCodexApp/AppModel.swift`
- Create: `Sources/PaperCodexApp/LibraryView.swift`
- Create: `Sources/PaperCodexApp/ReaderView.swift`
- Create: `Sources/PaperCodexApp/PDFKitView.swift`
- Create: `Sources/PaperCodexApp/ChatView.swift`

- [ ] **Step 1: Implement App shell from verified core APIs**

Create a native SwiftUI app with a clean two-page layout: library page with category tree and paper list, reader page with left PDFKit area and right chat panel.

- [ ] **Step 2: Build the app**

Run: `swift build`

Expected: PASS.

- [ ] **Step 3: Launch and visually inspect**

Run: `swift run PaperCodexApp`

Use Computer Use or the macOS UI surface to inspect that the library page, reader page, PDF area, and chat panel render cleanly and that the session dropdown plus `New` button are visible.

- [ ] **Step 4: Commit**

```bash
git add Sources/PaperCodexApp
git commit -m "feat: add macos paper codex app shell"
```

## Task 7: End-to-End Verification

**Files:**
- Modify as needed based on verification findings.

- [ ] **Step 1: Run full tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 2: Run full build**

Run: `swift build`

Expected: PASS.

- [ ] **Step 3: Run app and inspect UI**

Run: `swift run PaperCodexApp`

Use Computer Use to inspect the app window and verify the two-page structure, visual polish, and no obvious overlap or clipping.

- [ ] **Step 4: Commit verification fixes**

If fixes were needed, commit them with a standard message that describes the behavior changed.
