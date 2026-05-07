# Collection AI Table Workbench Redesign

Date: 2026-05-07
Status: approved direction, written spec for user review
Supersedes: `2026-05-07-collection-advanced-table-design.md`

## Goal

Collections should become an AI analysis table workbench, not a generic spreadsheet clone and not a chat window placed next to a table.

The selected direction is **C1-B: docked, selection-first AI panel**. The right panel stays visible because AI is a core part of the product, but the panel follows the selected table object by default. When the user selects a cell, row, or column, the panel shows relevant context, evidence, field rules, and AI actions for that selection. Long chat and batch Codex runs remain available, but they are not the default visual state.

## Current Problem

The current Collections UI has many useful controls, but it feels hard to use because the layout is panel-heavy and table-light:

- The right chat panel permanently consumes width even when the user is editing cells.
- The field inspector is a second competing side surface inside the table workbench.
- The table is visually interrupted by too many stacked controls: header, toolbar, tabs, formula bar, grid, inspector, status bar, and chat.
- AI is present, but its relationship to the selected cell or field is not clear enough.
- The screen reads more like a collection of features than a coherent table product.

The redesign should preserve table editability, sorting, filtering, column visibility, validation, and AI workflows, but reorganize them around a clear table-plus-context model.

## Product Principles

- The table remains the primary workspace.
- AI remains visible, but it is contextual to the selected cell, row, or field.
- The right panel is one integrated dock, not separate chat and inspector surfaces.
- The default right-panel tab is selection context, not chat history.
- Field settings belong in the same dock, under a `Field` tab.
- Long conversation belongs in a `Chat` tab.
- Batch fill, validation, and Codex jobs belong in a `Runs` tab.
- The table should keep as much width and vertical density as possible.
- Existing data model and persistence behavior should be reused. This is a UI re-architecture, not a storage rewrite.

## Target Layout

The Collections route keeps the left app sidebar and selected collection list. The selected collection content becomes a two-pane workbench:

1. Main table pane.
2. Right docked AI/context panel.

### Main Table Pane

The main pane should contain:

- A compact top toolbar with collection title, add field, add papers, filter, sort, columns, validate, and panel collapse.
- View tabs for `All Papers`, `Invalid Values`, and `Missing Required`.
- A compact formula/current-cell bar.
- The grid.
- A thin status bar.

The main pane should not contain a separate field inspector. It should not contain the chat transcript.

### Right Docked Panel

The right panel should be fixed-width but collapsible. It should have tabs:

- `Selection`
- `Field`
- `Chat`
- `Runs`

The panel width should be large enough to be useful for AI context, but not so large that normal tables feel cramped. The target default width is approximately 320-360 px, with a collapsed icon rail state.

## Right Panel Tabs

### Selection Tab

This is the default tab. It follows the selected table object:

- If a cell is selected:
  - show cell coordinate.
  - show row paper title.
  - show field title and type.
  - show current value.
  - show validation issues for the cell.
  - show evidence/context snippets when available.
  - show selection-scoped AI actions.
- If a row is selected:
  - show paper identity.
  - show row completion and validation summary.
  - show actions for summarizing, classifying, or filling fields for that row.
- If a column/header is selected:
  - show field summary.
  - show validation count for the field.
  - show actions for filling or validating the field across rows.
- If nothing is selected:
  - show collection summary and next useful actions.

Selection actions should be concrete and table-native:

- Explain this cell.
- Cite supporting evidence.
- Fill this field for selected rows.
- Validate this column.
- Suggest allowed values.
- Summarize selected papers.

### Field Tab

The existing Field Inspector moves into this tab.

It should show and edit:

- Field title.
- Field ID as read-only technical text.
- Type as display-only for existing fields.
- Width.
- Visible state.
- Required state.
- Allowed values.
- Description.
- Field-level validation summary.

The last visible field cannot be hidden from this tab. The same guard should apply everywhere fields can be hidden.

### Chat Tab

This tab contains the longer collection conversation.

Chat should still be able to edit the JSON-backed collection, but it should be visually secondary to the selection context. When possible, chat should inherit selection context:

- selected cell.
- selected rows.
- selected field.
- active view/filter.

The composer should make it clear when a prompt is scoped to the selection versus the whole collection.

### Runs Tab

This tab contains batch AI activity:

- active Codex run status.
- cancel controls.
- pending or recent table actions.
- validation/fill jobs.
- run result summary.

It should replace ad hoc status messages scattered through the table surface.

## Table Interaction Requirements

The existing table capabilities must remain:

- cells are editable, including metadata columns.
- filter rows.
- sort by visible or available fields.
- hide and restore fields.
- add fields.
- add papers.
- open a paper from the title cell.
- select rows for paper chat.
- select a cell for formula bar editing.
- validation issues show in the grid.
- keyboard navigation continues to work.

The redesign should reduce visible chrome rather than add more. Controls that are not needed constantly should move into:

- column header menus.
- right panel tabs.
- compact toolbar menus.
- contextual action groups.

## AI Context Model

The UI should maintain a current table selection model:

- selected cell.
- selected rows.
- selected field.
- active collection.
- active view mode.

The right panel derives its content from this selection model.

The collection prompt should include selection context when the user acts from the panel or chat:

- selected row IDs.
- selected field ID.
- selected cell coordinate and value.
- active validation issues when relevant.

The prompt must remain bounded. Large validation or row summaries should be grouped and sampled, not dumped in full.

## Data And Persistence

No new database or backend is needed for this redesign.

Reuse:

- `PaperCollectionDocument`
- `PaperCollectionColumn`
- `PaperCollectionValidationIssue`
- `AppModel` collection update methods
- JSON-backed collection store

If new view state is needed, it should initially remain local UI state unless persistence is clearly useful.

Persisted collection data should remain limited to actual table data and field settings:

- rows.
- columns.
- field titles.
- widths.
- hidden state.
- required state.
- allowed values.
- descriptions.

## Out Of Scope

- Full Excel-like formula engine.
- Pivot tables.
- Charts.
- Multi-user collaboration.
- Full saved-view system beyond existing view tabs.
- Separate table database backend.
- Drag fill handles.
- Rich cell formatting.
- Virtualized grid rewrite unless performance requires it.

## Implementation Boundaries

The implementation should be staged to avoid another broad UI pile-up:

1. Recompose the layout:
   - remove the separate chat panel from `contentPane`.
   - keep one main table pane and one integrated right dock.
   - move Field Inspector into the right dock.
2. Build the integrated right dock:
   - tab state.
   - `Selection` tab.
   - `Field` tab.
   - `Chat` tab using the existing collection chat messages/composer.
   - `Runs` tab using existing active-run state.
3. Slim the table chrome:
   - compact toolbar.
   - compact tabs.
   - compact formula bar.
   - status bar remains thin.
4. Wire selection-scoped actions:
   - panel reflects selected cell/field/row.
   - chat and AI actions receive bounded selection context.
5. Verify table behavior:
   - cell editing.
   - validation.
   - field settings.
   - sorting/filtering/hiding.
   - collection chat.
   - active run cancel.

## Verification

Required automated checks:

- `swift run PaperCodexCoreChecks collections collection-sources ui-layout-source`
- `swift build`
- `git diff --check`
- `scripts/build-app-bundle.sh`

Required manual verification:

- Open Collections in `/Users/chunqiu/Applications/PaperCodex.app`.
- Confirm the screen has one main table pane and one integrated right dock.
- Confirm the right dock defaults to selection context.
- Select a cell and confirm the right panel updates.
- Switch to the Field tab and edit field settings.
- Switch to Chat and confirm collection chat still works.
- Switch to Runs during or after an active Codex run.
- Confirm metadata and custom cells remain editable.
- Confirm hiding the last visible field is blocked.
- Confirm validation issues still show in the grid and panel.

## Completion Criteria

The redesign is complete when:

- Collections reads as an AI table workbench.
- The table remains the visual center.
- The right dock is useful by default because it follows selection.
- Field Inspector no longer competes as a separate panel.
- Chat remains available but is not the default right-panel mode.
- Batch AI run state has a clear home.
- Existing table editing, validation, filtering, sorting, field visibility, and collection chat behavior still work.
- The installed app is rebuilt and relaunched.
- Changes are committed with standard messages.
