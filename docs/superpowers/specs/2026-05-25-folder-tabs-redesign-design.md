# Folder And Reader Tabs Redesign

## Goal

Make Paper Codex folders feel like natural document navigation and make Reader tabs read as stable paper tabs instead of generic buttons.

## Design

The Library sidebar treats folders as a tree. `All Papers` is the library root, each folder row has a stable chevron slot, folder icon, name, count, and hover-only row actions. Selecting a folder updates a breadcrumb bar in the main pane so the user can see the exact location and switch between `This folder` and `All levels` without looking back to the sidebar.

The Save to Library sheet uses the same mental model. It has a destination header with selected folder chips and a single tree picker. Inline creation remains in the tree, so a new folder appears under its parent immediately.

The Reader paper strip behaves like tabs. Active tabs have stronger fill and a top accent line, inactive tabs are compact, long titles truncate, and close controls stay visually quiet until useful. The session paper count stays as context, not as the dominant control.

## Verification

- Add `ui-layout-source` checks for the new folder, save destination, and tab components.
- Run `swift run PaperCodexCoreChecks`, `swift build`, and `scripts/build-app-bundle.sh`.
- Launch the installed app with an isolated `PAPER_CODEX_SUPPORT_ROOT` fixture and manually verify Library, Save to Library, Discover navigation, and Reader tabs.
