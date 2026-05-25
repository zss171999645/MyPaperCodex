# Paper Codex Architecture Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor Paper Codex into clearer feature and service boundaries while preserving current behavior through code checks and real app usage tests.

**Architecture:** Keep the current macOS SwiftUI shell, SQLite repository, PDFKit reader, Codex CLI integration, and local-first data model. Shrink `AppModel` into a coordinator by extracting feature services/stores one slice at a time, beginning with category assignment and then moving Discover, Reader/session, and Agent runtime orchestration behind explicit interfaces.

**Tech Stack:** Swift 6.2, Swift Package Manager, SwiftUI, PDFKit, SQLite3, local `PaperCodexCoreChecks`, built app bundle at `/Users/chunqiu/Applications/PaperCodex.app`, and macOS app-level usage testing.

---

## File Structure

- `Sources/PaperCodexCore/LibraryCategoryAssignment.swift`: category assignment service for existing category IDs, flat new names, nested new category requests, deterministic duplicate handling, and hierarchy validation.
- `Sources/PaperCodexApp/SaveToLibrarySheet.swift`: keep the UI request shape but alias it to the Core request type.
- `Sources/PaperCodexApp/AppModel.swift`: remove category assignment implementation details and delegate to `LibraryCategoryAssigner`.
- `Sources/PaperCodexCoreChecks/main.swift`: add real SQLite-backed checks for category assignment behavior.
- `docs/superpowers/plans/2026-05-25-paper-codex-architecture-refactor.md`: this running implementation plan.

## Validation Baseline

- `swift build`
- `swift run PaperCodexCoreChecks`
- `scripts/build-app-bundle.sh`
- Open `/Users/chunqiu/Applications/PaperCodex.app`
- Real usage smoke test:
  - open Library
  - create/select nested folders through Save to Library
  - open a saved paper
  - open Discover
  - open or save an arXiv paper
  - open Reader and start a chat session without losing PDF/session state

## Task 1: Extract Library Category Assignment

**Files:**
- Create: `Sources/PaperCodexCore/LibraryCategoryAssignment.swift`
- Modify: `Sources/PaperCodexApp/SaveToLibrarySheet.swift`
- Modify: `Sources/PaperCodexApp/AppModel.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [x] **Step 1: Write the failing check**

Add `runLibraryCategoryAssignmentChecks()` to `PaperCodexCoreChecks` using a temporary SQLite database and a real `PaperRepository`. The check must prove:

- existing category IDs are assigned only when valid
- duplicate flat new names create one category
- nested new category requests preserve parent-child relationships
- cyclic new category requests throw `LibraryCategoryAssignmentError.invalidCategoryHierarchy`

- [x] **Step 2: Run the check and verify RED**

Run:

```bash
swift run PaperCodexCoreChecks library-category-assignment
```

Expected: compilation fails because `LibraryCategoryAssigner` and `LibraryCategoryRequest` do not exist yet.

- [x] **Step 3: Implement Core service**

Create `LibraryCategoryAssignment.swift` with:

- `LibraryCategoryRequest`
- `LibraryCategoryAssignmentError`
- `LibraryCategoryAssigner`
- deterministic normalization helpers
- injected ID factory for tests

- [x] **Step 4: Wire AppModel to the service**

Replace `AppModel.assignCategories(...)`, `ensureCategory(...)`, and request normalization helpers with a small wrapper that calls `LibraryCategoryAssigner.assign(...)` and updates similarity defaults for newly created categories.

- [x] **Step 5: Run focused and full checks**

Run:

```bash
swift run PaperCodexCoreChecks library-category-assignment
swift run PaperCodexCoreChecks
swift build
```

Expected: all commands exit 0.

## Task 2: Split App State Stores

**Files:**
- Create: `Sources/PaperCodexApp/LibraryFeatureStore.swift`
- Create: `Sources/PaperCodexApp/ReaderFeatureStore.swift`
- Create: `Sources/PaperCodexApp/DiscoverFeatureStore.swift`
- Modify: `Sources/PaperCodexApp/AppModel.swift`

- [x] Extract pure Library state and commands first.
- [x] Extract Reader/session state after Library still passes real app smoke tests.
- [x] Extract Discover state last because it has the highest async/concurrency risk.
- [x] Keep `AppModel` as the single SwiftUI environment object until the feature stores are stable.

## Task 3: Extract Agent Runtime Boundary

**Files:**
- Create: `Sources/PaperCodexCore/AgentRuntime.swift`
- Create: `Sources/PaperCodexCore/CodexAgentRuntime.swift`
- Modify: `Sources/PaperCodexApp/AppModel.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [x] Define a runtime protocol that preserves streaming events, cancellation, token usage, thread resume, generated image discovery, and workspace output paths.
- [x] Move Codex CLI orchestration behind `CodexAgentRuntime`.
- [x] Keep image generation capability routing intact.

## Task 4: UI Simplification Pass

**Files:**
- Modify: `Sources/PaperCodexApp/LibraryView.swift`
- Modify: `Sources/PaperCodexApp/DiscoverView.swift`
- Modify: `Sources/PaperCodexApp/ReaderView.swift`
- Modify: `Sources/PaperCodexApp/ChatView.swift`

- [x] Reduce nested controls and repeated component definitions.
- [x] Make common toolbar/action button components reusable.
- [x] Preserve dense, work-focused macOS UI rather than adding marketing-style surfaces.
- [x] Verify text fit and interaction states in the built app.

## Task 5: Real App Verification

**Files:**
- Modify if needed: `scripts/build-app-bundle.sh`

- [x] Build and install the app bundle.
- [x] Relaunch the app.
- [x] Use the real Library, Discover, Reader, and Chat flows.
- [x] Confirm no behavior regression from the current baseline.
- [x] Commit with a standard message after verification.
