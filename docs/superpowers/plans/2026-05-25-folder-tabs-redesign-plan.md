# Folder And Reader Tabs Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign Paper Codex folder navigation, Save to Library destination picking, and Reader paper tabs into a simpler, more natural workflow.

**Architecture:** Keep the existing SwiftUI surfaces and AppModel APIs. Add focused view components inside the existing files, protected by `PaperCodexCoreChecks ui-layout-source`, so behavior remains stable while the UI improves.

**Tech Stack:** Swift 6.2, SwiftUI, existing PaperCodexCoreChecks, installed macOS app bundle at `/Users/chunqiu/Applications/PaperCodex.app`.

---

## Files

- Modify `Sources/PaperCodexCoreChecks/main.swift` for the RED guard.
- Modify `Sources/PaperCodexApp/LibraryView.swift` for folder tree rows and breadcrumb context.
- Modify `Sources/PaperCodexApp/SaveToLibrarySheet.swift` for destination chips and tree rows.
- Modify `Sources/PaperCodexApp/ReaderView.swift` for browser-style paper tabs.

## Tasks

- [x] Add failing `ui-layout-source` checks for `FolderBreadcrumbBar`, `LibraryRootFolderRow`, `SaveToLibraryDestinationHeader`, `SaveToLibraryFolderPathChip`, and `ReaderPaperTabChip`.
- [x] Implement Library root row, folder tree row polish, and breadcrumb/scope context.
- [x] Implement Save to Library destination header, selected path chips, and more natural folder rows.
- [x] Implement Reader paper tabs with active/inactive states, stable truncation, and quieter close controls.
- [x] Run `swift run PaperCodexCoreChecks`, `swift build`, `git diff --check`, and `scripts/build-app-bundle.sh`.
- [x] Launch the rebuilt installed app with an isolated fixture and verify Library, Save to Library, Discover, and Reader tabs.
- [x] Commit with a standard message.
