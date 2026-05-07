# Collection Advanced Table Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Paper Codex Collections screen into an advanced local spreadsheet-style table workbench with field settings, validation, selected-cell editing, and a table-first layout.

**Architecture:** Extend the existing JSON-backed collection model first, then expose narrow `AppModel` update methods, then replace the current `CollectionView` table pane with a workbench composed of header, toolbar, view tabs, formula bar, grid, field inspector, and status bar. Validation remains deterministic and local; it never calls Codex and never blocks saving.

**Tech Stack:** Swift, SwiftUI, PaperCodexCore JSON models, `PaperCodexCoreChecks`, existing `scripts/build-app-bundle.sh`.

---

## File Structure

- Modify `Sources/PaperCodexCore/PaperCollection.swift`
  - Add column settings: `isRequired`, `allowedValues`, `description`.
  - Add `PaperCollectionValidationIssue`.
  - Add column setting mutators and `validationIssues()`.
  - Update Codex editing contract.
- Modify `Sources/PaperCodexApp/AppModel.swift`
  - Add column setting update APIs.
  - Add collection validation access helper.
  - Include hidden/required/allowed-values/description in collection prompts.
- Modify `Sources/PaperCodexApp/CollectionView.swift`
  - Replace the current collection table area with an advanced table workbench.
  - Add local view mode, selected cell, editing behavior, formula bar, field inspector, and status bar.
- Modify `Sources/PaperCodexCoreChecks/main.swift`
  - Add core validation checks.
  - Add source checks for workbench, formula bar, inspector, status bar, editable metadata, and AppModel column setting APIs.
- No new runtime dependency should be introduced.

## Task 1: Core Column Settings And Validation

**Files:**
- Modify: `Sources/PaperCodexCore/PaperCollection.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] **Step 1: Add failing core checks for new column settings and validation**

In `runCollectionChecks()` after the existing hidden-column check, add checks shaped like this:

```swift
edited.setColumnRequired(customColumn.id, required: true, updatedAt: now.addingTimeInterval(100))
try check(edited.columns.first { $0.id == customColumn.id }?.isRequired == true, "collection columns should support required fields")

edited.setColumnAllowedValues(customColumn.id, allowedValues: ["latent", "baseline"], updatedAt: now.addingTimeInterval(110))
try check(edited.columns.first { $0.id == customColumn.id }?.allowedValues == ["latent", "baseline"], "collection columns should support allowed values")

edited.setColumnDescription(customColumn.id, description: "Decision label for paper triage.", updatedAt: now.addingTimeInterval(120))
try check(edited.columns.first { $0.id == customColumn.id }?.description == "Decision label for paper triage.", "collection columns should support descriptions")

var invalid = edited
invalid.updateCell(rowID: invalid.rows[0].id, columnID: customColumn.id, value: "surprise", updatedAt: now.addingTimeInterval(130))
let invalidIssues = invalid.validationIssues()
try check(invalidIssues.contains { $0.rowID == invalid.rows[0].id && $0.columnID == customColumn.id }, "collection validation should report row and column ids")
try check(invalidIssues.contains { $0.message.contains("allowed") }, "collection validation should report allowed-value failures")

let requiredColumn = PaperCollectionColumn(id: "priority", title: "Priority", valueKind: .number, width: 100, isLocked: false, isRequired: true)
invalid.columns.append(requiredColumn)
for index in invalid.rows.indices {
    invalid.rows[index].values[requiredColumn.id] = index == 0 ? "" : "not-a-number"
}
let requiredIssues = invalid.validationIssues()
try check(requiredIssues.contains { $0.columnID == "priority" && $0.message.contains("required") }, "collection validation should report empty required values")
try check(requiredIssues.contains { $0.columnID == "priority" && $0.message.contains("number") }, "collection validation should report invalid number values")
```

Also add contract checks:

```swift
try check(contract.contains("isRequired"), "collection codex contract should include required-column state")
try check(contract.contains("allowedValues"), "collection codex contract should include allowed values")
try check(contract.contains("description"), "collection codex contract should include field descriptions")
```

- [ ] **Step 2: Run the checks and verify they fail**

Run:

```bash
swift run PaperCodexCoreChecks collections
```

Expected: build fails with missing members such as `setColumnRequired`, `allowedValues`, `description`, or `validationIssues`.

- [ ] **Step 3: Implement the core model**

In `PaperCollectionColumn`, add properties and defaulted initializer parameters:

```swift
public var isRequired: Bool
public var allowedValues: [String]
public var description: String
```

Extend `CodingKeys`, `init(from:)`, and `encode(to:)` so old JSON decodes with:

```swift
isRequired = try container.decodeIfPresent(Bool.self, forKey: .isRequired) ?? false
allowedValues = try container.decodeIfPresent([String].self, forKey: .allowedValues) ?? []
description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
```

Add:

```swift
public struct PaperCollectionValidationIssue: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(rowID):\(columnID):\(message)" }
    public var rowID: String
    public var columnID: String
    public var severity: String
    public var message: String

    public init(rowID: String, columnID: String, severity: String = "error", message: String) {
        self.rowID = rowID
        self.columnID = columnID
        self.severity = severity
        self.message = message
    }
}
```

Add mutators to `PaperCollectionDocument`:

```swift
public mutating func updateColumnTitle(_ columnID: String, title: String, updatedAt: Date = Date())
public mutating func updateColumnWidth(_ columnID: String, width: Double, updatedAt: Date = Date())
public mutating func setColumnRequired(_ columnID: String, required: Bool, updatedAt: Date = Date())
public mutating func setColumnAllowedValues(_ columnID: String, allowedValues: [String], updatedAt: Date = Date())
public mutating func setColumnDescription(_ columnID: String, description: String, updatedAt: Date = Date())
public func validationIssues() -> [PaperCollectionValidationIssue]
```

Validation rules:

```swift
let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
if column.isRequired && trimmed.isEmpty {
    issues.append(PaperCollectionValidationIssue(rowID: row.id, columnID: column.id, message: "\(column.title) is required."))
}
if !trimmed.isEmpty && column.valueKind == .number && Double(trimmed.replacingOccurrences(of: ",", with: "")) == nil {
    issues.append(PaperCollectionValidationIssue(rowID: row.id, columnID: column.id, message: "\(column.title) must be a number."))
}
if !trimmed.isEmpty && column.valueKind == .year && !Self.isValidYear(trimmed) {
    issues.append(PaperCollectionValidationIssue(rowID: row.id, columnID: column.id, message: "\(column.title) must be a 4-digit year."))
}
if !trimmed.isEmpty && column.valueKind == .date && !Self.isValidDate(trimmed) {
    issues.append(PaperCollectionValidationIssue(rowID: row.id, columnID: column.id, message: "\(column.title) must be a valid date."))
}
if !trimmed.isEmpty && !column.allowedValues.isEmpty && !column.allowedValues.contains(trimmed) {
    issues.append(PaperCollectionValidationIssue(rowID: row.id, columnID: column.id, message: "\(column.title) must use an allowed value."))
}
```

Use `ISO8601DateFormatter`, `yyyy-MM-dd`, and `yyyy/MM/dd` as accepted date formats.

- [ ] **Step 4: Update the Codex editing contract**

In `PaperCollectionDocument.codexEditingContract`, require new columns to include:

```text
id, title, valueKind, width, isLocked, isHidden, isRequired, allowedValues, and description
```

Add guidance that Codex should use `allowedValues` when present and preserve field settings unless the user asks to change them.

- [ ] **Step 5: Run checks and commit**

Run:

```bash
swift run PaperCodexCoreChecks collections
git diff --check
```

Expected: `collections: pass` and no diff-check output.

Commit:

```bash
git add Sources/PaperCodexCore/PaperCollection.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: add collection field validation model"
```

## Task 2: AppModel Column Setting APIs And Prompt Context

**Files:**
- Modify: `Sources/PaperCodexApp/AppModel.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] **Step 1: Add failing source checks**

In `runUILayoutSourceChecks()`, extend the existing collection checks with:

```swift
try check(
    appModelSource.contains("func updateCollectionColumnTitle")
        && appModelSource.contains("func updateCollectionColumnWidth")
        && appModelSource.contains("func setCollectionColumnRequired")
        && appModelSource.contains("func setCollectionColumnAllowedValues")
        && appModelSource.contains("func setCollectionColumnDescription"),
    "AppModel should expose collection field setting update APIs"
)
try check(
    appModelSource.contains("validationIssues(for collection:")
        && appModelSource.contains("allowedValues:")
        && appModelSource.contains("required:"),
    "AppModel collection prompts should include validation and field setting context"
)
```

- [ ] **Step 2: Run source checks and verify they fail**

Run:

```bash
swift run PaperCodexCoreChecks ui-layout-source
```

Expected: fails on missing AppModel APIs and prompt context.

- [ ] **Step 3: Implement AppModel update APIs**

Add methods near `setCollectionColumnHidden`:

```swift
func updateCollectionColumnTitle(collectionID: String, columnID: String, title: String)
func updateCollectionColumnWidth(collectionID: String, columnID: String, width: Double)
func setCollectionColumnRequired(collectionID: String, columnID: String, required: Bool)
func setCollectionColumnAllowedValues(collectionID: String, columnID: String, allowedValues: [String])
func setCollectionColumnDescription(collectionID: String, columnID: String, description: String)
func validationIssues(for collection: PaperCollectionDocument) -> [PaperCollectionValidationIssue]
```

Each updater should:

```swift
guard let collectionIndex = collections.firstIndex(where: { $0.id == collectionID }) else {
    throw AppModelError.collectionNotFound(collectionID)
}
var collection = collections[collectionIndex]
collection.setColumnRequired(columnID, required: required)
try collectionStore.save(collection)
collections[collectionIndex] = collection
selectedCollectionID = collectionID
```

Use the matching mutator for each API. For allowed values, trim whitespace and drop empty values before saving:

```swift
let normalized = allowedValues
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
collection.setColumnAllowedValues(columnID, allowedValues: normalized)
```

- [ ] **Step 4: Expand collection prompt column context**

Update `collectionPrompt` column rendering to include:

```swift
"- \(column.id): \(column.title) (\(column.valueKind.rawValue), locked: \(column.isLocked), hidden: \(column.isHidden), required: \(column.isRequired), allowedValues: \(column.allowedValues), description: \(column.description))"
```

Append validation issue summary if `collection.validationIssues()` is non-empty.

- [ ] **Step 5: Run checks and commit**

Run:

```bash
swift run PaperCodexCoreChecks collections ui-layout-source
swift build
git diff --check
```

Expected: checks pass, build complete, no diff-check output.

Commit:

```bash
git add Sources/PaperCodexApp/AppModel.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: add collection field setting APIs"
```

## Task 3: Collection Workbench Shell

**Files:**
- Modify: `Sources/PaperCodexApp/CollectionView.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] **Step 1: Add failing source checks for the workbench shell**

In `runUILayoutSourceChecks()`, add:

```swift
try check(
    collectionSource.contains("CollectionWorkbench")
        && collectionSource.contains("CollectionViewTabs")
        && collectionSource.contains("CollectionFormulaBar")
        && collectionSource.contains("CollectionFieldInspector")
        && collectionSource.contains("CollectionStatusBar"),
    "CollectionView should render an advanced table workbench structure"
)
try check(
    collectionSource.contains("enum CollectionTableViewMode")
        && collectionSource.contains("struct CollectionCellCoordinate")
        && collectionSource.contains("@State private var selectedCell"),
    "CollectionView should track table view mode and selected cell state"
)
```

- [ ] **Step 2: Run source checks and verify they fail**

Run:

```bash
swift run PaperCodexCoreChecks ui-layout-source
```

Expected: fails on missing workbench components.

- [ ] **Step 3: Introduce table state types**

In `CollectionView.swift`, add file-private types:

```swift
private enum CollectionTableViewMode: String, CaseIterable, Identifiable {
    case all
    case invalid
    case missingRequired

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All Papers"
        case .invalid: "Invalid Values"
        case .missingRequired: "Missing Required"
        }
    }
}

private struct CollectionCellCoordinate: Equatable {
    var rowID: String
    var columnID: String
}
```

Add state to `CollectionView`:

```swift
@State private var activeViewMode: CollectionTableViewMode = .all
@State private var selectedCell: CollectionCellCoordinate?
@State private var editingCell: CollectionCellCoordinate?
```

Reset these on collection change.

- [ ] **Step 4: Replace table pane composition with `CollectionWorkbench`**

Make `tablePane(_:)` render:

```swift
CollectionWorkbench(
    collection: collection,
    rows: displayRows,
    columns: visibleColumns,
    validationIssues: validationIssues,
    activeViewMode: $activeViewMode,
    selectedRowIDs: $selectedRowIDs,
    selectedCell: $selectedCell,
    editingCell: $editingCell,
    filterText: $filterText,
    sortColumnID: $sortColumnID,
    sortAscending: $sortAscending,
    onAddField: { isAddingColumn = true },
    onCommitCell: { rowID, columnID, value in
        model.updateCollectionCell(collectionID: collection.id, rowID: rowID, columnID: columnID, value: value)
    },
    onSetColumnHidden: { columnID, hidden in
        model.setCollectionColumnHidden(collectionID: collection.id, columnID: columnID, hidden: hidden)
    }
)
```

Keep existing callbacks for cell commit, open paper, add papers, add field, reveal JSON, rename, delete, chat, and column hiding.

- [ ] **Step 5: Add shell components**

Create private SwiftUI structs in the same file:

```swift
private struct CollectionWorkbench: View {
    var body: some View {
        VStack(spacing: 0) {
            CollectionWorkbenchHeader()
            CollectionViewTabs()
            CollectionFormulaBar()
            HStack(spacing: 0) {
                CollectionSpreadsheet()
                CollectionFieldInspector()
            }
            CollectionStatusBar()
        }
    }
}

private struct CollectionWorkbenchHeader: View {
    var body: some View { EmptyView() }
}

private struct CollectionViewTabs: View {
    var body: some View { EmptyView() }
}

private struct CollectionFormulaBar: View {
    var body: some View { EmptyView() }
}

private struct CollectionFieldInspector: View {
    var body: some View { EmptyView() }
}

private struct CollectionStatusBar: View {
    var body: some View { EmptyView() }
}
```

At this task, these can render the final layout and pass through existing controls, but field setting controls can remain display-only until Task 4.

- [ ] **Step 6: Run checks and commit**

Run:

```bash
swift run PaperCodexCoreChecks ui-layout-source
swift build
git diff --check
```

Expected: source checks pass, build complete, no diff-check output.

Commit:

```bash
git add Sources/PaperCodexApp/CollectionView.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: add collection table workbench shell"
```

## Task 4: Grid Selection, Formula Bar Editing, Inspector Settings, And Validation UI

**Files:**
- Modify: `Sources/PaperCodexApp/CollectionView.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] **Step 1: Add failing source checks for interaction and validation UI**

Add checks:

```swift
try check(
    collectionSource.contains("onMoveSelection")
        && collectionSource.contains("commitFormulaDraft")
        && collectionSource.contains("cancelCellEdit")
        && collectionSource.contains(".onKeyPress"),
    "Collection table should support keyboard movement and formula-bar editing"
)
try check(
    collectionSource.contains("setCollectionColumnRequired")
        && collectionSource.contains("setCollectionColumnAllowedValues")
        && collectionSource.contains("setCollectionColumnDescription")
        && collectionSource.contains("updateCollectionColumnWidth"),
    "Collection field inspector should save field settings through AppModel"
)
try check(
    collectionSource.contains("validationIssuesByCell")
        && collectionSource.contains("Invalid Values")
        && collectionSource.contains("Missing Required"),
    "Collection grid should surface validation issues and validation views"
)
```

- [ ] **Step 2: Run source checks and verify they fail**

Run:

```bash
swift run PaperCodexCoreChecks ui-layout-source
```

Expected: fails on missing keyboard/formula/inspector code.

- [ ] **Step 3: Implement validation-aware row filtering**

Update displayed rows so `activeViewMode` applies after text filter:

```swift
switch activeViewMode {
case .all:
    break
case .invalid:
    rows = rows.filter { row in issuesByRowID[row.id]?.isEmpty == false }
case .missingRequired:
    rows = rows.filter { row in
        issuesByRowID[row.id, default: []].contains { $0.message.contains("required") }
    }
}
```

- [ ] **Step 4: Implement selected-cell grid behavior**

Update `CollectionSpreadsheet` / grid row cells to accept:

```swift
selectedCell: Binding<CollectionCellCoordinate?>
editingCell: Binding<CollectionCellCoordinate?>
validationIssuesByCell: [String: [PaperCollectionValidationIssue]]
onMoveSelection: (Int, Int) -> Void
cancelCellEdit: () -> Void
```

Cell click sets `selectedCell`. Double click sets `editingCell`. Invalid cells show a visible red outline and help text with the issue message.

- [ ] **Step 5: Implement keyboard basics**

Use SwiftUI keyboard handling available in this target. If `.onKeyPress` is available, attach it to the grid; otherwise use an AppKit-backed focused key handler local to `CollectionView.swift`. Required behavior:

```swift
Escape -> cancelCellEdit()
ArrowLeft/Right/Up/Down -> move selectedCell among displayed rows and visible columns when not editing
Tab -> commit current edit and move one visible cell to the right
Return -> commit current edit
```

Do not add a broad global event monitor.

- [ ] **Step 6: Implement formula bar editing**

`CollectionFormulaBar` should display:

- selected coordinate such as `B2`.
- selected field title.
- selected field type.
- text field bound to a formula draft.

When the formula draft commits, call `model.updateCollectionCell(collectionID:rowID:columnID:value:)` for the selected cell.

- [ ] **Step 7: Implement field inspector setting controls**

`CollectionFieldInspector` should support:

```swift
TextField("Field title", text: $titleDraft)
Stepper("Width: \(Int(widthDraft))", value: $widthDraft, in: 72...420, step: 8)
Toggle("Visible", isOn: $isVisibleDraft)
Toggle("Required", isOn: $isRequiredDraft)
TextField("Allowed values", text: $allowedValuesDraft)
TextField("Description", text: $descriptionDraft)
```

Commit controls through the AppModel methods from Task 2. Field ID is read-only. Existing type is display-only.

- [ ] **Step 8: Run checks and commit**

Run:

```bash
swift run PaperCodexCoreChecks collections collection-sources ui-layout-source
swift build
git diff --check
```

Expected: checks pass, build complete, no diff-check output.

Commit:

```bash
git add Sources/PaperCodexApp/CollectionView.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: add collection table inspector interactions"
```

## Task 5: Final Verification, Bundle Rebuild, Relaunch, And Completion Audit

**Files:**
- Modify only if verification finds a concrete gap.

- [ ] **Step 1: Run required automated verification**

Run:

```bash
swift run PaperCodexCoreChecks models repository citations anchors prompt workspace pdf codex codex-recovery paths fixture watch collections collection-sources ui-layout-source
swift build
git diff --check
```

Expected:

- every listed `PaperCodexCoreChecks` suite prints `pass`.
- `swift build` prints `Build complete`.
- `git diff --check` prints no output.

- [ ] **Step 2: Rebuild installed app bundle**

Run:

```bash
scripts/build-app-bundle.sh
```

Expected:

- build completes.
- `/Users/chunqiu/Applications/PaperCodex.app` is printed.
- codesign validation reports valid on disk and satisfies designated requirement.

- [ ] **Step 3: Relaunch installed app**

Run:

```bash
pgrep -af '/Users/chunqiu/Applications/PaperCodex.app/Contents/MacOS/PaperCodexApp|PaperCodexApp'
pkill -f '/Users/chunqiu/Applications/PaperCodex.app/Contents/MacOS/PaperCodexApp|PaperCodexApp' || true
open /Users/chunqiu/Applications/PaperCodex.app
pgrep -af '/Users/chunqiu/Applications/PaperCodex.app/Contents/MacOS/PaperCodexApp|PaperCodexApp'
```

Expected: a new `PaperCodexApp` PID is reported.

- [ ] **Step 4: Completion audit**

Verify the implementation against the spec:

- Collections visually uses workbench structure.
- Toolbar, view tabs, formula bar, grid, field inspector, and status bar are present in source.
- Metadata and custom cells use the same editable commit path.
- Column settings persist to collection JSON.
- Validation issues are local and visible.
- Chat remains present but secondary.
- No `.idea/` files are staged.

- [ ] **Step 5: Commit any final fixes**

If Task 5 required fixes, commit them:

```bash
git add Sources/PaperCodexCore/PaperCollection.swift Sources/PaperCodexApp/AppModel.swift Sources/PaperCodexApp/CollectionView.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "fix: polish collection table workbench"
```

If no fixes were required, do not create an empty commit.
