# CodeArXiv Discover Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the CodeArXiv-backed Discover, Library, Settings, storage, and quick prompt integration.

**Architecture:** CodeArXiv remains the authoritative server for arXiv feed enrichment, favorite folders, similarity vectors, and tag filters. Paper Codex consumes that API, caches feed/assets/PDFs locally, and owns the macOS reader/library/chat UI.

**Tech Stack:** Flask/pytest/SQLite on CodeArXiv; Swift 6.2, SwiftUI, PDFKit, SQLite, and PaperCodexCoreChecks locally.

---

### Task 1: CodeArXiv User API

**Files:**
- Modify: `/home/sariel/workspace/CodeArXiv/app/feed.py`
- Modify: `/home/sariel/workspace/CodeArXiv/app/security.py`
- Modify: `/home/sariel/workspace/CodeArXiv/tests/test_api_feed.py`

- [x] Add coverage for `/api/v1/users/caopu/state`.
- [x] Add coverage for `/api/v1/feed/<date>?username=caopu` returning similarity, filter group, favorite flags, filters, groups, and favorites.
- [x] Add coverage for `/api/v1/users/<username>/filters` updates.
- [x] Implement user lookup, filter serialization, favorite export, API feed grouping, and Bearer-token API writes without web CSRF.
- [x] Run `.venv/bin/python -m py_compile app/feed.py app/security.py tests/test_api_feed.py`.
- [x] Run a manual Flask test client smoke for user state, filters update, token rejection, and filtered feed ordering. Remote `.venv` currently has no `pytest` module, so pytest could not be executed.
- [ ] Commit on the remote repo with `feat: expose codearxiv user feed state`.

### Task 2: Local Core Data

**Files:**
- Modify: `Sources/PaperCodexCore/ArxivFeed.swift`
- Modify: `Sources/PaperCodexCore/Models.swift`
- Modify: `Sources/PaperCodexCore/PaperRepository.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [x] Add checks for CodeArXiv user-state decoding, feed grouping fields, quick prompt model round-trip, and repository metadata links.
- [x] Implement Codable models and persistence helpers.
- [x] Run `swift run PaperCodexCoreChecks arxiv-feed`.
- [ ] Commit locally with `feat: add codearxiv feed state models`.

### Task 3: App State And Import Flow

**Files:**
- Modify: `Sources/PaperCodexApp/AppModel.swift`
- Create: `Sources/PaperCodexApp/PDFThumbnailCache.swift`

- [x] Add app state for username, filters, favorite sync, per-paper downloads, quick prompts, split widths, and PDF thumbnails.
- [x] Implement CodeArXiv user-state sync and caopu favorite migration into saved papers/categories/tags.
- [x] Implement per-paper Open progress/spinner and cache-to-library promotion.
- [x] Implement five-page PDF thumbnail rendering/cache with PDFKit.
- [x] Run `swift build` and `swift run PaperCodexCoreChecks`.

### Task 4: UI

**Files:**
- Modify: `Sources/PaperCodexApp/PaperCodexApp.swift`
- Modify: `Sources/PaperCodexApp/DiscoverView.swift`
- Modify: `Sources/PaperCodexApp/LibraryView.swift`
- Modify: `Sources/PaperCodexApp/SettingsView.swift`
- Modify: `Sources/PaperCodexApp/ChatView.swift`

- [x] Create sidebar/nav rows with stable width and full-row hit targets.
- [x] Replace Discover adaptive grid with a stable CodeArXiv-like card flow and no overlapping text/image regions.
- [x] Add Settings controls for CodeArXiv username/token, filters, similarity folders, quick prompts, storage, cache, and favorite sync.
- [x] Add Library thumbnail strips and persisted split width.
- [x] Replace the chat status area with quick prompt dropdown plus compact Codex status/model controls.
- [x] Build, install the app bundle, and test with Computer Use.
- [ ] Commit locally with `feat: complete codearxiv discover library workflow`.

### Task 5: Verification

**Files:**
- Modify only if a verification failure reveals a real product gap.

- [x] Run remote py_compile and manual Flask client smoke against CodeArXiv. Pytest is blocked by missing `pytest` in the remote `.venv`.
- [x] Run local `swift build`, `swift run PaperCodexCoreChecks`, `swift run PaperCodexCoreChecks arxiv-feed`, and `swift run PaperCodexCoreChecks arxiv-live`.
- [x] Use Computer Use for Discover layout, navigation hit area, Settings stability, Open spinner/progress, Library thumbnails, quick prompt dropdown, and save/cache-to-library migration controls. Direct splitter drag is not available in the current Computer Use tool surface; persistence is covered by implementation and route/relaunch observation.
- [x] Restart remote tmux service after server code changed.
- [ ] Delete the heartbeat automation only after every requested behavior is verified.
