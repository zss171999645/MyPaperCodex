import PaperCodexCore
import SwiftUI

fileprivate enum CollectionTableViewMode: String, CaseIterable, Identifiable {
    case all
    case invalid
    case missingRequired

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All Papers"
        case .invalid:
            "Invalid Values"
        case .missingRequired:
            "Missing Required"
        }
    }
}

fileprivate struct CollectionCellCoordinate: Equatable {
    var rowID: String
    var columnID: String
}

fileprivate func validationCellKey(rowID: String, columnID: String) -> String {
    "\(rowID)::\(columnID)"
}

struct CollectionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedRowIDs: Set<String> = []
    @State private var isCreatingCollection = false
    @State private var isAddingColumn = false
    @State private var collectionPendingRename: PaperCollectionDocument?
    @State private var collectionPendingDelete: PaperCollectionDocument?
    @State private var filterText = ""
    @State private var sortColumnID: String?
    @State private var sortAscending = true
    @State private var activeViewMode: CollectionTableViewMode = .all
    @State private var selectedCell: CollectionCellCoordinate?
    @State private var editingCell: CollectionCellCoordinate?
    @State private var cancelledEditingCell: CollectionCellCoordinate?
    @State private var formulaDraft = ""
    @State private var formulaDraftCell: CollectionCellCoordinate?

    var body: some View {
        SidebarSplitLayout(minContentWidth: 940) {
            sidebar
        } content: {
            contentPane
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if model.selectedCollectionID == nil {
                model.selectedCollectionID = model.collections.first?.id
            }
        }
        .onChange(of: model.selectedCollectionID) { _, _ in
            selectedRowIDs.removeAll()
            filterText = ""
            sortColumnID = nil
            sortAscending = true
            activeViewMode = .all
            selectedCell = nil
            editingCell = nil
            cancelledEditingCell = nil
            formulaDraft = ""
            formulaDraftCell = nil
        }
        .sheet(isPresented: $isCreatingCollection) {
            CollectionCreateSheet(
                categories: model.categories,
                libraryPaperCount: model.papers.filter { !$0.isArxivImportPlaceholder }.count
            ) { title, categoryID in
                if let categoryID {
                    model.createCollectionFromCategory(categoryID)
                } else {
                    model.createCollection(title: title, paperIDs: model.papers.filter { !$0.isArxivImportPlaceholder }.map(\.id))
                }
                isCreatingCollection = false
            } onCancel: {
                isCreatingCollection = false
            }
        }
        .sheet(isPresented: $isAddingColumn) {
            if let collection = model.selectedCollection {
                CollectionColumnSheet(collection: collection) { title, kind in
                    model.addColumn(toCollectionID: collection.id, title: title, kind: kind)
                    isAddingColumn = false
                } onCancel: {
                    isAddingColumn = false
                }
            }
        }
        .sheet(item: $collectionPendingRename) { collection in
            CollectionRenameSheet(collection: collection) { title, description in
                model.renameCollection(collection.id, title: title, description: description)
                collectionPendingRename = nil
            } onCancel: {
                collectionPendingRename = nil
            }
        }
        .alert("Delete collection?", isPresented: Binding(
            get: { collectionPendingDelete != nil },
            set: { if !$0 { collectionPendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let collectionPendingDelete {
                    model.deleteCollection(collectionPendingDelete.id)
                }
                collectionPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                collectionPendingDelete = nil
            }
        } message: {
            Text("This removes the collection JSON and its Codex workspace. Papers stay in the library.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Paper Codex")
                .font(.paperCodexSystem(size: 24, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                navButton(title: "Library", systemImage: "books.vertical") {
                    model.goToLibrary()
                }
                navButton(title: "Discover", systemImage: "sparkle.magnifyingglass") {
                    model.showDiscover()
                }
                navButton(title: "Collections", systemImage: "tablecells", selected: true) {}
                navButton(title: "Settings", systemImage: "gearshape") {
                    model.showSettings()
                }
            }

            Divider()

            HStack {
                Label("Collections", systemImage: "tablecells")
                    .font(.headline)
                Spacer()
                Button {
                    isCreatingCollection = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New Collection")
            }

            if model.collections.isEmpty {
                Text("No collections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(model.collections) { collection in
                            SidebarRowButton(
                                title: collection.title,
                                systemImage: "tablecells",
                                selected: model.selectedCollectionID == collection.id,
                                action: {
                                    model.selectCollection(collection)
                                }
                            )
                            .help("\(collection.rows.count) papers")
                        }
                    }
                    .padding(.trailing, 2)
                }
            }
        }
        .paperCodexSidebarChromePadding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var contentPane: some View {
        if let collection = model.selectedCollection {
            HStack(spacing: 0) {
                tablePane(collection)
                Divider()
                CollectionChatPanel(collection: collection)
                    .frame(width: 380)
            }
        } else {
            ContentUnavailableView {
                Label("No Collections", systemImage: "tablecells")
            } description: {
                Text("Build a comparison table from library papers or a folder.")
            } actions: {
                Button {
                    isCreatingCollection = true
                } label: {
                    Label("New Collection", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tablePane(_ collection: PaperCollectionDocument) -> some View {
        let visibleColumns = visibleColumns(for: collection)
        let validationIssues = model.validationIssues(for: collection)
        let validationIssuesByCell = Dictionary(grouping: validationIssues) { issue in
            validationCellKey(rowID: issue.rowID, columnID: issue.columnID)
        }
        let displayRows = displayedRows(for: collection, issues: validationIssues)
        let displayedRowIDs = Set(displayRows.map(\.id))
        let visibleColumnIDs = Set(visibleColumns.map(\.id))

        return CollectionWorkbench(
            collection: collection,
            displayRows: displayRows,
            visibleColumns: visibleColumns,
            allColumns: collection.columns,
            categories: model.categories,
            jsonPath: model.collectionJSONPath(for: collection.id),
            validationIssues: validationIssues,
            validationIssuesByCell: validationIssuesByCell,
            selectedRowIDs: $selectedRowIDs,
            activeViewMode: $activeViewMode,
            selectedCell: $selectedCell,
            editingCell: $editingCell,
            cancelledEditingCell: $cancelledEditingCell,
            formulaDraft: $formulaDraft,
            formulaDraftCell: $formulaDraftCell,
            filterText: $filterText,
            sortColumnID: sortColumnID,
            sortAscending: sortAscending,
            onAddColumn: {
                isAddingColumn = true
            },
            onAddAllPapers: {
                model.addPapers(
                    model.papers.filter { !$0.isArxivImportPlaceholder }.map(\.id),
                    toCollectionID: collection.id
                )
            },
            onAddCategory: { category in
                model.addCategory(category.id, toCollectionID: collection.id)
            },
            onSortColumn: { columnID, ascending in
                sortColumnID = columnID
                sortAscending = ascending
            },
            onClearSort: {
                sortColumnID = nil
            },
            onToggleSortDirection: {
                sortAscending.toggle()
            },
            onSetColumnHidden: { columnID, hidden in
                model.setCollectionColumnHidden(collectionID: collection.id, columnID: columnID, hidden: hidden)
            },
            onUpdateColumnTitle: { columnID, title in
                model.updateCollectionColumnTitle(collectionID: collection.id, columnID: columnID, title: title)
            },
            onUpdateColumnWidth: { columnID, width in
                model.updateCollectionColumnWidth(collectionID: collection.id, columnID: columnID, width: width)
            },
            onSetColumnRequired: { columnID, required in
                model.setCollectionColumnRequired(collectionID: collection.id, columnID: columnID, required: required)
            },
            onSetColumnAllowedValues: { columnID, allowedValues in
                model.setCollectionColumnAllowedValues(collectionID: collection.id, columnID: columnID, allowedValues: allowedValues)
            },
            onSetColumnDescription: { columnID, description in
                model.setCollectionColumnDescription(collectionID: collection.id, columnID: columnID, description: description)
            },
            onChatSelection: {
                let selectedPapers = model.papers(in: collection, rowIDs: selectedRowIDs.isEmpty ? nil : selectedRowIDs)
                model.openPapersForChat(selectedPapers.map(\.id))
            },
            onRevealJSON: {
                model.revealCollectionSource(collection.id)
            },
            onRename: {
                collectionPendingRename = collection
            },
            onDelete: {
                collectionPendingDelete = collection
            },
            onCellCommit: { rowID, columnID, value in
                model.updateCollectionCell(
                    collectionID: collection.id,
                    rowID: rowID,
                    columnID: columnID,
                    value: value
                )
            },
            onMoveSelection: { columnOffset, rowOffset in
                moveSelection(
                    columnOffset: columnOffset,
                    rowOffset: rowOffset,
                    displayedRows: displayRows,
                    visibleColumns: visibleColumns
                )
            },
            commitFormulaDraft: {
                commitFormulaDraft(collection: collection)
            },
            cancelCellEdit: {
                cancelCellEdit(collection: collection)
            },
            onOpenPaper: { paperID in
                if let paper = model.papers.first(where: { $0.id == paperID }) {
                    model.openPaper(paper)
                }
            }
        )
        .onAppear {
            pruneSelectedCell(displayedRowIDs: displayedRowIDs, visibleColumnIDs: visibleColumnIDs)
        }
        .onChange(of: displayedRowIDs) { _, newRowIDs in
            pruneSelectedCell(displayedRowIDs: newRowIDs, visibleColumnIDs: visibleColumnIDs)
        }
        .onChange(of: visibleColumnIDs) { _, newColumnIDs in
            pruneSelectedCell(displayedRowIDs: displayedRowIDs, visibleColumnIDs: newColumnIDs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func pruneSelectedCell(displayedRowIDs: Set<String>, visibleColumnIDs: Set<String>) {
        guard let selectedCell else {
            return
        }
        if !displayedRowIDs.contains(selectedCell.rowID) || !visibleColumnIDs.contains(selectedCell.columnID) {
            self.selectedCell = nil
            if editingCell == selectedCell {
                cancelledEditingCell = selectedCell
                editingCell = nil
            }
            formulaDraft = ""
            formulaDraftCell = nil
        }
    }

    private func moveSelection(
        columnOffset: Int,
        rowOffset: Int,
        displayedRows: [PaperCollectionRow],
        visibleColumns: [PaperCollectionColumn]
    ) {
        guard !displayedRows.isEmpty, !visibleColumns.isEmpty else {
            selectedCell = nil
            cancelledEditingCell = editingCell
            editingCell = nil
            formulaDraftCell = nil
            formulaDraft = ""
            return
        }
        let currentRowIndex = selectedCell.flatMap { cell in
            displayedRows.firstIndex { $0.id == cell.rowID }
        } ?? 0
        let currentColumnIndex = selectedCell.flatMap { cell in
            visibleColumns.firstIndex { $0.id == cell.columnID }
        } ?? 0
        let nextRowIndex = min(max(currentRowIndex + rowOffset, 0), displayedRows.count - 1)
        let nextColumnIndex = min(max(currentColumnIndex + columnOffset, 0), visibleColumns.count - 1)
        selectedCell = CollectionCellCoordinate(
            rowID: displayedRows[nextRowIndex].id,
            columnID: visibleColumns[nextColumnIndex].id
        )
        editingCell = nil
    }

    private func commitFormulaDraft(collection: PaperCollectionDocument) {
        commitFormulaDraft(collection: collection, coordinate: formulaDraftCell ?? selectedCell)
    }

    private func commitFormulaDraft(collection: PaperCollectionDocument, coordinate: CollectionCellCoordinate?) {
        guard let coordinate else {
            return
        }
        let currentValue = collection.rows.first { $0.id == coordinate.rowID }?.values[coordinate.columnID, default: ""] ?? ""
        guard formulaDraft != currentValue else {
            return
        }
        model.updateCollectionCell(
            collectionID: collection.id,
            rowID: coordinate.rowID,
            columnID: coordinate.columnID,
            value: formulaDraft
        )
    }

    private func cancelCellEdit(collection: PaperCollectionDocument) {
        cancelledEditingCell = editingCell
        editingCell = nil
        guard let selectedCell,
              let row = collection.rows.first(where: { $0.id == selectedCell.rowID }) else {
            formulaDraft = ""
            formulaDraftCell = nil
            return
        }
        formulaDraft = row.values[selectedCell.columnID, default: ""]
        formulaDraftCell = selectedCell
    }

    private func navButton(title: String, systemImage: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        SidebarRowButton(title: title, systemImage: systemImage, selected: selected, action: action)
    }

    private var normalizedFilterText: String {
        filterText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func visibleColumns(for collection: PaperCollectionDocument) -> [PaperCollectionColumn] {
        let visibleColumns = collection.columns.filter { !$0.isHidden }
        return visibleColumns.isEmpty ? Array(collection.columns.prefix(1)) : visibleColumns
    }

    private func displayedRows(for collection: PaperCollectionDocument, issues: [PaperCollectionValidationIssue]) -> [PaperCollectionRow] {
        let query = normalizedFilterText
        var rows = query.isEmpty ? collection.rows : collection.rows.filter { row in
            rowMatchesFilter(row, query: query)
        }
        rows = rows.filter { row in
            rowMatchesViewMode(row, issues: issues)
        }
        if let sortColumnID,
           let sortColumn = collection.columns.first(where: { $0.id == sortColumnID }) {
            rows = rows.sorted { left, right in
                let leftValue = left.values[sortColumn.id, default: ""]
                let rightValue = right.values[sortColumn.id, default: ""]
                let leftIsEmpty = leftValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let rightIsEmpty = rightValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if leftIsEmpty != rightIsEmpty {
                    return !leftIsEmpty
                }
                let comparison = compareCollectionValues(
                    leftValue,
                    rightValue,
                    kind: sortColumn.valueKind
                )
                if comparison == .orderedSame {
                    return left.values["paper_title", default: ""]
                        .localizedStandardCompare(right.values["paper_title", default: ""]) == .orderedAscending
                }
                return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
            }
        }
        return rows
    }

    private func rowMatchesViewMode(_ row: PaperCollectionRow, issues: [PaperCollectionValidationIssue]) -> Bool {
        switch activeViewMode {
        case .all:
            return true
        case .invalid:
            return issues.contains { issue in
                issue.rowID == row.id
            }
        case .missingRequired:
            return issues.contains { issue in
                issue.rowID == row.id && issue.reason == .required
            }
        }
    }

    private func rowMatchesFilter(_ row: PaperCollectionRow, query: String) -> Bool {
        row.paperID.localizedCaseInsensitiveContains(query)
            || row.values.values.contains { value in
                value.localizedCaseInsensitiveContains(query)
            }
    }

    private func compareCollectionValues(_ left: String, _ right: String, kind: PaperCollectionColumnValueKind) -> ComparisonResult {
        let leftValue = left.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightValue = right.trimmingCharacters(in: .whitespacesAndNewlines)
        if leftValue.isEmpty && rightValue.isEmpty {
            return .orderedSame
        }
        if leftValue.isEmpty {
            return .orderedDescending
        }
        if rightValue.isEmpty {
            return .orderedAscending
        }
        if (kind == .number || kind == .year),
           let leftNumber = collectionNumberValue(leftValue),
           let rightNumber = collectionNumberValue(rightValue) {
            if leftNumber == rightNumber {
                return .orderedSame
            }
            return leftNumber < rightNumber ? .orderedAscending : .orderedDescending
        }
        return leftValue.localizedStandardCompare(rightValue)
    }

    private func collectionNumberValue(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: ""))
    }

    private func rowCountTitle(displayRows: Int, totalRows: Int) -> String {
        normalizedFilterText.isEmpty ? "\(totalRows) papers" : "\(displayRows)/\(totalRows) papers"
    }

    private func sortLabel(for collection: PaperCollectionDocument) -> String {
        guard let sortColumnID,
              let column = collection.columns.first(where: { $0.id == sortColumnID }) else {
            return "Sort"
        }
        return column.title
    }
}

private struct CollectionWorkbench: View {
    var collection: PaperCollectionDocument
    var displayRows: [PaperCollectionRow]
    var visibleColumns: [PaperCollectionColumn]
    var allColumns: [PaperCollectionColumn]
    var categories: [PaperCodexCore.Category]
    var jsonPath: String
    var validationIssues: [PaperCollectionValidationIssue]
    var validationIssuesByCell: [String: [PaperCollectionValidationIssue]]
    @Binding var selectedRowIDs: Set<String>
    @Binding var activeViewMode: CollectionTableViewMode
    @Binding var selectedCell: CollectionCellCoordinate?
    @Binding var editingCell: CollectionCellCoordinate?
    @Binding var cancelledEditingCell: CollectionCellCoordinate?
    @Binding var formulaDraft: String
    @Binding var formulaDraftCell: CollectionCellCoordinate?
    @Binding var filterText: String
    var sortColumnID: String?
    var sortAscending: Bool
    var onAddColumn: () -> Void
    var onAddAllPapers: () -> Void
    var onAddCategory: (PaperCodexCore.Category) -> Void
    var onSortColumn: (String, Bool) -> Void
    var onClearSort: () -> Void
    var onToggleSortDirection: () -> Void
    var onSetColumnHidden: (String, Bool) -> Void
    var onUpdateColumnTitle: (String, String) -> Void
    var onUpdateColumnWidth: (String, Double) -> Void
    var onSetColumnRequired: (String, Bool) -> Void
    var onSetColumnAllowedValues: (String, [String]) -> Void
    var onSetColumnDescription: (String, String) -> Void
    var onChatSelection: () -> Void
    var onRevealJSON: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void
    var onCellCommit: (String, String, String) -> Void
    var onMoveSelection: (Int, Int) -> Void
    var commitFormulaDraft: () -> Void
    var cancelCellEdit: () -> Void
    var onOpenPaper: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            CollectionWorkbenchHeader(
                collection: collection,
                displayRowCount: displayRows.count,
                visibleColumnCount: visibleColumns.count,
                jsonPath: jsonPath,
                onRename: onRename,
                onRevealJSON: onRevealJSON,
                onDelete: onDelete
            )
            Divider()
            toolbar
            CollectionViewTabs(
                activeViewMode: $activeViewMode,
                allCount: collection.rows.count,
                invalidCount: invalidRowIDs.count,
                missingRequiredCount: missingRequiredRowIDs.count
            )
            Divider()
            CollectionFormulaBar(
                collection: collection,
                selectedCell: selectedCell,
                columns: allColumns,
                formulaDraft: $formulaDraft,
                formulaDraftCell: $formulaDraftCell,
                commitFormulaDraft: commitFormulaDraft
            )
            Divider()
            HStack(spacing: 0) {
                CollectionSpreadsheet(
                    rows: displayRows,
                    columns: visibleColumns,
                    selectedRowIDs: $selectedRowIDs,
                    selectedCell: $selectedCell,
                    editingCell: $editingCell,
                    cancelledEditingCell: $cancelledEditingCell,
                    validationIssuesByCell: validationIssuesByCell,
                    sortColumnID: sortColumnID,
                    sortAscending: sortAscending,
                    onSortColumn: onSortColumn,
                    onHideColumn: { columnID in
                        onSetColumnHidden(columnID, true)
                    },
                    onCellCommit: onCellCommit,
                    onMoveSelection: onMoveSelection,
                    commitFormulaDraft: commitFormulaDraft,
                    cancelCellEdit: cancelCellEdit,
                    onOpenPaper: onOpenPaper
                )
                Divider()
                CollectionFieldInspector(
                    collection: collection,
                    selectedCell: selectedCell,
                    columns: allColumns,
                    visibleColumnCount: visibleColumns.count,
                    validationIssues: validationIssues,
                    onUpdateColumnTitle: onUpdateColumnTitle,
                    onSetColumnHidden: onSetColumnHidden,
                    onUpdateColumnWidth: onUpdateColumnWidth,
                    onSetColumnRequired: onSetColumnRequired,
                    onSetColumnAllowedValues: onSetColumnAllowedValues,
                    onSetColumnDescription: onSetColumnDescription
                )
                .frame(width: 260)
            }
            Divider()
            CollectionStatusBar(
                displayRowCount: displayRows.count,
                totalRowCount: collection.rows.count,
                selectedRowCount: selectedRowIDs.count,
                visibleColumnCount: visibleColumns.count,
                totalColumnCount: allColumns.count,
                issueCount: validationIssues.count,
                editingCell: editingCell
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                Button(action: onAddColumn) {
                    Label("Column", systemImage: "rectangle.badge.plus")
                }
                .buttonStyle(.bordered)

                Menu {
                    Button(action: onAddAllPapers) {
                        Label("All Library Papers", systemImage: "books.vertical")
                    }
                    Divider()
                    ForEach(categories) { category in
                        Button {
                            onAddCategory(category)
                        } label: {
                            Label(category.name, systemImage: "folder")
                        }
                    }
                } label: {
                    Label("Add Papers", systemImage: "plus")
                }
                .menuStyle(.button)

                filterField

                Menu {
                    Button(action: onClearSort) {
                        Label("No Sort", systemImage: sortColumnID == nil ? "checkmark" : "circle")
                    }
                    Divider()
                    ForEach(allColumns) { column in
                        Button {
                            onSortColumn(column.id, true)
                        } label: {
                            Label(column.title, systemImage: sortColumnID == column.id ? "checkmark" : column.valueKind.systemImage)
                        }
                    }
                } label: {
                    Label(sortLabel, systemImage: "arrow.up.arrow.down")
                }
                .menuStyle(.button)

                Button(action: onToggleSortDirection) {
                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(sortColumnID == nil)
                .help(sortAscending ? "Ascending" : "Descending")

                columnsMenu

                Button(action: onChatSelection) {
                    Label(selectedRowIDs.isEmpty ? "Chat All" : "Chat \(selectedRowIDs.count)", systemImage: "text.bubble")
                }
                .buttonStyle(.borderedProminent)
                .disabled(collection.rows.isEmpty)

                if !selectedRowIDs.isEmpty {
                    Button {
                        selectedRowIDs.removeAll()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter rows", text: $filterText)
                .textFieldStyle(.plain)
                .frame(width: 200)
            if !filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear Filter")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.black.opacity(0.10), lineWidth: 1)
        )
    }

    private var columnsMenu: some View {
        Menu {
            ForEach(allColumns) { column in
                let isVisible = !column.isHidden
                let isLastVisibleColumn = isVisible && visibleColumns.count <= 1
                Button {
                    onSetColumnHidden(column.id, isVisible)
                } label: {
                    Label(column.title, systemImage: isVisible ? "checkmark.circle.fill" : "circle")
                }
                .disabled(isLastVisibleColumn)
            }
        } label: {
            Label("Columns", systemImage: "rectangle.3.group")
        }
        .menuStyle(.button)
    }

    private var sortLabel: String {
        guard let sortColumnID,
              let column = allColumns.first(where: { $0.id == sortColumnID }) else {
            return "Sort"
        }
        return column.title
    }

    private var invalidRowIDs: Set<String> {
        Set(validationIssues.map(\.rowID))
    }

    private var missingRequiredRowIDs: Set<String> {
        Set(validationIssues.filter { $0.reason == .required }.map(\.rowID))
    }
}

private struct CollectionWorkbenchHeader: View {
    var collection: PaperCollectionDocument
    var displayRowCount: Int
    var visibleColumnCount: Int
    var jsonPath: String
    var onRename: () -> Void
    var onRevealJSON: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(collection.title)
                    .font(.paperCodexSystem(size: 22, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Label("\(displayRowCount)/\(collection.rows.count) papers", systemImage: "doc.text")
                    Label("\(visibleColumnCount)/\(collection.columns.count) columns", systemImage: "rectangle.grid.3x2")
                    Text(jsonPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onRename) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Rename Collection")
            Button(action: onRevealJSON) {
                Image(systemName: "curlybraces.square")
            }
            .buttonStyle(.borderless)
            .help("Reveal collection.json")
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete Collection")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct CollectionViewTabs: View {
    @Binding var activeViewMode: CollectionTableViewMode
    var allCount: Int
    var invalidCount: Int
    var missingRequiredCount: Int

    var body: some View {
        Picker("View", selection: $activeViewMode) {
            ForEach(CollectionTableViewMode.allCases) { mode in
                Text("\(mode.title) \(count(for: mode))").tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func count(for mode: CollectionTableViewMode) -> Int {
        switch mode {
        case .all:
            return allCount
        case .invalid:
            return invalidCount
        case .missingRequired:
            return missingRequiredCount
        }
    }
}

private struct CollectionFormulaBar: View {
    var collection: PaperCollectionDocument
    var selectedCell: CollectionCellCoordinate?
    var columns: [PaperCollectionColumn]
    @Binding var formulaDraft: String
    @Binding var formulaDraftCell: CollectionCellCoordinate?
    var commitFormulaDraft: () -> Void
    @FocusState private var isFormulaFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(coordinateLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            Text(fieldLabel)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)
            Text(typeLabel)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            TextField("Select a table cell", text: $formulaDraft)
                .textFieldStyle(.plain)
                .focused($isFormulaFocused)
                .disabled(selectedCell == nil)
                .onAppear {
                    formulaDraftCell = selectedCell
                    formulaDraft = selectedValue
                }
                .onChange(of: selectedCell) { _, newCell in
                    if isFormulaFocused {
                        commitFormulaDraft()
                    }
                    formulaDraftCell = newCell
                    formulaDraft = selectedValue
                }
                .onChange(of: selectedValue) { _, newValue in
                    if !isFormulaFocused {
                        formulaDraftCell = selectedCell
                        formulaDraft = newValue
                    }
                }
                .onChange(of: isFormulaFocused) { _, focused in
                    if !focused {
                        commitFormulaDraft()
                    }
                }
                .onSubmit {
                    commitFormulaDraft()
                }
            Spacer(minLength: 0)
        }
        .font(.paperCodexSystem(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.70))
    }

    private var selectedValue: String {
        guard let selectedCell,
              let row = collection.rows.first(where: { $0.id == selectedCell.rowID }) else {
            return ""
        }
        return row.values[selectedCell.columnID, default: ""]
    }

    private var coordinateLabel: String {
        guard let selectedCell,
              let rowIndex = collection.rows.firstIndex(where: { $0.id == selectedCell.rowID }),
              let columnIndex = columns.firstIndex(where: { $0.id == selectedCell.columnID }) else {
            return "--"
        }
        return "\(spreadsheetColumnName(columnIndex))\(rowIndex + 1)"
    }

    private var fieldLabel: String {
        selectedColumn?.title ?? "No cell selected"
    }

    private var typeLabel: String {
        selectedColumn?.valueKind.displayTitle ?? "--"
    }

    private var selectedColumn: PaperCollectionColumn? {
        guard let selectedCell else {
            return nil
        }
        return columns.first { $0.id == selectedCell.columnID }
    }

    private func spreadsheetColumnName(_ index: Int) -> String {
        var value = index + 1
        var name = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            name = String(UnicodeScalar(65 + remainder)!) + name
            value = (value - 1) / 26
        }
        return name
    }
}

private struct CollectionFieldInspector: View {
    var collection: PaperCollectionDocument
    var selectedCell: CollectionCellCoordinate?
    var columns: [PaperCollectionColumn]
    var visibleColumnCount: Int
    var validationIssues: [PaperCollectionValidationIssue]
    var onUpdateColumnTitle: (String, String) -> Void
    var onSetColumnHidden: (String, Bool) -> Void
    var onUpdateColumnWidth: (String, Double) -> Void
    var onSetColumnRequired: (String, Bool) -> Void
    var onSetColumnAllowedValues: (String, [String]) -> Void
    var onSetColumnDescription: (String, String) -> Void

    @State private var titleDraft = ""
    @State private var allowedValuesDraft = ""
    @State private var descriptionDraft = ""
    @State private var draftColumnID: String?
    @FocusState private var focusedField: InspectorFocusedField?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Field Inspector", systemImage: "sidebar.right")
                .font(.paperCodexSystem(size: 14, weight: .semibold))
            if let column {
                Group {
                    editableTextField(
                        "Field title",
                        text: $titleDraft,
                        focus: .title,
                        onCommit: { commitTitleIfChanged(column) }
                    )
                    inspectorRow("Field ID", column.id)
                    inspectorRow("Type", column.valueKind.displayTitle)

                    Stepper(
                        "Width: \(Int(column.width))",
                        value: Binding(
                            get: { column.width },
                            set: { onUpdateColumnWidth(column.id, $0) }
                        ),
                        in: 72...420,
                        step: 8
                    )
                    .font(.caption)

                    Toggle("Visible", isOn: Binding(
                        get: { !column.isHidden },
                        set: { isVisible in
                            guard isVisible || column.isHidden || visibleColumnCount > 1 else {
                                return
                            }
                            onSetColumnHidden(column.id, !isVisible)
                        }
                    ))
                    .font(.caption)
                    .disabled(!column.isHidden && visibleColumnCount <= 1)

                    Toggle("Required", isOn: Binding(
                        get: { column.isRequired },
                        set: { onSetColumnRequired(column.id, $0) }
                    ))
                    .font(.caption)

                    editableTextField(
                        "Allowed values",
                        text: $allowedValuesDraft,
                        focus: .allowedValues,
                        onCommit: {
                            commitAllowedValuesIfChanged(column)
                        }
                    )

                    editableTextField(
                        "Description",
                        text: $descriptionDraft,
                        focus: .description,
                        onCommit: { commitDescriptionIfChanged(column) }
                    )
                }
                if let selectedCell {
                    let issues = validationIssues.filter { $0.rowID == selectedCell.rowID && $0.columnID == selectedCell.columnID }
                    if !issues.isEmpty {
                        Divider()
                        ForEach(issues) { issue in
                            Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            } else {
                Text("Select a cell to inspect its field settings and validation state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        .onAppear(perform: syncDrafts)
        .onChange(of: column?.id) { _, _ in
            commitFocusedField(focusedField)
            syncDrafts()
        }
        .onChange(of: column?.title) { _, _ in
            if focusedField != .title {
                syncDrafts()
            }
        }
        .onChange(of: column?.allowedValues) { _, _ in
            if focusedField != .allowedValues {
                syncDrafts()
            }
        }
        .onChange(of: column?.description) { _, _ in
            if focusedField != .description {
                syncDrafts()
            }
        }
        .onChange(of: focusedField) { previous, current in
            if current == nil {
                commitFocusedField(previous)
            }
        }
    }

    private var column: PaperCollectionColumn? {
        guard let selectedCell else {
            return nil
        }
        return columns.first { $0.id == selectedCell.columnID }
    }

    private func inspectorRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    private func editableTextField(
        _ title: String,
        text: Binding<String>,
        focus: InspectorFocusedField,
        onCommit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .focused($focusedField, equals: focus)
                .onSubmit(onCommit)
        }
    }

    private func syncDrafts() {
        titleDraft = column?.title ?? ""
        allowedValuesDraft = column?.allowedValues.joined(separator: ", ") ?? ""
        descriptionDraft = column?.description ?? ""
        draftColumnID = column?.id
    }

    private func commitFocusedField(_ field: InspectorFocusedField?) {
        guard let column = draftColumn else {
            return
        }
        switch field {
        case .title:
            commitTitleIfChanged(column)
        case .allowedValues:
            commitAllowedValuesIfChanged(column)
        case .description:
            commitDescriptionIfChanged(column)
        case nil:
            break
        }
    }

    private func commitTitleIfChanged(_ column: PaperCollectionColumn) {
        let normalizedTitle = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty, normalizedTitle != column.title else {
            return
        }
        onUpdateColumnTitle(column.id, normalizedTitle)
    }

    private func commitAllowedValuesIfChanged(_ column: PaperCollectionColumn) {
        let values = allowedValuesDraft.collectionCommaSeparatedValues
        guard values != column.allowedValues else {
            return
        }
        onSetColumnAllowedValues(column.id, values)
    }

    private func commitDescriptionIfChanged(_ column: PaperCollectionColumn) {
        guard descriptionDraft != column.description else {
            return
        }
        onSetColumnDescription(column.id, descriptionDraft)
    }

    private var draftColumn: PaperCollectionColumn? {
        guard let draftColumnID else {
            return nil
        }
        return columns.first { $0.id == draftColumnID }
    }
}

private enum InspectorFocusedField: Hashable {
    case title
    case allowedValues
    case description
}

private struct CollectionStatusBar: View {
    var displayRowCount: Int
    var totalRowCount: Int
    var selectedRowCount: Int
    var visibleColumnCount: Int
    var totalColumnCount: Int
    var issueCount: Int
    var editingCell: CollectionCellCoordinate?

    var body: some View {
        HStack(spacing: 14) {
            Label("\(displayRowCount)/\(totalRowCount) rows", systemImage: "line.3.horizontal")
            Label("\(visibleColumnCount)/\(totalColumnCount) columns", systemImage: "rectangle.grid.3x2")
            Label("\(selectedRowCount) selected", systemImage: "checkmark.circle")
            Label("\(issueCount) issues", systemImage: issueCount == 0 ? "checkmark.seal" : "exclamationmark.triangle")
            Spacer()
            if editingCell != nil {
                Label("Editing", systemImage: "pencil")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct CollectionSpreadsheet: View {
    var rows: [PaperCollectionRow]
    var columns: [PaperCollectionColumn]
    @Binding var selectedRowIDs: Set<String>
    @Binding var selectedCell: CollectionCellCoordinate?
    @Binding var editingCell: CollectionCellCoordinate?
    @Binding var cancelledEditingCell: CollectionCellCoordinate?
    var validationIssuesByCell: [String: [PaperCollectionValidationIssue]]
    var sortColumnID: String?
    var sortAscending: Bool
    var onSortColumn: (String, Bool) -> Void
    var onHideColumn: (String) -> Void
    var onCellCommit: (String, String, String) -> Void
    var onMoveSelection: (Int, Int) -> Void
    var commitFormulaDraft: () -> Void
    var cancelCellEdit: () -> Void
    var onOpenPaper: (String) -> Void
    @FocusState private var isGridFocused: Bool

    private var totalWidth: CGFloat {
        72 + columns.reduce(CGFloat(0)) { $0 + CGFloat($1.width) }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    CollectionTableRow(
                        index: index,
                        row: row,
                        columns: columns,
                        isSelected: selectedRowIDs.contains(row.id),
                        selectedCell: $selectedCell,
                        editingCell: $editingCell,
                        cancelledEditingCell: $cancelledEditingCell,
                        validationIssuesByCell: validationIssuesByCell,
                        onToggleSelection: {
                            toggle(row.id)
                        },
                        onOpenPaper: {
                            onOpenPaper(row.paperID)
                        },
                        onCellCommit: { columnID, value in
                            onCellCommit(row.id, columnID, value)
                        },
                        onMoveSelection: onMoveSelection,
                        cancelCellEdit: cancelCellEdit
                    )
                }
            }
            .frame(width: max(totalWidth, 820), alignment: .topLeading)
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .focusable()
        .focused($isGridFocused)
        .onChange(of: selectedCell) { _, _ in
            if editingCell == nil {
                isGridFocused = true
            }
        }
        .onKeyPress(.escape) {
            cancelCellEdit()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard editingCell == nil else { return .ignored }
            onMoveSelection(-1, 0)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard editingCell == nil else { return .ignored }
            onMoveSelection(1, 0)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard editingCell == nil else { return .ignored }
            onMoveSelection(0, -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard editingCell == nil else { return .ignored }
            onMoveSelection(0, 1)
            return .handled
        }
        .onKeyPress(.tab) {
            commitFormulaDraft()
            onMoveSelection(1, 0)
            return .handled
        }
        .onKeyPress(.return) {
            commitFormulaDraft()
            return .handled
        }
    }

    private var selectedDisplayedCount: Int {
        rows.filter { selectedRowIDs.contains($0.id) }.count
    }

    private var selectionIcon: String {
        if selectedDisplayedCount == 0 {
            return "circle"
        }
        if selectedDisplayedCount == rows.count {
            return "checkmark.circle.fill"
        }
        return "minus.circle.fill"
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: selectionIcon)
                    .foregroundStyle(selectedDisplayedCount == 0 ? Color.secondary : Color.accentColor)
                Text("#")
                    .font(.paperCodexSystem(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72, height: 36, alignment: .leading)
            .padding(.horizontal, 10)
            .background(CollectionTableStyle.headerBackground)
            .overlay(CollectionGridLine(), alignment: .trailing)
            .onTapGesture {
                toggleDisplayedRows()
            }

            ForEach(columns) { column in
                Menu {
                    Button {
                        onSortColumn(column.id, true)
                    } label: {
                        Label("Sort Ascending", systemImage: "arrow.up")
                    }
                    Button {
                        onSortColumn(column.id, false)
                    } label: {
                        Label("Sort Descending", systemImage: "arrow.down")
                    }
                    Divider()
                    Button {
                        onHideColumn(column.id)
                    } label: {
                        Label("Hide Column", systemImage: "eye.slash")
                    }
                    .disabled(columns.count <= 1)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: column.valueKind.systemImage)
                            .foregroundStyle(Color.accentColor)
                        Text(column.title)
                            .lineLimit(1)
                        if sortColumnID == column.id {
                            Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .font(.paperCodexSystem(size: 12.5, weight: .semibold))
                    .frame(width: CGFloat(column.width), height: 36, alignment: .leading)
                    .padding(.horizontal, 10)
                    .background(CollectionTableStyle.headerBackground)
                    .overlay(CollectionGridLine(), alignment: .trailing)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .overlay(CollectionGridLine(), alignment: .bottom)
    }

    private func toggleDisplayedRows() {
        let displayedIDs = Set(rows.map(\.id))
        guard !displayedIDs.isEmpty else {
            return
        }
        if displayedIDs.isSubset(of: selectedRowIDs) {
            selectedRowIDs.subtract(displayedIDs)
        } else {
            selectedRowIDs.formUnion(displayedIDs)
        }
    }

    private func toggle(_ rowID: String) {
        if selectedRowIDs.contains(rowID) {
            selectedRowIDs.remove(rowID)
        } else {
            selectedRowIDs.insert(rowID)
        }
    }
}

private struct CollectionTableRow: View {
    var index: Int
    var row: PaperCollectionRow
    var columns: [PaperCollectionColumn]
    var isSelected: Bool
    @Binding var selectedCell: CollectionCellCoordinate?
    @Binding var editingCell: CollectionCellCoordinate?
    @Binding var cancelledEditingCell: CollectionCellCoordinate?
    var validationIssuesByCell: [String: [PaperCollectionValidationIssue]]
    var onToggleSelection: () -> Void
    var onOpenPaper: () -> Void
    var onCellCommit: (String, String) -> Void
    var onMoveSelection: (Int, Int) -> Void
    var cancelCellEdit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(isSelected ? "Deselect Row" : "Select Row")
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72, height: 42, alignment: .leading)
            .padding(.horizontal, 10)
            .background(rowBackground)
            .overlay(CollectionGridLine(), alignment: .trailing)

            ForEach(columns) { column in
                let coordinate = CollectionCellCoordinate(rowID: row.id, columnID: column.id)
                let issues = validationIssuesByCell[validationCellKey(rowID: row.id, columnID: column.id), default: []]
                CollectionTableCell(
                    value: row.values[column.id, default: ""],
                    column: column,
                    coordinate: coordinate,
                    validationIssues: issues,
                    isSelected: selectedCell == coordinate,
                    selectedCell: $selectedCell,
                    editingCell: $editingCell,
                    cancelledEditingCell: $cancelledEditingCell,
                    onOpenPaper: column.id == "paper_title" ? onOpenPaper : nil,
                    onCommit: { value in
                        onCellCommit(column.id, value)
                    },
                    onMoveSelection: onMoveSelection,
                    cancelCellEdit: cancelCellEdit
                )
                .frame(width: CGFloat(column.width), height: 42, alignment: .leading)
                .padding(.horizontal, 10)
                .background(rowBackground)
                .overlay(CollectionGridLine(), alignment: .trailing)
            }
        }
        .overlay(CollectionGridLine(), alignment: .bottom)
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.10)
        }
        return index.isMultiple(of: 2) ? Color(nsColor: .textBackgroundColor).opacity(0.64) : Color(nsColor: .windowBackgroundColor)
    }
}

private struct CollectionTableCell: View {
    var value: String
    var column: PaperCollectionColumn
    var coordinate: CollectionCellCoordinate
    var validationIssues: [PaperCollectionValidationIssue]
    var isSelected: Bool
    @Binding var selectedCell: CollectionCellCoordinate?
    @Binding var editingCell: CollectionCellCoordinate?
    @Binding var cancelledEditingCell: CollectionCellCoordinate?
    var onOpenPaper: (() -> Void)?
    var onCommit: (String) -> Void
    var onMoveSelection: (Int, Int) -> Void
    var cancelCellEdit: () -> Void

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let onOpenPaper {
                Button(action: onOpenPaper) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Open Paper")
            }
            if editingCell == coordinate {
                TextField(column.title, text: $draft)
                    .textFieldStyle(.plain)
                    .font(cellFont)
                    .focused($isFocused)
                    .onAppear {
                        draft = value
                        isFocused = true
                    }
                    .onChange(of: value) { _, newValue in
                        if !isFocused {
                            draft = newValue
                        }
                    }
                    .onChange(of: isFocused) { _, focused in
                        if focused {
                            selectedCell = coordinate
                            editingCell = coordinate
                        } else {
                            commitDraft()
                            if editingCell == coordinate {
                                editingCell = nil
                            }
                        }
                    }
                    .onSubmit {
                        commitDraft()
                        editingCell = nil
                    }
                    .onKeyPress(.escape) {
                        draft = value
                        cancelCellEdit()
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        commitDraft()
                        editingCell = nil
                        onMoveSelection(1, 0)
                        return .handled
                    }
            } else {
                Text(value.isEmpty ? " " : value)
                    .font(cellFont)
                    .lineLimit(1)
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !validationIssues.isEmpty {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .help(issueMessages)
            }
        }
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColor, lineWidth: validationIssues.isEmpty ? (isSelected ? 1 : 0) : 2)
        )
        .help(issueMessages)
        .onTapGesture(count: 2) {
            if editingCell != coordinate {
                editingCell = nil
            }
            selectedCell = coordinate
            editingCell = coordinate
            draft = value
        }
        .onTapGesture {
            if editingCell != coordinate {
                editingCell = nil
            }
            selectedCell = coordinate
        }
        .onAppear {
            draft = value
        }
        .onChange(of: editingCell) { oldValue, newValue in
            if oldValue == coordinate && newValue != coordinate {
                if cancelledEditingCell == coordinate {
                    draft = value
                    cancelledEditingCell = nil
                } else {
                    commitDraft()
                }
            }
            if newValue != coordinate {
                draft = value
            }
        }
    }

    private func commitDraft() {
        if draft != value {
            onCommit(draft)
        }
    }

    private var cellFont: Font {
        .paperCodexSystem(size: 13, weight: column.id == "paper_title" ? .medium : .regular)
    }

    private var borderColor: Color {
        validationIssues.isEmpty ? Color.accentColor.opacity(0.45) : Color.red
    }

    private var issueMessages: String {
        validationIssues.map(\.message).joined(separator: "\n")
    }
}

private enum CollectionTableStyle {
    static let headerBackground = Color(nsColor: .controlBackgroundColor)
}

private struct CollectionGridLine: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.08))
            .frame(width: 1, height: 1)
    }
}

private extension String {
    var collectionCommaSeparatedValues: [String] {
        split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct CollectionChatPanel: View {
    @EnvironmentObject private var model: AppModel
    var collection: PaperCollectionDocument
    @State private var draft = ""

    private var messages: [ChatMessage] {
        model.collectionMessages(for: collection.id)
    }

    private var activeRun: ActiveCodexRun? {
        model.activeCodexRun(forCollectionID: collection.id)
    }

    private var isSending: Bool {
        activeRun != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Collection Chat", systemImage: "wand.and.stars")
                    .font(.paperCodexSystem(size: 15, weight: .semibold))
                Spacer()
                if isSending {
                    Button {
                        model.cancelCollectionCodexRun(collection.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("Stop Codex")
                }
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if messages.isEmpty && activeRun == nil {
                            ContentUnavailableView(
                                "Ask Codex to Fill the Table",
                                systemImage: "tablecells.badge.ellipsis",
                                description: Text("Examples: summarize each paper, classify by method, mark datasets, or add decision labels.")
                            )
                            .padding(.top, 40)
                        }
                        ForEach(messages) { message in
                            CollectionChatBubble(message: message)
                                .id(message.id)
                        }
                        if let activeRun {
                            CollectionRunBubble(run: activeRun)
                                .id("collection-active-run")
                        }
                        Color.clear.frame(height: 1).id("collection-chat-bottom")
                    }
                    .padding(14)
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: activeRun?.events.count ?? 0) { _, _ in
                    scrollToBottom(proxy)
                }
            }
            Divider()
            quickPrompts
            HStack(alignment: .bottom, spacing: 8) {
                TextEditor(text: $draft)
                    .font(.paperCodexSystem(size: 13))
                    .frame(minHeight: 76, maxHeight: 110)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.black.opacity(0.10), lineWidth: 1)
                    )
                Button {
                    send()
                } label: {
                    Image(systemName: isSending ? "hourglass.circle.fill" : "arrow.up.circle.fill")
                        .font(.paperCodexSystem(size: 26))
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSending ? Color.secondary : Color.blue)
                .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Send")
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var quickPrompts: some View {
        HStack(spacing: 6) {
            quickPrompt("Summarize", "Summarize each paper into one concise cell. Add a Summary column if needed.")
            quickPrompt("Classify", "Classify the papers by method family. Add a Method Family column if needed.")
            quickPrompt("Decision", "Add a Decision Label column and tag each paper as must-read, useful, or optional.")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private func quickPrompt(_ title: String, _ prompt: String) -> some View {
        Button(title) {
            draft = prompt
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func send() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isSending else {
            return
        }
        draft = ""
        Task {
            await model.sendCollectionMessage(message, collectionID: collection.id)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.16)) {
                proxy.scrollTo("collection-chat-bottom", anchor: .bottom)
            }
        }
    }
}

private struct CollectionChatBubble: View {
    var message: ChatMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            Text(message.role == .user ? "You" : "Codex")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(message.content)
                .font(.paperCodexSystem(size: 13))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(background, in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var background: Color {
        message.role == .user ? Color.accentColor.opacity(0.16) : Color(nsColor: .textBackgroundColor)
    }
}

private struct CollectionRunBubble: View {
    var run: ActiveCodexRun

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(run.title, systemImage: "brain.head.profile")
                .font(.paperCodexSystem(size: 13, weight: .semibold))
            ForEach(run.events.suffix(5)) { event in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: event.kind.systemImage)
                        .foregroundStyle(event.kind.tint)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.displayTitle)
                            .font(.caption.weight(.semibold))
                        Text(event.previewDetail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.20), lineWidth: 1)
        )
    }
}

private struct CollectionCreateSheet: View {
    var categories: [PaperCodexCore.Category]
    var libraryPaperCount: Int
    var onCreate: (String, String?) -> Void
    var onCancel: () -> Void

    @State private var title = "Paper Collection"
    @State private var source: CollectionCreateSource = .all
    @State private var categoryID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("New Collection", systemImage: "tablecells")
                .font(.title3.weight(.semibold))
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
            Picker("Source", selection: $source) {
                Label("All Library Papers", systemImage: "books.vertical").tag(CollectionCreateSource.all)
                Label("Folder", systemImage: "folder").tag(CollectionCreateSource.folder)
            }
            .pickerStyle(.segmented)
            if source == .folder {
                Picker("Folder", selection: $categoryID) {
                    ForEach(categories) { category in
                        Text(category.name).tag(category.id)
                    }
                }
                .labelsHidden()
            }
            Text(source == .all ? "\(libraryPaperCount) papers will be added." : "The folder and its subfolders will be added.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Create") {
                    onCreate(title, source == .folder ? categoryID : nil)
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (source == .folder && categoryID.isEmpty))
            }
        }
        .padding(22)
        .frame(width: 420)
        .onAppear {
            categoryID = categoryID.isEmpty ? (categories.first?.id ?? "") : categoryID
        }
    }
}

private enum CollectionCreateSource: Hashable {
    case all
    case folder
}

private struct CollectionColumnSheet: View {
    var collection: PaperCollectionDocument
    var onCreate: (String, PaperCollectionColumnValueKind) -> Void
    var onCancel: () -> Void

    @State private var title = ""
    @State private var kind: PaperCollectionColumnValueKind = .text

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Add Column", systemImage: "rectangle.badge.plus")
                .font(.title3.weight(.semibold))
            TextField("Column title", text: $title)
                .textFieldStyle(.roundedBorder)
            Picker("Type", selection: $kind) {
                ForEach(PaperCollectionColumnValueKind.customKinds, id: \.self) { kind in
                    Label(kind.displayTitle, systemImage: kind.systemImage).tag(kind)
                }
            }
            .pickerStyle(.menu)
            Text("This adds an editable field to \(collection.title). Codex can fill it from chat.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Add") {
                    onCreate(title, kind)
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 380)
    }
}

private struct CollectionRenameSheet: View {
    var collection: PaperCollectionDocument
    var onSave: (String, String) -> Void
    var onCancel: () -> Void

    @State private var title: String
    @State private var description: String

    init(collection: PaperCollectionDocument, onSave: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.collection = collection
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: collection.title)
        _description = State(initialValue: collection.description)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Collection Settings", systemImage: "pencil")
                .font(.title3.weight(.semibold))
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
            TextField("Description", text: $description)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    onSave(title, description)
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}

private extension PaperCollectionColumnValueKind {
    static var customKinds: [PaperCollectionColumnValueKind] {
        [.text, .longText, .badge, .number, .date]
    }

    var displayTitle: String {
        switch self {
        case .paperTitle:
            "Paper"
        case .authors:
            "Authors"
        case .year:
            "Year"
        case .categories:
            "Folders"
        case .tags:
            "Tags"
        case .sourceURL:
            "Source"
        case .text:
            "Text"
        case .longText:
            "Long Text"
        case .number:
            "Number"
        case .date:
            "Date"
        case .badge:
            "Badge"
        }
    }

    var systemImage: String {
        switch self {
        case .paperTitle:
            "doc.text"
        case .authors:
            "person.2"
        case .year:
            "calendar"
        case .categories:
            "folder"
        case .tags:
            "tag"
        case .sourceURL:
            "link"
        case .text:
            "text.alignleft"
        case .longText:
            "text.justify.left"
        case .number:
            "number"
        case .date:
            "calendar.badge.clock"
        case .badge:
            "checkmark.seal"
        }
    }
}

private extension CodexRunEventKind {
    var systemImage: String {
        switch self {
        case .status:
            "circle.dotted"
        case .thinking:
            "brain.head.profile"
        case .tool:
            "wrench.and.screwdriver"
        case .terminal:
            "terminal"
        case .answer:
            "text.bubble"
        case .usage:
            "gauge"
        case .warning:
            "exclamationmark.triangle"
        case .error:
            "xmark.octagon"
        case .raw:
            "doc.plaintext"
        }
    }

    var tint: Color {
        switch self {
        case .error:
            .red
        case .warning:
            .orange
        case .answer:
            .green
        case .thinking:
            .purple
        case .terminal, .tool:
            .blue
        case .usage:
            .teal
        case .status, .raw:
            .secondary
        }
    }
}
