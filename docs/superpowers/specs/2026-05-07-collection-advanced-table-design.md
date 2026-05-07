# Collection Advanced Table Design

Date: 2026-05-07
Status: superseded by `2026-05-07-collection-ai-table-workbench-redesign.md`

## Goal

Collections should become a credible local spreadsheet-style table product inside Paper Codex. The current surface exposes useful controls, but it still feels like a row list with buttons attached to it. This redesign should make Collections feel like a serious data grid for organizing papers: editable cells, clear selection state, field configuration, validation feedback, view controls, and a table-first layout.

The selected product direction is A3: an advanced table system. It should lean toward Numbers/Airtable-style table work, not a paper-card research matrix and not a Codex chat-first workflow.

## Product Principles

- The table is the primary surface. Chat and JSON access are supporting tools, not the visual center of this screen.
- Metadata columns are editable user-facing cells. Stable internal IDs can remain protected, but the UI must not present metadata as locked.
- Table operations should be discoverable from expected table places: top toolbar, view tabs, column headers, selected-cell formula bar, field inspector, and status bar.
- Errors should be visible. Invalid values, empty required cells, and type mismatches should be shown in the grid and summarized in the status bar.
- The first implementation should feel complete for local collection editing without pretending to be a full Excel engine.

## In Scope

- A redesigned Collections content area with:
  - collection title and compact table controls.
  - built-in view tabs: `All Papers`, `Invalid Values`, and `Missing Required`.
  - toolbar controls for adding rows/papers, adding fields, filtering, sorting, choosing visible fields, and validation.
  - formula/current-cell bar showing the active cell reference, field name, field type, and draft value.
  - spreadsheet grid with row index column, frozen paper title column, editable cells, selected cell/row state, and column header menus.
  - right-side field inspector for the selected field.
  - bottom status bar with row count, visible field count, selection summary, and validation summary.
- A field model extension that supports user-facing field settings:
  - display title.
  - value kind.
  - width.
  - hidden state.
  - required state.
  - allowed values for select/badge-like fields.
  - optional field description.
- Validation for collection cells:
  - number fields should flag values that cannot parse as numbers.
  - year fields should flag non-year values.
  - date fields should flag non-date values.
  - select/badge fields with allowed values should flag values outside the configured set.
  - required fields should flag empty values where required.
- Visual feedback:
  - invalid cells get a visible error treatment.
  - selected cell gets a clear focus treatment.
  - the status bar summarizes validation issues.
  - the inspector shows field rules and selected-field issue counts.
- Keyboard and interaction basics:
  - click to select a cell.
  - double click or focus to edit.
  - Return commits the draft.
  - Escape cancels the draft.
  - Tab moves to the next visible cell after committing.
  - arrow keys move the selected cell when not editing.
  - select-all displayed rows from the row-index header.
- Source compatibility:
  - existing collection JSON files must decode.
  - newly saved collection JSON should include the new field settings with safe defaults.
  - Codex editing contract should describe the new field settings and validation expectations.

## Out Of Scope For This Iteration

- Formula computation engine.
- Cross-cell references.
- Infinite virtualized grid engine.
- Multi-user collaboration.
- Pivot tables or charts.
- Remote sync.
- Full spreadsheet import/export.
- Cell merge, rich text, or per-cell formatting beyond type-aware display and validation.
- A separate database backend for Collections.

## User Experience

### Overall Layout

The Collections route keeps the existing left sidebar for app navigation and collection switching. The selected collection content becomes a table workbench:

1. Top header row:
   - collection title.
   - compact metadata such as row count and collection JSON path.
   - rename, reveal JSON, and delete actions.
2. Table toolbar:
   - add papers.
   - add field.
   - filter.
   - sort.
   - fields menu.
   - validation menu or toggle.
   - chat selected/all papers remains available, but visually secondary.
3. View tabs:
   - `All Papers` as the default.
   - `Invalid` or `Needs Review` view that filters rows with validation issues.
   - `Missing Required` view that filters rows with empty required fields.
4. Formula/current-cell bar:
   - shows current cell coordinate, field title, field type, and current draft/value.
   - editing here updates the selected cell.
5. Grid:
   - row index column on the left.
   - paper title column visually frozen.
   - visible fields only.
   - column headers contain sort, hide, field settings, and validation indicators.
6. Field inspector:
   - shows selected field details.
   - allows title, type display, width, hidden state, required state, allowed values, and description.
   - shows validation issue count for the field.
7. Status bar:
   - row count after filters.
   - total row count.
   - visible field count.
   - selected cell or selected row count.
   - validation summary.

### Empty And Edge States

- If there is no selected collection, keep a clear empty state with create collection action.
- If all columns are hidden, the app should force at least one visible column or restore the paper title column.
- If a filter returns no rows, the grid area should show a table-shaped empty state with clear filter controls.
- If there are validation errors, the status bar should show the count and the invalid view should be available.

### Editing Behavior

Each visible cell has a persistent value string in collection JSON. Editing should commit to `collection.rows[].values[columnID]` through the existing collection save path.

The selected cell state should be separate from editing state:

- selected cell: highlighted but not actively editing.
- editing cell: text field active and keyboard input goes into the draft.
- committed cell: saved to JSON and validation recalculates.

Metadata fields and custom fields both use this path. The `isLocked` field can remain as internal schema protection for column IDs, but it should not block user cell editing.

### Field Inspector

The inspector should be driven by the selected column:

- Field name/title.
- Field ID as read-only technical text.
- Type.
- Width.
- Visible/hidden state.
- Required toggle.
- Allowed values editor for `badge`/select-like fields.
- Description text.
- Issue summary.

Title, width, visible/hidden state, required state, allowed values, and description should save back to collection JSON. Field ID is read-only. Existing field type is display-only for this iteration; new fields choose their type at creation time.

## Data Model

Extend `PaperCollectionColumn` with optional settings that decode safely from existing JSON:

- `isHidden: Bool`
- `isRequired: Bool`
- `allowedValues: [String]`
- `description: String`

Existing documents without these keys should decode as:

- `isHidden = false`
- `isRequired = false`
- `allowedValues = []`
- `description = ""`

The current `isLocked` property remains available for schema stability, but user cell editing should not depend on it.

Add collection document helpers:

- update column title.
- update column width.
- update hidden state.
- update required state.
- update allowed values.
- update description.
- compute validation issues for rows/columns.

Validation should be deterministic and local. It should not call Codex.

## Validation Rules

Validation should return structured issues with:

- row ID.
- column ID.
- severity, initially `error`.
- message.

Rules:

- Required field: empty trimmed value is invalid.
- Number field: non-empty value must parse as a number after removing commas.
- Year field: non-empty value must parse to a reasonable 4-digit year.
- Date field: non-empty value must parse through the app's accepted date formats.
- Badge/select field: if `allowedValues` is non-empty, non-empty value must be one of those values.

The grid should not block saving invalid values. It should expose them. This matches the project preference to surface real problems rather than hide them.

## Codex Contract

Update the collection Codex editing contract:

- New columns must include the new field settings.
- Codex may fill cell values.
- Codex should not invent values outside `allowedValues` when present.
- Codex should not remove field settings unless explicitly requested.
- Codex should preserve stable IDs and row IDs.

The collection prompt should include hidden/required/allowed-values context for fields so Codex can work within the table model.

## Implementation Boundaries

Recommended implementation slices:

1. Core model:
   - column settings.
   - validation issue type.
   - validation helpers.
   - JSON backward compatibility.
2. App model:
   - column setting update APIs.
   - validation issue derivation for selected collection.
   - collection prompt context update.
3. UI state:
   - selected cell.
   - editing cell.
   - active view.
   - filter/sort/visible fields state.
4. Collection table UI:
   - workbench header.
   - view tabs.
   - formula bar.
   - grid.
   - inspector.
   - status bar.
5. Verification:
   - core checks for defaults and validation.
   - source/layout checks for the new table workbench structure.
   - Swift build.
   - bundle rebuild.
   - app relaunch.

## Testing And Verification

Required checks:

- `swift run PaperCodexCoreChecks collections collection-sources ui-layout-source`
- `swift build`
- `git diff --check`
- `scripts/build-app-bundle.sh`
- Relaunch `/Users/chunqiu/Applications/PaperCodex.app`

Core checks should cover:

- existing collection JSON decodes without new keys.
- new columns encode/decode the new settings.
- hidden fields remain persistent.
- required validation catches empty cells.
- number/year/date validation catches invalid strings.
- allowed values validation catches invalid badge/select cells.
- validation returns row and column IDs.

Source/layout checks should cover:

- `CollectionView` contains a workbench-style table surface.
- formula/current-cell bar exists.
- field inspector exists.
- status bar exists.
- cells are editable for metadata and custom fields.
- column settings update paths exist in `AppModel`.
- collection prompt includes new field settings.

Manual verification should include:

- Open Collections route in the installed app.
- Select a cell and see selected-cell state.
- Edit a metadata cell and confirm it persists.
- Hide and restore a column.
- Add a custom field.
- Trigger or observe validation feedback.
- Confirm chat remains available but is not the dominant layout.

## Completion Criteria

The implementation is complete when:

- The Collections screen visually reads as a spreadsheet workbench rather than a simple list-plus-toolbar.
- The user can edit metadata and custom cells.
- The user can inspect and adjust field settings.
- Hidden fields, required state, allowed values, and description persist in collection JSON.
- Invalid table values are visible in the grid and summarized.
- The app builds, checks pass, bundle rebuild succeeds, and the installed app is relaunched.
- The implementation is committed with a standard message.
