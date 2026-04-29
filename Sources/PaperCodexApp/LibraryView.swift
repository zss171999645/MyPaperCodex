import PaperCodexCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isShowingWatchedFolders = false
    @State private var isShowingArxivImport = false
    @State private var isCreatingCategory = false
    @State private var isCreatingTag = false
    @State private var newCategoryName = ""
    @State private var newCategoryParentID = ""
    @State private var newTagName = ""
    @State private var searchText = ""
    @State private var selectedCategoryID: String?
    @State private var selectedTagID: String?
    @AppStorage("PaperCodexLibrarySortOption") private var librarySortRawValue = LibrarySortOption.addedNewest.rawValue

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

    private var sortedPapers: [Paper] {
        let option = LibrarySortOption(rawValue: librarySortRawValue) ?? .addedNewest
        return option.sorted(filteredPapers)
    }

    var body: some View {
        SidebarSplitLayout(minContentWidth: 840) {
            sidebar
        } content: {
            HSplitView {
                paperList
                    .padding(.top, LibraryLayout.splitPaneTopInset)
                    .frame(minWidth: 500)
                inspector
                    .padding(.top, LibraryLayout.splitPaneTopInset)
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
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
        .sheet(isPresented: $isShowingWatchedFolders) {
            WatchedFoldersSheet {
                presentWatchedFolderPanel()
            } onClose: {
                isShowingWatchedFolders = false
            }
            .environmentObject(model)
        }
        .sheet(isPresented: $isShowingArxivImport) {
            LibraryArxivImportSheet(
                categoryItems: flattenedCategoryItems(),
                initialCategoryID: selectedCategoryID
            ) {
                isShowingArxivImport = false
            }
            .environmentObject(model)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Paper Codex")
                .font(.system(size: 24, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                filterButton(
                    title: "Library",
                    systemImage: "books.vertical.fill",
                    isSelected: true
                ) {}
                filterButton(
                    title: "Discover",
                    systemImage: "sparkle.magnifyingglass",
                    isSelected: false
                ) {
                    model.showDiscover()
                }
                filterButton(
                    title: "Settings",
                    systemImage: "gearshape",
                    isSelected: false
                ) {
                    model.showSettings()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                sidebarHeader("Categories", systemImage: "folder") {
                    startCreatingCategory(parentID: selectedCategoryID)
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
                        CategorySidebarRow(
                            title: item.category.name,
                            systemImage: selectedCategoryID == item.category.id ? "folder.fill" : "folder",
                            isSelected: selectedCategoryID == item.category.id,
                            depth: item.depth,
                            onSelect: {
                                selectedCategoryID = item.category.id
                                selectedTagID = nil
                            },
                            onCreateChild: {
                                newCategoryParentID = item.category.id
                                startCreatingCategory(parentID: item.category.id)
                            }
                        )
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
                    isShowingWatchedFolders = true
                } label: {
                    Label("Folders", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                Button {
                    isShowingArxivImport = true
                } label: {
                    Label("arXiv", systemImage: "number")
                }
                .buttonStyle(.bordered)
                Picker("Sort", selection: $librarySortRawValue) {
                    ForEach(LibrarySortOption.allCases) { option in
                        Label(option.title, systemImage: option.systemImage)
                            .tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 142)
                .help("Sort Library")
                Button {
                    presentPDFImportPanel()
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

            if sortedPapers.isEmpty {
                ContentUnavailableView("No Papers", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(sortedPapers) { paper in
                            PaperRow(
                                paper: paper,
                                categories: categories(for: paper),
                                tags: model.paperTagsByID[paper.id, default: []],
                                thumbnailURLs: model.paperThumbnailURLsByID[paper.id, default: []],
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
        SidebarRowButton(
            title: title,
            systemImage: systemImage,
            selected: isSelected,
            depth: depth,
            action: action
        )
    }

    private func startCreatingCategory(parentID: String?) {
        newCategoryParentID = parentID ?? ""
        isCreatingCategory = true
    }

    private func categories(for paper: Paper) -> [PaperCodexCore.Category] {
        let ids = Set(model.paperCategoryIDsByID[paper.id, default: []])
        return model.categories.filter { ids.contains($0.id) }
    }

    private func presentPDFImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import PDF"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        beginOpenPanel(panel) { url in
            model.importPDF(from: url)
        }
    }

    private func presentWatchedFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add Watched Folder"
        panel.prompt = "Add Folder"
        panel.allowedContentTypes = [.folder]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.resolvesAliases = true
        beginOpenPanel(panel) { url in
            model.addWatchedFolder(from: url)
        }
    }

    private func beginOpenPanel(_ panel: NSOpenPanel, onSelection: @escaping (URL) -> Void) {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else {
                    return
                }
                onSelection(url)
            }
        } else {
            panel.begin { response in
                guard response == .OK, let url = panel.url else {
                    return
                }
                onSelection(url)
            }
        }
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

private struct WatchedFoldersSheet: View {
    @EnvironmentObject private var model: AppModel
    var onAdd: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Watched Folders")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(action: onAdd) {
                    Label("Add Folder", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                Button {
                    model.scanWatchedFolders()
                } label: {
                    Label(model.isScanningWatchedFolders ? "Scanning" : "Scan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(model.watchedFolders.isEmpty || model.isScanningWatchedFolders)
            }

            if model.watchedFolders.isEmpty {
                ContentUnavailableView("No Folders", systemImage: "folder")
                    .frame(width: 520, height: 220)
            } else {
                List {
                    ForEach(model.watchedFolders) { folder in
                        WatchedFolderRow(folder: folder) {
                            model.removeWatchedFolder(folder)
                        }
                    }
                }
                .listStyle(.inset)
                .frame(width: 560, height: 260)
            }

            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 600)
    }
}

private struct WatchedFolderRow: View {
    var folder: WatchedFolder
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: folder.path).lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(lastScannedText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove Folder")
        }
        .padding(.vertical, 4)
    }

    private var lastScannedText: String {
        guard let date = folder.lastScannedAt else {
            return "Not scanned"
        }
        return "Scanned \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct CategoryListItem: Identifiable {
    var category: PaperCodexCore.Category
    var depth: Int

    var id: String { category.id }
}

private enum LibraryLayout {
    static let splitPaneTopInset: CGFloat = 24
}

private struct PaperRow: View {
    var paper: Paper
    var categories: [PaperCodexCore.Category]
    var tags: [PaperTag]
    var thumbnailURLs: [URL]
    var isSelected: Bool
    var onRead: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ThumbnailStrip(urls: Array(thumbnailURLs.prefix(5)))
                .frame(width: 132, height: 54)

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
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ThumbnailStrip: View {
    var urls: [URL]

    var body: some View {
        HStack(spacing: -18) {
            if urls.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .windowBackgroundColor))
                    Image(systemName: "doc.richtext")
                        .foregroundStyle(.blue)
                }
                .frame(width: 42, height: 54)
            } else {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    if let image = NSImage(contentsOf: url) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(2)
                            .frame(width: 42, height: 54)
                            .background(Color(nsColor: .textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .zIndex(Double(urls.count - index))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

private enum LibrarySortOption: String, CaseIterable, Identifiable {
    case addedNewest
    case title
    case arxivID

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addedNewest:
            "Added"
        case .title:
            "Title"
        case .arxivID:
            "arXiv ID"
        }
    }

    var systemImage: String {
        switch self {
        case .addedNewest:
            "clock.arrow.circlepath"
        case .title:
            "textformat"
        case .arxivID:
            "number"
        }
    }

    func sorted(_ papers: [Paper]) -> [Paper] {
        papers.sorted { left, right in
            switch self {
            case .addedNewest:
                if left.importedAt != right.importedAt {
                    return left.importedAt > right.importedAt
                }
                return titleComesBefore(left, right)
            case .title:
                return titleComesBefore(left, right)
            case .arxivID:
                return arxivIDComesBefore(left, right)
            }
        }
    }

    private func titleComesBefore(_ left: Paper, _ right: Paper) -> Bool {
        let titleComparison = left.title.localizedStandardCompare(right.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }
        return left.id < right.id
    }

    private func arxivIDComesBefore(_ left: Paper, _ right: Paper) -> Bool {
        let leftID = left.sourceURL.flatMap(ArxivIDExtractor.firstCanonicalID(in:))
        let rightID = right.sourceURL.flatMap(ArxivIDExtractor.firstCanonicalID(in:))
        switch (leftID, rightID) {
        case let (leftID?, rightID?):
            let comparison = leftID.localizedStandardCompare(rightID)
            if comparison != .orderedSame {
                return comparison == .orderedDescending
            }
            return titleComesBefore(left, right)
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return titleComesBefore(left, right)
        }
    }
}

private enum LibraryArxivImportStatus: Equatable {
    case queued
    case downloading
    case imported
    case alreadyInLibrary
    case failed(String)

    var title: String {
        switch self {
        case .queued:
            "Queued"
        case .downloading:
            "Downloading"
        case .imported:
            "Imported"
        case .alreadyInLibrary:
            "Already in Library"
        case .failed:
            "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .queued:
            "clock"
        case .downloading:
            "arrow.down.circle"
        case .imported:
            "checkmark.circle.fill"
        case .alreadyInLibrary:
            "checkmark.seal.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .queued:
            .secondary
        case .downloading:
            .accentColor
        case .imported, .alreadyInLibrary:
            .green
        case .failed:
            .red
        }
    }

    var detail: String? {
        if case let .failed(message) = self {
            return message
        }
        return nil
    }
}

private struct LibraryArxivImportRow: Identifiable, Equatable {
    var id: String { versionedID }
    var versionedID: String
    var canonicalID: String
    var title: String = ""
    var status: LibraryArxivImportStatus
}

private struct LibraryArxivImportSheet: View {
    @EnvironmentObject private var model: AppModel
    var categoryItems: [CategoryListItem]
    var onClose: () -> Void

    @State private var inputText = ""
    @State private var targetCategoryID: String
    @State private var rows: [LibraryArxivImportRow] = []
    @State private var isImporting = false
    @FocusState private var isInputFocused: Bool

    init(categoryItems: [CategoryListItem], initialCategoryID: String?, onClose: @escaping () -> Void) {
        self.categoryItems = categoryItems
        self.onClose = onClose
        _targetCategoryID = State(initialValue: initialCategoryID ?? "")
    }

    private var parsedIDs: [String] {
        ArxivIDExtractor.extractVersionedIDs(from: inputText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Add arXiv Papers", systemImage: "number")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Close", action: onClose)
                    .disabled(isImporting)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $inputText)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 110)
                    .focused($isInputFocused)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                if parsedIDs.isEmpty {
                    Text("Paste arXiv IDs, links, PDFs, or any text containing one or more IDs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(parsedIDs, id: \.self) { id in
                            Text(id)
                                .font(.caption.monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        }
                    }
                }
            }

            Picker("Folder", selection: $targetCategoryID) {
                Text("No folder").tag("")
                ForEach(categoryItems) { item in
                    Text(String(repeating: "  ", count: item.depth) + item.category.name)
                        .tag(item.category.id)
                }
            }

            if !rows.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rows) { row in
                            HStack(spacing: 8) {
                                Image(systemName: row.status.systemImage)
                                    .foregroundStyle(row.status.color)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.canonicalID)
                                        .font(.caption.monospaced().weight(.semibold))
                                    if !row.title.isEmpty {
                                        Text(row.title)
                                            .font(.caption)
                                            .lineLimit(1)
                                    }
                                    if let detail = row.status.detail {
                                        Text(detail)
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                Text(row.status.title)
                                    .font(.caption)
                                    .foregroundStyle(row.status.color)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                    .disabled(isImporting)
                Button {
                    Task {
                        await importParsedIDs()
                    }
                } label: {
                    if isImporting {
                        ProgressView()
                            .scaleEffect(0.72)
                    } else {
                        Label("Add", systemImage: "arrow.down.doc")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(parsedIDs.isEmpty || isImporting)
            }
        }
        .padding(22)
        .frame(width: 540)
        .onAppear {
            isInputFocused = true
        }
    }

    @MainActor
    private func importParsedIDs() async {
        let ids = parsedIDs
        rows = ids.map { id in
            LibraryArxivImportRow(
                versionedID: id,
                canonicalID: ArxivIDExtractor.canonicalID(from: id),
                status: .queued
            )
        }
        isImporting = true
        defer {
            isImporting = false
        }

        for id in ids {
            updateRow(id: id, status: .downloading)
            let outcome = await model.addArxivIDToLibrary(
                id,
                categoryID: targetCategoryID.isEmpty ? nil : targetCategoryID
            )
            switch outcome.state {
            case .imported:
                updateRow(id: id, title: outcome.title, status: .imported)
            case .alreadyInLibrary:
                updateRow(id: id, title: outcome.title, status: .alreadyInLibrary)
            case .failed:
                updateRow(id: id, status: .failed(outcome.message))
            }
        }
    }

    private func updateRow(id: String, title: String? = nil, status: LibraryArxivImportStatus) {
        guard let index = rows.firstIndex(where: { $0.versionedID == id }) else {
            return
        }
        if let title {
            rows[index].title = title
        }
        rows[index].status = status
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct CategorySidebarRow: View {
    @State private var isHovering = false

    var title: String
    var systemImage: String
    var isSelected: Bool
    var depth: Int
    var onSelect: () -> Void
    var onCreateChild: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            SidebarRowButton(
                title: title,
                systemImage: systemImage,
                selected: isSelected,
                depth: depth,
                trailingReserve: 30,
                action: onSelect
            )

            if isHovering || isSelected {
                Button(action: onCreateChild) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Color.accentColor)
                        .background(
                            Circle()
                                .fill(Color.accentColor.opacity(isHovering ? 0.16 : 0.10))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.accentColor.opacity(isHovering ? 0.40 : 0.24), lineWidth: 1)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .help("New subcategory under \(title)")
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

private struct CategoryEditorSheet: View {
    var categoryItems: [CategoryListItem]
    @Binding var name: String
    @Binding var parentID: String
    var onCreate: (String, String) -> Void
    var onCancel: () -> Void
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Category")
                .font(.title3.weight(.semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
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
        .onAppear {
            isNameFocused = true
        }
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
