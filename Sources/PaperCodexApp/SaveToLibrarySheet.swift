import Foundation
import PaperCodexCore
import SwiftUI

typealias SaveToLibraryNewCategory = LibraryCategoryRequest

struct SaveToLibraryCategorySelection: Equatable {
    var categoryIDs: [String]
    var newCategoryNames: [String]
    var newCategories: [SaveToLibraryNewCategory]

    static let empty = SaveToLibraryCategorySelection(categoryIDs: [], newCategoryNames: [], newCategories: [])
}

private let saveToLibraryRootDraftParentID = "__papercodex-save-root__"

private enum SaveToLibraryLayout {
    static let treeConnectorHeight: CGFloat = 34
    static let treeIndentWidth: CGFloat = 22
    static let chevronWidth: CGFloat = 16
    static let chevronFolderSpacing: CGFloat = 4
    static let folderButtonLeadingPadding: CGFloat = 10
    static let folderIconWidth: CGFloat = 17
    static let treeConnectorTargetInset: CGFloat = 7
    static let treeConnectorLineWidth: CGFloat = 1
    static let treeConnectorOpacity = 0.16

    static var folderIconCenterX: CGFloat {
        chevronWidth + chevronFolderSpacing + folderButtonLeadingPadding + folderIconWidth / 2
    }

    static func folderIconCenterX(depth: Int) -> CGFloat {
        folderIconCenterX + CGFloat(depth) * treeIndentWidth
    }
}

struct SaveToLibrarySheet: View {
    var paperTitle: String
    var detail: String?
    var libraryCategories: [PaperCodexCore.Category]
    var initialCategoryIDs: [String]
    var onSave: (SaveToLibraryCategorySelection) -> Void
    var onCancel: () -> Void

    @State private var selectedCategoryIDs: Set<String>
    @State private var selectedNewCategoryIDs: Set<String> = []
    @State private var pendingNewCategories: [SaveToLibraryNewCategory] = []
    @State private var collapsedCategoryIDs: Set<String> = []
    @State private var activeNewCategoryParentID: String?
    @State private var newCategoryName = ""

    init(
        paperTitle: String,
        detail: String? = nil,
        libraryCategories: [PaperCodexCore.Category],
        initialCategoryIDs: [String] = [],
        onSave: @escaping (SaveToLibraryCategorySelection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.paperTitle = paperTitle
        self.detail = detail
        self.libraryCategories = libraryCategories
        self.initialCategoryIDs = initialCategoryIDs
        self.onSave = onSave
        self.onCancel = onCancel
        _selectedCategoryIDs = State(initialValue: Set(initialCategoryIDs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            destinationHeader
            folderPicker
            Divider()
            actionRow
        }
        .padding(22)
        .frame(width: 560)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.paperCodexSystem(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text("Save to Library")
                    .font(.title3.weight(.semibold))
                Text(paperTitle)
                    .font(.paperCodexSystem(size: 13, weight: .medium))
                    .lineLimit(2)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var destinationHeader: some View {
        SaveToLibraryDestinationHeader(
            folders: selectedFolderSummaries,
            onRemove: { folderID in
                toggleSelection(folderID)
            }
        )
    }

    private var folderPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Choose destination", systemImage: "folder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    beginNewCategory(parentID: nil)
                } label: {
                    Label("New root folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if activeNewCategoryParentID == saveToLibraryRootDraftParentID {
                        newCategoryInlineRow(parentID: nil, depth: 0, connectorContinuations: [])
                    }

                    if visibleFolderItems.isEmpty && activeNewCategoryParentID == nil {
                        Text("No folders yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(12)
                    } else {
                        ForEach(visibleFolderItems) { item in
                            SaveToLibraryFolderRow(
                                item: item,
                                isSelected: isSelected(item.node.id),
                                isExpanded: !collapsedCategoryIDs.contains(item.node.id),
                                hasChildren: hasChildren(item.node.id),
                                onToggleExpanded: {
                                    toggleCollapsed(item.node.id)
                                },
                                onToggleSelected: {
                                    toggleSelection(item.node.id)
                                },
                                onCreateChild: {
                                    beginNewCategory(parentID: item.node.id)
                                },
                                onRemoveNewCategory: item.node.isNew ? {
                                    removeNewCategory(item.node.id)
                                } : nil
                            )
                            if activeNewCategoryParentID == item.node.id {
                                newCategoryInlineRow(
                                    parentID: item.node.id,
                                    depth: item.depth + 1,
                                    connectorContinuations: item.connectorContinuations + [hasChildren(item.node.id)]
                                )
                            }
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func newCategoryInlineRow(parentID: String?, depth: Int, connectorContinuations: [Bool]) -> some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(width: SaveToLibraryLayout.chevronWidth, height: 24)
            Image(systemName: "folder.badge.plus")
                .frame(width: SaveToLibraryLayout.folderIconWidth)
                .foregroundStyle(Color.accentColor)
            TextField("New folder", text: $newCategoryName)
                .textFieldStyle(.roundedBorder)
            Button {
                commitNewCategory(parentID: parentID)
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderless)
            .disabled(trimmedNewCategoryName.isEmpty)
            .help("Add Folder")
            Button {
                cancelNewCategory()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Cancel")
        }
        .padding(.leading, CGFloat(depth) * SaveToLibraryLayout.treeIndentWidth)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .background(alignment: .leading) {
            SaveToLibraryTreeConnector(
                depth: depth,
                connectorContinuations: connectorContinuations
            )
            .allowsHitTesting(false)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Cancel", action: onCancel)
            Button {
                onSave(
                    SaveToLibraryCategorySelection(
                        categoryIDs: selectedCategoryIDsInOrder,
                        newCategoryNames: [],
                        newCategories: selectedNewCategoriesInOrder
                    )
                )
            } label: {
                Label("Save", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCategoryIDs.isEmpty && selectedNewCategoryIDs.isEmpty)
        }
    }

    private var visibleFolderItems: [SaveToLibraryFolderItem] {
        folderItems(parentID: nil, respectingCollapse: true)
    }

    private var allFolderItems: [SaveToLibraryFolderItem] {
        folderItems(parentID: nil, respectingCollapse: false)
    }

    private var allFolderNodes: [SaveToLibraryFolderNode] {
        let existing = libraryCategories.map { category in
            SaveToLibraryFolderNode(
                id: category.id,
                parentID: category.parentID,
                name: category.name,
                sortOrder: category.sortOrder,
                isPinned: category.isPinned,
                isNew: false
            )
        }
        let pending = pendingNewCategories.enumerated().map { index, category in
            SaveToLibraryFolderNode(
                id: category.id,
                parentID: category.parentID,
                name: category.name,
                sortOrder: Int.max / 2 + index,
                isPinned: false,
                isNew: true
            )
        }
        return existing + pending
    }

    private var selectedFolderSummaries: [SaveToLibrarySelectedFolderSummary] {
        allFolderItems.compactMap { item in
            guard isSelected(item.node.id) else {
                return nil
            }
            return SaveToLibrarySelectedFolderSummary(id: item.node.id, path: folderDisplayPath(for: item.node))
        }
    }

    private var selectedCategoryIDsInOrder: [String] {
        allFolderItems.compactMap { item in
            guard !item.node.isNew, selectedCategoryIDs.contains(item.node.id) else {
                return nil
            }
            return item.node.id
        }
    }

    private var selectedNewCategoriesInOrder: [SaveToLibraryNewCategory] {
        let selectedIDs = selectedNewCategoryIDs.union(newCategoryAncestorIDs(for: selectedNewCategoryIDs))
        return allFolderItems.compactMap { item in
            guard item.node.isNew,
                  selectedIDs.contains(item.node.id),
                  let category = pendingNewCategories.first(where: { $0.id == item.node.id }) else {
                return nil
            }
            return category
        }
    }

    private var trimmedNewCategoryName: String {
        newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func folderItems(
        parentID: String?,
        depth: Int = 0,
        respectingCollapse: Bool,
        visited: Set<String> = [],
        ancestorContinuations: [Bool] = []
    ) -> [SaveToLibraryFolderItem] {
        let children = childNodes(parentID: parentID)
        return children.enumerated().flatMap { index, node -> [SaveToLibraryFolderItem] in
            guard !visited.contains(node.id) else {
                return []
            }
            let isLast = index == children.count - 1
            let connectorContinuations = depth == 0 ? [] : ancestorContinuations + [!isLast]
            let item = SaveToLibraryFolderItem(
                node: node,
                depth: depth,
                connectorContinuations: connectorContinuations
            )
            if respectingCollapse && collapsedCategoryIDs.contains(node.id) {
                return [item]
            }
            return [item] + folderItems(
                parentID: node.id,
                depth: depth + 1,
                respectingCollapse: respectingCollapse,
                visited: visited.union([node.id]),
                ancestorContinuations: connectorContinuations
            )
        }
    }

    private func childNodes(parentID: String?) -> [SaveToLibraryFolderNode] {
        allFolderNodes
            .filter { $0.parentID == parentID }
            .sorted { left, right in
                if left.isPinned != right.isPinned {
                    return left.isPinned
                }
                if left.sortOrder == right.sortOrder {
                    if left.isNew != right.isNew {
                        return !left.isNew
                    }
                    return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
                }
                return left.sortOrder < right.sortOrder
            }
    }

    private func hasChildren(_ categoryID: String) -> Bool {
        !childNodes(parentID: categoryID).isEmpty
    }

    private func isSelected(_ categoryID: String) -> Bool {
        if pendingNewCategories.contains(where: { $0.id == categoryID }) {
            return selectedNewCategoryIDs.contains(categoryID)
        }
        return selectedCategoryIDs.contains(categoryID)
    }

    private func toggleSelection(_ categoryID: String) {
        if pendingNewCategories.contains(where: { $0.id == categoryID }) {
            toggle(categoryID, in: &selectedNewCategoryIDs)
        } else {
            toggle(categoryID, in: &selectedCategoryIDs)
        }
    }

    private func toggle(_ value: String, in set: inout Set<String>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private func toggleCollapsed(_ categoryID: String) {
        toggle(categoryID, in: &collapsedCategoryIDs)
    }

    private func beginNewCategory(parentID: String?) {
        activeNewCategoryParentID = parentID ?? saveToLibraryRootDraftParentID
        newCategoryName = ""
        if let parentID {
            collapsedCategoryIDs.remove(parentID)
        }
    }

    private func commitNewCategory(parentID: String?) {
        let trimmed = trimmedNewCategoryName
        guard !trimmed.isEmpty else {
            return
        }
        let category = SaveToLibraryNewCategory(
            id: "new-category-\(UUID().uuidString)",
            parentID: parentID,
            name: trimmed
        )
        pendingNewCategories.append(category)
        selectedNewCategoryIDs.insert(category.id)
        if let parentID {
            collapsedCategoryIDs.remove(parentID)
        }
        cancelNewCategory()
    }

    private func cancelNewCategory() {
        activeNewCategoryParentID = nil
        newCategoryName = ""
    }

    private func removeNewCategory(_ categoryID: String) {
        let idsToRemove = Set([categoryID]).union(descendantIDs(of: categoryID))
        pendingNewCategories.removeAll { idsToRemove.contains($0.id) }
        selectedNewCategoryIDs.subtract(idsToRemove)
        collapsedCategoryIDs.subtract(idsToRemove)
        if activeNewCategoryParentID.map({ idsToRemove.contains($0) }) == true {
            cancelNewCategory()
        }
    }

    private func descendantIDs(of categoryID: String) -> Set<String> {
        var result: Set<String> = []
        var didChange = true
        while didChange {
            didChange = false
            for node in allFolderNodes where node.parentID.map({ $0 == categoryID || result.contains($0) }) == true && !result.contains(node.id) {
                result.insert(node.id)
                didChange = true
            }
        }
        return result
    }

    private func newCategoryAncestorIDs(for categoryIDs: Set<String>) -> Set<String> {
        var result: Set<String> = []
        var queue = Array(categoryIDs)
        while let categoryID = queue.popLast(),
              let parentID = pendingNewCategories.first(where: { $0.id == categoryID })?.parentID {
            if pendingNewCategories.contains(where: { $0.id == parentID }),
               !result.contains(parentID) {
                result.insert(parentID)
                queue.append(parentID)
            }
        }
        return result
    }

    private func folderDisplayPath(for node: SaveToLibraryFolderNode) -> String {
        var names = [node.name]
        var visited = Set([node.id])
        var parentID = node.parentID
        while let id = parentID,
              !visited.contains(id),
              let parent = allFolderNodes.first(where: { $0.id == id }) {
            names.append(parent.name)
            visited.insert(parent.id)
            parentID = parent.parentID
        }
        return names.reversed().joined(separator: " / ")
    }
}

private struct SaveToLibraryFolderNode: Equatable, Identifiable {
    var id: String
    var parentID: String?
    var name: String
    var sortOrder: Int
    var isPinned: Bool
    var isNew: Bool
}

private struct SaveToLibraryFolderItem: Identifiable {
    var node: SaveToLibraryFolderNode
    var depth: Int
    var connectorContinuations: [Bool] = []

    var id: String { node.id }
}

private struct SaveToLibrarySelectedFolderSummary: Identifiable {
    var id: String
    var path: String
}

private struct SaveToLibraryDestinationHeader: View {
    var folders: [SaveToLibrarySelectedFolderSummary]
    var onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Destination", systemImage: "target")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(folders.isEmpty ? "Choose destination" : "\(folders.count) selected")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if folders.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .foregroundStyle(.secondary)
                    Text("No folder selected")
                        .font(.paperCodexSystem(size: 12.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                SaveToLibraryFlowLayout(spacing: 6) {
                    ForEach(folders) { folder in
                        SaveToLibraryFolderPathChip(folder: folder) {
                            onRemove(folder.id)
                        }
                    }
                }
            }
        }
    }
}

private struct SaveToLibraryFolderPathChip: View {
    var folder: SaveToLibrarySelectedFolderSummary
    var onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 5) {
                Image(systemName: "folder.fill")
                    .font(.paperCodexSystem(size: 10.5, weight: .semibold))
                Text(folder.path)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.paperCodexSystem(size: 8.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("Remove \(folder.path)")
    }
}

private struct SaveToLibraryFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layout(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews).rows
        for row in rows {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
            }
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, rows: [SaveToLibraryFlowRow]) {
        let maxWidth = proposal.width ?? 520
        var rows: [SaveToLibraryFlowRow] = []
        var currentItems: [SaveToLibraryFlowItem] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if currentX > 0, currentX + size.width > maxWidth {
                rows.append(SaveToLibraryFlowRow(items: currentItems))
                currentY += rowHeight + spacing
                currentItems = []
                currentX = 0
                rowHeight = 0
            }
            currentItems.append(SaveToLibraryFlowItem(index: index, origin: CGPoint(x: currentX, y: currentY), size: size))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        if !currentItems.isEmpty {
            rows.append(SaveToLibraryFlowRow(items: currentItems))
        }
        let height = rows.last?.items.map { $0.origin.y + $0.size.height }.max() ?? 0
        return (CGSize(width: maxWidth, height: height), rows)
    }
}

private struct SaveToLibraryFlowRow {
    var items: [SaveToLibraryFlowItem]
}

private struct SaveToLibraryFlowItem {
    var index: Int
    var origin: CGPoint
    var size: CGSize
}

private struct SaveToLibraryFolderRow: View {
    @State private var isHovering = false

    var item: SaveToLibraryFolderItem
    var isSelected: Bool
    var isExpanded: Bool
    var hasChildren: Bool
    var onToggleExpanded: () -> Void
    var onToggleSelected: () -> Void
    var onCreateChild: () -> Void
    var onRemoveNewCategory: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            if hasChildren {
                Button(action: onToggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.paperCodexSystem(size: 9, weight: .bold))
                        .frame(width: 16, height: 24)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse" : "Expand")
            } else {
                Color.clear
                    .frame(width: 16, height: 24)
            }

            Button(action: onToggleSelected) {
                HStack(spacing: 8) {
                    Image(systemName: item.node.isNew ? "folder.badge.plus" : "folder")
                        .frame(width: 17)
                        .foregroundStyle(isSelected || item.node.isNew ? Color.accentColor : Color.secondary)
                    Text(item.node.name)
                        .font(.paperCodexSystem(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                    if item.node.isNew {
                        Text("New")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.65))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? Color.accentColor.opacity(0.11) : (isHovering ? Color.primary.opacity(0.045) : Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor.opacity(0.25) : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button(action: onCreateChild) {
                Image(systemName: "plus")
                    .font(.paperCodexSystem(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("New subfolder")

            if let onRemoveNewCategory {
                Button(action: onRemoveNewCategory) {
                    Image(systemName: "trash")
                        .font(.paperCodexSystem(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove new folder")
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .padding(.leading, CGFloat(item.depth) * SaveToLibraryLayout.treeIndentWidth)
        .frame(minHeight: SaveToLibraryLayout.treeConnectorHeight)
        .background(alignment: .leading) {
            SaveToLibraryTreeConnector(
                depth: item.depth,
                connectorContinuations: item.connectorContinuations
            )
            .allowsHitTesting(false)
        }
    }
}

private struct SaveToLibraryTreeConnector: View {
    var depth: Int
    var connectorContinuations: [Bool]

    var body: some View {
        if depth == 0 || connectorContinuations.isEmpty {
            Color.clear
                .frame(height: SaveToLibraryLayout.treeConnectorHeight)
        } else {
            SaveToLibraryTreeConnectorLevel(
                depth: depth,
                connectorContinuations: connectorContinuations
            )
            .stroke(
                Color.primary.opacity(SaveToLibraryLayout.treeConnectorOpacity),
                style: StrokeStyle(
                    lineWidth: SaveToLibraryLayout.treeConnectorLineWidth,
                    lineCap: .butt,
                    lineJoin: .round
                )
            )
            .frame(
                width: SaveToLibraryLayout.folderIconCenterX(depth: depth) + 1,
                height: SaveToLibraryLayout.treeConnectorHeight
            )
        }
    }
}

private struct SaveToLibraryTreeConnectorLevel: Shape {
    var depth: Int
    var connectorContinuations: [Bool]

    func path(in rect: CGRect) -> Path {
        Path { path in
            let midY = rect.midY
            let currentIconX = SaveToLibraryLayout.folderIconCenterX(depth: depth)
            let currentTargetX = currentIconX - SaveToLibraryLayout.treeConnectorTargetInset
            let parentIconX = SaveToLibraryLayout.folderIconCenterX(depth: depth - 1)
            let currentBranchContinues = connectorContinuations.indices.contains(depth - 1)
                ? connectorContinuations[depth - 1]
                : false

            if depth > 1 {
                for level in 0..<(depth - 1) where connectorContinuations.indices.contains(level) && connectorContinuations[level] {
                    let ancestorIconX = SaveToLibraryLayout.folderIconCenterX(depth: level)
                    path.move(to: CGPoint(x: ancestorIconX, y: rect.minY))
                    path.addLine(to: CGPoint(x: ancestorIconX, y: rect.maxY))
                }
            }

            path.move(to: CGPoint(x: parentIconX, y: rect.minY))
            path.addLine(to: CGPoint(x: parentIconX, y: currentBranchContinues ? rect.maxY : midY))
            path.move(to: CGPoint(x: parentIconX, y: midY))
            path.addLine(to: CGPoint(x: currentTargetX, y: midY))
        }
    }
}
