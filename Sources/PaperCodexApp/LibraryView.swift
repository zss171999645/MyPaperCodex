import PaperCodexCore
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isImporting = false
    @State private var isCreatingCategory = false
    @State private var isCreatingTag = false
    @State private var newCategoryName = ""
    @State private var newCategoryParentID = ""
    @State private var newTagName = ""
    @State private var searchText = ""
    @State private var selectedCategoryID: String?
    @State private var selectedTagID: String?

    private var filteredPapers: [Paper] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = model.papers
        if let selectedCategoryID {
            result = result.filter { paper in
                model.paperCategoryIDsByID[paper.id, default: []].contains(selectedCategoryID)
            }
        }
        if let selectedTagID {
            result = result.filter { paper in
                model.paperTagsByID[paper.id, default: []].contains { $0.id == selectedTagID }
            }
        }
        if !query.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.authors.joined(separator: " ").localizedCaseInsensitiveContains(query)
            }
        }
        return result
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 250, idealWidth: 280, maxWidth: 340)
            HSplitView {
                paperList
                    .frame(minWidth: 520)
                inspector
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                model.importPDF(from: url)
            }
        }
        .sheet(isPresented: $isCreatingCategory) {
            CategoryEditorSheet(
                categoryItems: flattenedCategoryItems(),
                name: $newCategoryName,
                parentID: $newCategoryParentID
            ) { name, parentID in
                model.createCategory(name: name, parentID: parentID.isEmpty ? nil : parentID)
                newCategoryName = ""
                newCategoryParentID = ""
                isCreatingCategory = false
            } onCancel: {
                newCategoryName = ""
                newCategoryParentID = ""
                isCreatingCategory = false
            }
        }
        .sheet(isPresented: $isCreatingTag) {
            TagEditorSheet(name: $newTagName) { name in
                model.createTag(name: name)
                newTagName = ""
                isCreatingTag = false
            } onCancel: {
                newTagName = ""
                isCreatingTag = false
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Paper Codex")
                .font(.system(size: 24, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                sidebarHeader("Categories", systemImage: "folder") {
                    newCategoryParentID = selectedCategoryID ?? ""
                    isCreatingCategory = true
                }
                filterButton(
                    title: "All Papers",
                    systemImage: selectedCategoryID == nil && selectedTagID == nil ? "tray.full.fill" : "tray.full",
                    isSelected: selectedCategoryID == nil && selectedTagID == nil
                ) {
                    selectedCategoryID = nil
                    selectedTagID = nil
                }
                if model.categories.isEmpty {
                    SidebarEmptyText("No categories")
                } else {
                    ForEach(flattenedCategoryItems()) { item in
                        filterButton(
                            title: item.category.name,
                            systemImage: selectedCategoryID == item.category.id ? "folder.fill" : "folder",
                            isSelected: selectedCategoryID == item.category.id,
                            depth: item.depth
                        ) {
                            selectedCategoryID = item.category.id
                            selectedTagID = nil
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                sidebarHeader("Tags", systemImage: "tag") {
                    isCreatingTag = true
                }
                if model.tags.isEmpty {
                    SidebarEmptyText("No tags")
                } else {
                    ForEach(model.tags) { tag in
                        filterButton(
                            title: tag.name,
                            systemImage: selectedTagID == tag.id ? "tag.fill" : "tag",
                            isSelected: selectedTagID == tag.id
                        ) {
                            selectedTagID = tag.id
                            selectedCategoryID = nil
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(22)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var paperList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("Library")
                    .font(.system(size: 28, weight: .semibold))
                Spacer()
                Button {
                    isImporting = true
                } label: {
                    Label("Import PDF", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            TextField("Search title or author", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15))

            if selectedCategoryID != nil || selectedTagID != nil {
                Button {
                    selectedCategoryID = nil
                    selectedTagID = nil
                } label: {
                    Label("Clear Filter", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
            }

            if filteredPapers.isEmpty {
                ContentUnavailableView("No Papers", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredPapers) { paper in
                            PaperRow(
                                paper: paper,
                                categories: categories(for: paper),
                                tags: model.paperTagsByID[paper.id, default: []],
                                isSelected: model.selectedLibraryPaper?.id == paper.id
                            ) {
                                model.openPaper(paper)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selectLibraryPaper(paper)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(24)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Paper Details")
                .font(.system(size: 20, weight: .semibold))

            if let paper = model.selectedLibraryPaper {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(paper.title)
                                .font(.headline)
                            Text(paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", "))
                                .foregroundStyle(.secondary)
                            Text(paper.filePath)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }

                        Button {
                            model.openPaper(paper)
                        } label: {
                            Label("Read", systemImage: "book")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Divider()
                        categoryAssignments(for: paper)
                        Divider()
                        tagAssignments(for: paper)
                    }
                    .padding(.trailing, 4)
                }
            } else {
                ContentUnavailableView("Select Paper", systemImage: "sidebar.right")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func categoryAssignments(for paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Categories", systemImage: "folder")
                    .font(.headline)
                Spacer()
                Button {
                    newCategoryParentID = ""
                    isCreatingCategory = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New Category")
            }

            if model.categories.isEmpty {
                SidebarEmptyText("No categories")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(flattenedCategoryItems()) { item in
                        Toggle(isOn: Binding(
                            get: {
                                model.paperCategoryIDsByID[paper.id, default: []].contains(item.category.id)
                            },
                            set: { isAssigned in
                                model.setCategory(item.category.id, assigned: isAssigned, for: paper)
                            }
                        )) {
                            Text(item.category.name)
                                .padding(.leading, CGFloat(item.depth * 14))
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
        }
    }

    private func tagAssignments(for paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Tags", systemImage: "tag")
                    .font(.headline)
                Spacer()
                Button {
                    isCreatingTag = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New Tag")
            }

            if model.tags.isEmpty {
                SidebarEmptyText("No tags")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(model.tags) { tag in
                        let assigned = model.paperTagsByID[paper.id, default: []].contains { $0.id == tag.id }
                        TagToggleChip(tag: tag, isAssigned: assigned) {
                            model.setTag(tag.id, assigned: !assigned, for: paper)
                        }
                    }
                }
            }
        }
    }

    private func sidebarHeader(_ title: String, systemImage: String, onAdd: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New \(title.dropLast())")
        }
    }

    private func filterButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        depth: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, CGFloat(depth * 14))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func categories(for paper: Paper) -> [PaperCodexCore.Category] {
        let ids = Set(model.paperCategoryIDsByID[paper.id, default: []])
        return model.categories.filter { ids.contains($0.id) }
    }

    private func flattenedCategoryItems(parentID: String? = nil, depth: Int = 0) -> [CategoryListItem] {
        model.categories
            .filter { $0.parentID == parentID }
            .sorted { left, right in
                if left.sortOrder == right.sortOrder {
                    return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
                }
                return left.sortOrder < right.sortOrder
            }
            .flatMap { category in
                [CategoryListItem(category: category, depth: depth)]
                    + flattenedCategoryItems(parentID: category.id, depth: depth + 1)
            }
    }
}

private struct CategoryListItem: Identifiable {
    var category: PaperCodexCore.Category
    var depth: Int

    var id: String { category.id }
}

private struct PaperRow: View {
    var paper: Paper
    var categories: [PaperCodexCore.Category]
    var tags: [PaperTag]
    var isSelected: Bool
    var onRead: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 22))
                .foregroundStyle(.blue)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 7) {
                Text(paper.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ForEach(categories.prefix(2)) { category in
                        SmallChip(title: category.name, systemImage: "folder")
                    }
                    ForEach(tags.prefix(3)) { tag in
                        SmallChip(title: tag.name, systemImage: "tag")
                    }
                }
            }

            Spacer()

            Button(action: onRead) {
                Image(systemName: "book")
            }
            .buttonStyle(.borderless)
            .help("Read")
        }
        .padding(14)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SmallChip: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct TagToggleChip: View {
    var tag: PaperTag
    var isAssigned: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(tag.name, systemImage: isAssigned ? "checkmark.circle.fill" : "circle")
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(isAssigned ? .accentColor : .secondary)
    }
}

private struct SidebarEmptyText: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .padding(.vertical, 5)
    }
}

private struct CategoryEditorSheet: View {
    var categoryItems: [CategoryListItem]
    @Binding var name: String
    @Binding var parentID: String
    var onCreate: (String, String) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Category")
                .font(.title3.weight(.semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            Picker("Parent", selection: $parentID) {
                Text("Top Level").tag("")
                ForEach(categoryItems) { item in
                    Text(String(repeating: "  ", count: item.depth) + item.category.name)
                        .tag(item.category.id)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Create") {
                    onCreate(name, parentID)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 360)
    }
}

private struct TagEditorSheet: View {
    @Binding var name: String
    var onCreate: (String) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Tag")
                .font(.title3.weight(.semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Create") {
                    onCreate(name)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 320)
    }
}
