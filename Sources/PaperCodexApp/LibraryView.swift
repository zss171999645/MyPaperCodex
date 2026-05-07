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
    @State private var selectedPaperIDs: Set<String> = []
    @State private var lastSelectedPaperID: String?
    @State private var lastPaperRowClick: LibraryPaperRowClick?
    @State private var isShowingBulkMove = false
    @State private var isShowingBulkTag = false
    @State private var isConfirmingBulkDelete = false
    @State private var collapsedCategoryIDs: Set<String> = []
    @State private var categoryPendingManagement: PaperCodexCore.Category?
    @State private var categoryPendingDelete: PaperCodexCore.Category?
    @State private var tagPendingManagement: PaperTag?
    @State private var tagPendingDelete: PaperTag?
    @State private var watchedFolderPendingRemoval: WatchedFolder?
    @State private var noteTitle = ""
    @State private var noteBody = ""
    @State private var editingNoteID: String?
    @State private var selectedLibrarySurface: LibrarySurface = .papers
    @State private var selectedRecentSessionID: String?
    @AppStorage("PaperCodexLibrarySortOption") private var librarySortRawValue = LibrarySortOption.addedNewest.rawValue
    @AppStorage("PaperCodexLibrarySortAscending") private var librarySortAscending = false

    private var searchText: String {
        get { model.librarySearchText }
        nonmutating set { model.librarySearchText = newValue }
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { model.librarySearchText },
            set: { model.librarySearchText = $0 }
        )
    }

    private var selectedCategoryID: String? {
        get { model.librarySelectedCategoryID }
        nonmutating set { model.librarySelectedCategoryID = newValue }
    }

    private var selectedTagID: String? {
        get { model.librarySelectedTagID }
        nonmutating set { model.librarySelectedTagID = newValue }
    }

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
                let categories = categories(for: $0).map(\.name).joined(separator: " ")
                let tags = model.paperTagsByID[$0.id, default: []].map(\.name).joined(separator: " ")
                let year = $0.year.map(String.init) ?? ""
                return $0.title.localizedCaseInsensitiveContains(query)
                    || $0.authors.joined(separator: " ").localizedCaseInsensitiveContains(query)
                    || categories.localizedCaseInsensitiveContains(query)
                    || tags.localizedCaseInsensitiveContains(query)
                    || year.localizedCaseInsensitiveContains(query)
                    || ($0.sourceURL ?? "").localizedCaseInsensitiveContains(query)
            }
        }
        return result
    }

    private var sortedPapers: [Paper] {
        let option = LibrarySortOption(rawValue: librarySortRawValue) ?? .addedNewest
        return option.sorted(filteredPapers, ascending: librarySortAscending)
    }

    private var selectedPaperIDsInOrder: [String] {
        let selected = selectedPaperIDs
        return sortedPapers.map(\.id).filter { selected.contains($0) }
    }

    private var selectedReadablePaperIDsInOrder: [String] {
        selectedPaperIDsInOrder.filter { paperID in
            sortedPapers.first(where: { $0.id == paperID })?.isArxivImportPlaceholder == false
        }
    }

    private var selectedCategory: PaperCodexCore.Category? {
        selectedCategoryID.flatMap { categoryID in
            model.categories.first { $0.id == categoryID }
        }
    }

    private var selectedCategoryPaperIDsInOrder: [String] {
        guard let selectedCategoryID else {
            return []
        }
        let option = LibrarySortOption(rawValue: librarySortRawValue) ?? .addedNewest
        let categoryPapers = model.papers.filter { paper in
            !paper.isArxivImportPlaceholder
                && model.paperCategoryIDsByID[paper.id, default: []].contains(selectedCategoryID)
        }
        return option.sorted(categoryPapers, ascending: librarySortAscending).map(\.id)
    }

    private var selectedRecentSession: PaperSession? {
        if let selectedRecentSessionID,
           let session = model.recentSessions.first(where: { $0.id == selectedRecentSessionID }) {
            return session
        }
        return model.recentSessions.first
    }

    var body: some View {
        SidebarSplitLayout(minContentWidth: 840) {
            sidebar
        } content: {
            contentPane
        }
        .onChange(of: sortedPapers.map(\.id)) { _, _ in
            prunePaperSelection()
        }
        .onChange(of: model.recentSessions.map(\.id)) { _, _ in
            pruneRecentSessionSelection()
        }
        .alert("Delete selected papers?", isPresented: $isConfirmingBulkDelete) {
            Button("Delete", role: .destructive) {
                deleteSelectedPapers()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes \(selectedPaperIDs.count) papers from the local library and deletes app-managed PDF/cache files. This cannot be undone.")
        }
        .alert("Delete category?", isPresented: Binding(
            get: { categoryPendingDelete != nil },
            set: { if !$0 { categoryPendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let categoryPendingDelete {
                    model.deleteCategory(categoryPendingDelete.id)
                    selectedCategoryID = nil
                }
                categoryPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                categoryPendingDelete = nil
            }
        } message: {
            Text("This removes the category, its subcategories, and their assignments. Papers stay in the library.")
        }
        .alert("Delete tag?", isPresented: Binding(
            get: { tagPendingDelete != nil },
            set: { if !$0 { tagPendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let tagPendingDelete {
                    model.deleteTag(tagPendingDelete.id)
                    selectedTagID = nil
                }
                tagPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                tagPendingDelete = nil
            }
        } message: {
            Text("This removes the tag from every paper. Papers stay in the library.")
        }
        .alert("Remove watched folder?", isPresented: Binding(
            get: { watchedFolderPendingRemoval != nil },
            set: { if !$0 { watchedFolderPendingRemoval = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let watchedFolderPendingRemoval {
                    model.removeWatchedFolder(watchedFolderPendingRemoval)
                }
                watchedFolderPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                watchedFolderPendingRemoval = nil
            }
        } message: {
            Text("The folder will stop being scanned. Imported papers remain in the library.")
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
        .sheet(item: $categoryPendingManagement) { category in
            categoryManagementSheet(category)
        }
        .sheet(item: $tagPendingManagement) { tag in
            tagManagementSheet(tag)
        }
        .sheet(isPresented: $isShowingWatchedFolders) {
            WatchedFoldersSheet {
                presentWatchedFolderPanel()
            } onClose: {
                isShowingWatchedFolders = false
            } onRemove: { folder in
                watchedFolderPendingRemoval = folder
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
        .sheet(isPresented: $isShowingBulkMove) {
            LibraryBulkMoveSheet(
                categoryItems: flattenedCategoryItems(),
                selectedCount: selectedPaperIDs.count
            ) { categoryID in
                model.movePapers(selectedPaperIDsInOrder, toCategory: categoryID)
                selectedPaperIDs.removeAll()
                lastSelectedPaperID = nil
                if let categoryID {
                    selectedCategoryID = categoryID
                    selectedTagID = nil
                }
                isShowingBulkMove = false
            } onCancel: {
                isShowingBulkMove = false
            }
        }
        .sheet(isPresented: $isShowingBulkTag) {
            LibraryBulkTagSheet(
                tags: model.tags,
                selectedCount: selectedPaperIDs.count
            ) { tagIDs in
                model.assignPapers(selectedPaperIDsInOrder, toTags: tagIDs)
                selectedPaperIDs.removeAll()
                lastSelectedPaperID = nil
                isShowingBulkTag = false
            } onCancel: {
                isShowingBulkTag = false
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            dropPDFs(from: providers)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Paper Codex")
                .font(.paperCodexSystem(size: 24, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                filterButton(
                    title: "Recent Conversations",
                    systemImage: "clock",
                    isSelected: selectedLibrarySurface == .recentConversations
                ) {
                    selectedLibrarySurface = .recentConversations
                    selectedRecentSessionID = selectedRecentSessionID ?? model.recentSessions.first?.id
                }
                filterButton(
                    title: "Library",
                    systemImage: "books.vertical.fill",
                    isSelected: selectedLibrarySurface == .papers
                ) {
                    selectedLibrarySurface = .papers
                }
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

            ScrollView(.vertical) {
                sidebarLists
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .paperCodexSidebarChromePadding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var sidebarLists: some View {
        VStack(alignment: .leading, spacing: 18) {
            categorySidebarSection
            Divider()
            tagSidebarSection
        }
        .padding(.trailing, 2)
        .padding(.bottom, 8)
    }

    private var categorySidebarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sidebarHeader("Categories", systemImage: "folder") {
                startCreatingCategory(parentID: selectedCategoryID)
            }
            filterButton(
                title: "All Papers",
                systemImage: selectedCategoryID == nil && selectedTagID == nil ? "tray.full.fill" : "tray.full",
                isSelected: selectedLibrarySurface == .papers && selectedCategoryID == nil && selectedTagID == nil
            ) {
                selectedLibrarySurface = .papers
                selectedCategoryID = nil
                selectedTagID = nil
            }
            if model.categories.isEmpty {
                SidebarEmptyText("No categories")
            } else {
                ForEach(visibleCategoryItems()) { item in
                    CategorySidebarRow(
                        title: item.category.name,
                        countText: "\(paperCount(inCategory: item.category.id))",
                        systemImage: selectedCategoryID == item.category.id ? "folder.fill" : "folder",
                        isSelected: selectedLibrarySurface == .papers && selectedCategoryID == item.category.id,
                        depth: item.depth,
                        hasChildren: hasChildCategories(item.category.id),
                        isExpanded: !collapsedCategoryIDs.contains(item.category.id),
                        categoryDragPayload: categoryDragPayload(for: item.category),
                        onToggle: {
                            toggleCategoryCollapsed(item.category.id)
                        },
                        onSelect: {
                            selectedLibrarySurface = .papers
                            selectedCategoryID = item.category.id
                            selectedTagID = nil
                        },
                        onCreateChild: {
                            newCategoryParentID = item.category.id
                            startCreatingCategory(parentID: item.category.id)
                        },
                        onManage: {
                            categoryPendingManagement = item.category
                        },
                        onDropPapers: { paperIDs in
                            model.movePapers(paperIDs, toCategory: item.category.id)
                            selectedLibrarySurface = .papers
                            selectedCategoryID = item.category.id
                            selectedTagID = nil
                        },
                        onDropCategory: { droppedCategoryID in
                            guard droppedCategoryID != item.category.id else {
                                return
                            }
                            model.moveCategory(droppedCategoryID, toParent: item.category.id)
                        }
                    )
                }
            }
        }
    }

    private var tagSidebarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sidebarHeader("Tags", systemImage: "tag") {
                isCreatingTag = true
            }
            if model.tags.isEmpty {
                SidebarEmptyText("No tags")
            } else {
                ForEach(model.tags) { tag in
                    TagSidebarRow(
                        title: tag.name,
                        countText: "\(paperCount(forTag: tag.id))",
                        isSelected: selectedLibrarySurface == .papers && selectedTagID == tag.id
                    ) {
                        selectedLibrarySurface = .papers
                        selectedTagID = tag.id
                        selectedCategoryID = nil
                    } onManage: {
                        tagPendingManagement = tag
                    }
                }
            }
        }
    }

    private var contentPane: some View {
        HSplitView {
            primaryContentPane
                .padding(.top, LibraryLayout.splitPaneTopInset)
                .frame(minWidth: 500)
            secondaryContentPane
                .padding(.top, LibraryLayout.splitPaneTopInset)
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
        }
    }

    @ViewBuilder
    private var primaryContentPane: some View {
        switch selectedLibrarySurface {
        case .papers:
            paperList
        case .recentConversations:
            RecentConversationsContent(
                sessions: model.recentSessions,
                papersBySessionID: model.recentSessionPapersByID,
                selectedSessionID: Binding(
                    get: { selectedRecentSessionID ?? model.recentSessions.first?.id },
                    set: { selectedRecentSessionID = $0 }
                ),
                onOpen: { session in
                    model.openRecentSession(session)
                }
            )
        }
    }

    @ViewBuilder
    private var secondaryContentPane: some View {
        switch selectedLibrarySurface {
        case .papers:
            inspector
        case .recentConversations:
            RecentConversationDetailPanel(
                session: selectedRecentSession,
                papers: selectedRecentSession.map { model.papersForSession($0) } ?? [],
                onOpen: { session in
                    model.openRecentSession(session)
                }
            )
        }
    }

    private var paperList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("Library")
                    .font(.paperCodexSystem(size: 28, weight: .semibold))
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
                        Label {
                            Text(LocalizedStringKey(option.title))
                        } icon: {
                            Image(systemName: option.systemImage)
                        }
                        .tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 142)
                .help("Sort Library")
                sortDirectionButton
                Button {
                    presentPDFImportPanel()
                } label: {
                    Label("Import PDF", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if let selectedCategory {
                folderConversationActions(for: selectedCategory)
            }

            HStack(spacing: 8) {
                TextField("Search title, author, tag, category, year, or source", text: searchTextBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.paperCodexSystem(size: 15))
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear Search")
                }
            }

            if selectedCategoryID != nil || selectedTagID != nil || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    searchText = ""
                    selectedCategoryID = nil
                    selectedTagID = nil
                } label: {
                    Label("Clear Filters", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
            }

            if sortedPapers.isEmpty {
                ContentUnavailableView("No Papers", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(sortedPapers) { paper in
                            PaperRow(
                                paper: paper,
                                categories: categories(for: paper),
                                tags: model.paperTagsByID[paper.id, default: []],
                                thumbnailURLs: model.paperThumbnailURLsByID[paper.id, default: []],
                                isImportPlaceholder: paper.isArxivImportPlaceholder,
                                placeholderDetail: model.arxivImportPlaceholderDetail(for: paper),
                                isSelected: model.selectedLibraryPaper?.id == paper.id,
                                isMultiSelected: selectedPaperIDs.contains(paper.id),
                                onToggleStar: {
                                    model.togglePaperStar(paper)
                                },
                                onRead: {
                                    model.openPaper(paper)
                                }
                            )
                            .contentShape(Rectangle())
                            .onDrag {
                                NSItemProvider(object: paperDragPayload(for: paper) as NSString)
                            } preview: {
                                PaperDragPreview(
                                    paper: paper,
                                    selectedCount: dragPreviewPaperIDs(for: paper).count
                                )
                            }
                            .onTapGesture {
                                handlePaperRowClick(paper)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .overlay(alignment: .top) {
                    bulkActionBarOverlay
                }
            }
        }
        .padding(24)
    }

    private var bulkActionBarOverlay: some View {
        Group {
            if selectedPaperIDs.count > 1 {
                BulkLibraryActionBar(
                    selectedCount: selectedPaperIDs.count,
                    canMove: true,
                    canTag: !model.tags.isEmpty,
                    canOpenConversation: !selectedReadablePaperIDsInOrder.isEmpty,
                    onRead: openSelectedPapersForReading,
                    onChat: openSelectedPapersForChat,
                    onMove: {
                        isShowingBulkMove = true
                    },
                    onTag: {
                        isShowingBulkTag = true
                    },
                    onDelete: {
                        isConfirmingBulkDelete = true
                    },
                    onClear: {
                        selectedPaperIDs.removeAll()
                        lastSelectedPaperID = nil
                    }
                )
                .padding(.horizontal, 10)
                .padding(.top, LibraryLayout.bulkActionBarOverlayYOffset)
                .opacity(LibraryLayout.bulkActionBarOverlayOpacity)
                .transition(.move(edge: .top).combined(with: .opacity))
                .shadow(color: Color.black.opacity(0.12), radius: 14, y: 5)
            }
        }
        .animation(.easeOut(duration: 0.16), value: selectedPaperIDs.count > 1)
    }

    private func folderConversationActions(for category: PaperCodexCore.Category) -> some View {
        HStack(spacing: 10) {
            Label(category.name, systemImage: "folder.fill")
                .font(.paperCodexSystem(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(selectedCategoryPaperIDsInOrder.count) papers")
                .font(.paperCodexSystem(size: 12.5))
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                model.openPapersForReading(selectedCategoryPaperIDsInOrder)
            } label: {
                Label("Read", systemImage: "book")
            }
            .disabled(selectedCategoryPaperIDsInOrder.isEmpty)
            Button {
                model.openPapersForChat(selectedCategoryPaperIDsInOrder)
            } label: {
                Label("Chat", systemImage: "text.bubble")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCategoryPaperIDsInOrder.isEmpty)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var sortDirectionButton: some View {
        Button {
            librarySortAscending.toggle()
        } label: {
            Image(systemName: librarySortAscending ? "arrow.up" : "arrow.down")
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.bordered)
        .help(librarySortAscending ? "Ascending" : "Descending")
        .accessibilityLabel(librarySortAscending ? "Sort Ascending" : "Sort Descending")
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Paper Details")
                .font(.paperCodexSystem(size: 20, weight: .semibold))

            if let paper = model.selectedLibraryPaper {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                Text(paper.title)
                                    .font(.headline)
                                Spacer(minLength: 8)
                                Button {
                                    model.togglePaperStar(paper)
                                } label: {
                                    Image(systemName: paper.isStarred ? "star.fill" : "star")
                                        .foregroundStyle(paper.isStarred ? Color.yellow : Color.secondary)
                                }
                                .buttonStyle(.borderless)
                                .disabled(paper.isArxivImportPlaceholder)
                                .help(paper.isStarred ? "Remove Star" : "Star Paper")
                                .accessibilityLabel(paper.isStarred ? "Remove Star" : "Star Paper")
                            }
                            Text(paper.isArxivImportPlaceholder ? model.arxivImportPlaceholderDetail(for: paper) : (paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", ")))
                                .foregroundStyle(.secondary)
                            Text(paper.isArxivImportPlaceholder ? (paper.sourceURL ?? paper.title) : paper.filePath)
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
                        .disabled(paper.isArxivImportPlaceholder)

                        Divider()
                        categoryAssignments(for: paper)
                        Divider()
                        tagAssignments(for: paper)
                        Divider()
                        paperNotesSection(for: paper)
                    }
                    .padding(.trailing, 4)
                    .onAppear {
                        model.loadPaperNotes(for: paper)
                    }
                    .onChange(of: paper.id) { _, _ in
                        model.loadPaperNotes(for: paper)
                    }
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

    private func paperNotesSection(for paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Notes", systemImage: "note.text")
                    .font(.headline)
                Spacer()
                if editingNoteID != nil {
                    Button("New") {
                        clearNoteDraft()
                    }
                    .buttonStyle(.borderless)
                }
            }

            let notes = model.paperNotesByID[paper.id, default: []]
            if notes.isEmpty {
                SidebarEmptyText("No notes")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(notes) { note in
                        PaperNoteRow(note: note) {
                            editingNoteID = note.id
                            noteTitle = note.title
                            noteBody = note.bodyMarkdown
                        } onDelete: {
                            model.deleteNote(note)
                            if editingNoteID == note.id {
                                clearNoteDraft()
                            }
                        }
                    }
                }
            }

            TextField("Note title", text: $noteTitle)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $noteBody)
                .font(.paperCodexSystem(size: 12.5))
                .frame(minHeight: 72)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7))
            HStack {
                Button {
                    model.saveNote(paperID: paper.id, noteID: editingNoteID, title: noteTitle, bodyMarkdown: noteBody)
                    clearNoteDraft()
                } label: {
                    Label(editingNoteID == nil ? "Add Note" : "Save Note", systemImage: "checkmark")
                }
                .buttonStyle(.bordered)
                .disabled(noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if editingNoteID != nil {
                    Button("Cancel") {
                        clearNoteDraft()
                    }
                    .buttonStyle(.borderless)
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

    private func handlePaperRowClick(_ paper: Paper) {
        let modifiers = NSEvent.modifierFlags.intersection([.command, .shift])
        let canOpenOnSecondClick = modifiers.isEmpty
        let clickedAt = Date()
        handlePaperRowTap(paper)

        guard canOpenOnSecondClick else {
            lastPaperRowClick = nil
            return
        }

        if let lastPaperRowClick,
           lastPaperRowClick.paperID == paper.id,
           clickedAt.timeIntervalSince(lastPaperRowClick.clickedAt) <= 0.38,
           !paper.isArxivImportPlaceholder {
            model.openPaper(paper)
            self.lastPaperRowClick = nil
        } else {
            lastPaperRowClick = LibraryPaperRowClick(paperID: paper.id, clickedAt: clickedAt)
        }
    }

    private func handlePaperRowTap(_ paper: Paper) {
        let modifiers = NSEvent.modifierFlags.intersection([.command, .shift])
        if modifiers.contains(.shift) {
            selectPaperRange(through: paper)
        } else if modifiers.contains(.command) {
            togglePaperSelection(paper)
        } else {
            clearPaperMultiSelection()
            lastSelectedPaperID = paper.id
            model.selectLibraryPaper(paper)
        }
    }

    private func togglePaperSelection(_ paper: Paper) {
        var nextSelection = seedSelectionForCommandToggle(startingWith: paper)
        if nextSelection.contains(paper.id) {
            nextSelection.remove(paper.id)
        } else {
            nextSelection.insert(paper.id)
        }
        applyPaperSelection(nextSelection, focusedPaper: paper)
    }

    private func seedSelectionForCommandToggle(startingWith paper: Paper) -> Set<String> {
        guard selectedPaperIDs.isEmpty else {
            return selectedPaperIDs
        }
        guard let focusedPaper = model.selectedLibraryPaper,
              sortedPapers.contains(where: { $0.id == focusedPaper.id }) else {
            return []
        }
        return [focusedPaper.id]
    }

    private func applyPaperSelection(_ paperIDs: Set<String>, focusedPaper: Paper) {
        let visibleIDs = Set(sortedPapers.map(\.id))
        let visibleSelection = paperIDs.intersection(visibleIDs)
        if visibleSelection.count > 1 {
            selectedPaperIDs = visibleSelection
            lastSelectedPaperID = focusedPaper.id
            model.selectLibraryPaper(focusedPaper)
            return
        }

        clearPaperMultiSelection()
        if let remainingID = visibleSelection.first,
           let remainingPaper = sortedPapers.first(where: { $0.id == remainingID }) {
            lastSelectedPaperID = remainingID
            model.selectLibraryPaper(remainingPaper)
        } else if visibleIDs.contains(focusedPaper.id) {
            lastSelectedPaperID = focusedPaper.id
            model.selectLibraryPaper(focusedPaper)
        } else {
            lastSelectedPaperID = nil
            model.selectedLibraryPaper = nil
        }
    }

    private func clearPaperMultiSelection() {
        selectedPaperIDs.removeAll()
    }

    private func selectPaperRange(through paper: Paper) {
        let visibleIDs = sortedPapers.map(\.id)
        guard let currentIndex = visibleIDs.firstIndex(of: paper.id) else {
            togglePaperSelection(paper)
            return
        }
        let anchorID = lastSelectedPaperID ?? paper.id
        guard let anchorIndex = visibleIDs.firstIndex(of: anchorID) else {
            applyPaperSelection([paper.id], focusedPaper: paper)
            return
        }
        let lower = min(anchorIndex, currentIndex)
        let upper = max(anchorIndex, currentIndex)
        applyPaperSelection(Set(visibleIDs[lower...upper]), focusedPaper: paper)
    }

    private func prunePaperSelection() {
        let visibleIDs = Set(sortedPapers.map(\.id))
        selectedPaperIDs = selectedPaperIDs.intersection(visibleIDs)
        if selectedPaperIDs.count < 2 {
            clearPaperMultiSelection()
        }
        if let lastSelectedPaperID, !selectedPaperIDs.isEmpty, !selectedPaperIDs.contains(lastSelectedPaperID) {
            self.lastSelectedPaperID = selectedPaperIDsInOrder.last
        }
    }

    private func pruneRecentSessionSelection() {
        if let selectedRecentSessionID,
           model.recentSessions.contains(where: { $0.id == selectedRecentSessionID }) {
            return
        }
        selectedRecentSessionID = model.recentSessions.first?.id
    }

    private func deleteSelectedPapers() {
        let paperIDs = selectedPaperIDsInOrder
        guard !paperIDs.isEmpty else {
            return
        }
        model.deletePapers(paperIDs)
        selectedPaperIDs.removeAll()
        lastSelectedPaperID = nil
    }

    private func openSelectedPapersForReading() {
        let paperIDs = selectedReadablePaperIDsInOrder
        guard !paperIDs.isEmpty else {
            return
        }
        model.openPapersForReading(paperIDs)
    }

    private func openSelectedPapersForChat() {
        let paperIDs = selectedReadablePaperIDsInOrder
        guard !paperIDs.isEmpty else {
            return
        }
        model.openPapersForChat(paperIDs)
    }

    private func clearNoteDraft() {
        editingNoteID = nil
        noteTitle = ""
        noteBody = ""
    }

    private func toggleCategoryCollapsed(_ categoryID: String) {
        if collapsedCategoryIDs.contains(categoryID) {
            collapsedCategoryIDs.remove(categoryID)
        } else {
            collapsedCategoryIDs.insert(categoryID)
        }
    }

    private func hasChildCategories(_ categoryID: String) -> Bool {
        model.categories.contains { $0.parentID == categoryID }
    }

    private func paperCount(inCategory categoryID: String) -> Int {
        model.paperCategoryIDsByID.values.filter { $0.contains(categoryID) }.count
    }

    private func paperCount(forTag tagID: String) -> Int {
        model.paperTagsByID.values.filter { tags in
            tags.contains { $0.id == tagID }
        }.count
    }

    private func dropPDFs(from providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else {
            return false
        }
        for provider in fileProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let itemURL = item as? URL {
                    url = itemURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let nsURL = item as? NSURL {
                    url = nsURL as URL
                } else {
                    url = nil
                }
                guard let url else {
                    return
                }
                DispatchQueue.main.async {
                    model.importPDFs(from: [url])
                }
            }
        }
        return true
    }

    private func paperIDsForDrag(startingWith paper: Paper) -> [String] {
        if selectedPaperIDs.count > 1, selectedPaperIDs.contains(paper.id) {
            return selectedPaperIDsInOrder
        }
        return [paper.id]
    }

    private func dragPreviewPaperIDs(for paper: Paper) -> [String] {
        paperIDsForDrag(startingWith: paper)
    }

    private func paperDragPayload(for paper: Paper) -> String {
        paperIDsForDrag(startingWith: paper).joined(separator: "\n")
    }

    private func categoryDragPayload(for category: PaperCodexCore.Category) -> String {
        "\(LibraryLayout.categoryDragPayloadPrefix)\(category.id)"
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

    private func visibleCategoryItems(parentID: String? = nil, depth: Int = 0) -> [CategoryListItem] {
        model.categories
            .filter { $0.parentID == parentID }
            .sorted { left, right in
                if left.sortOrder == right.sortOrder {
                    return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
                }
                return left.sortOrder < right.sortOrder
            }
            .flatMap { category in
                let children = collapsedCategoryIDs.contains(category.id) ? [] : visibleCategoryItems(parentID: category.id, depth: depth + 1)
                return [CategoryListItem(category: category, depth: depth)] + children
            }
    }

    private func categoryManagementSheet(_ category: PaperCodexCore.Category) -> some View {
        CategoryManagementSheet(
            category: category,
            categoryItems: flattenedCategoryItems().filter { $0.category.id != category.id },
            onSave: { name, parentID in
                model.updateCategory(category.id, name: name, parentID: parentID)
                categoryPendingManagement = nil
            },
            onDelete: {
                categoryPendingManagement = nil
                categoryPendingDelete = category
            },
            onCancel: {
                categoryPendingManagement = nil
            }
        )
    }

    private func tagManagementSheet(_ tag: PaperTag) -> some View {
        TagManagementSheet(
            tag: tag,
            onSave: { name in
                model.updateTag(tag.id, name: name)
                tagPendingManagement = nil
            },
            onDelete: {
                tagPendingManagement = nil
                tagPendingDelete = tag
            },
            onCancel: {
                tagPendingManagement = nil
            }
        )
    }
}

private struct WatchedFoldersSheet: View {
    @EnvironmentObject private var model: AppModel
    var onAdd: () -> Void
    var onClose: () -> Void
    var onRemove: (WatchedFolder) -> Void

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
                            onRemove(folder)
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
                .foregroundStyle(folderExists ? Color.accentColor : Color.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: folder.path).lastPathComponent)
                    .font(.paperCodexSystem(size: 13, weight: .medium))
                Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(lastScannedText)
                    .font(.caption2)
                    .foregroundStyle(folderExists ? Color.secondary.opacity(0.72) : Color.orange)
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
        guard folderExists else {
            return "Folder missing"
        }
        guard let date = folder.lastScannedAt else {
            return "Not scanned"
        }
        return "Scanned \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var folderExists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

private struct CategoryListItem: Identifiable {
    var category: PaperCodexCore.Category
    var depth: Int

    var id: String { category.id }
}

private struct LibraryPaperRowClick: Equatable {
    var paperID: String
    var clickedAt: Date
}

private enum LibraryLayout {
    static let splitPaneTopInset: CGFloat = 24
    static let bulkActionBarOverlayYOffset: CGFloat = 42
    static let bulkActionBarOverlayOpacity = 0.84
    static let categoryDropContentTypes: [UTType] = [.plainText]
    static let categoryDragPayloadPrefix = "papercodex-category-id:"

    static func droppedCategoryID(from payload: String) -> String? {
        guard payload.hasPrefix(categoryDragPayloadPrefix) else {
            return nil
        }
        let categoryID = String(payload.dropFirst(categoryDragPayloadPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return categoryID.isEmpty ? nil : categoryID
    }
}

private struct PaperRow: View {
    var paper: Paper
    var categories: [PaperCodexCore.Category]
    var tags: [PaperTag]
    var thumbnailURLs: [URL]
    var isImportPlaceholder: Bool
    var placeholderDetail: String
    var isSelected: Bool
    var isMultiSelected: Bool
    var onToggleStar: () -> Void
    var onRead: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ThumbnailStrip(urls: Array(thumbnailURLs.prefix(5)))
                .frame(width: 132, height: 54)
                .opacity(isImportPlaceholder ? 0.45 : 1)

            VStack(alignment: .leading, spacing: 7) {
                Text(paper.title)
                    .font(.headline)
                    .foregroundStyle(isImportPlaceholder ? .secondary : .primary)
                    .lineLimit(2)
                Text(isImportPlaceholder ? placeholderDetail : (paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", ")))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let arxivDisplayID {
                        SmallChip(title: arxivDisplayID, systemImage: "number")
                    }
                    ForEach(categories.prefix(2)) { category in
                        SmallChip(title: category.name, systemImage: "folder")
                    }
                    ForEach(tags.prefix(3)) { tag in
                        SmallChip(title: tag.name, systemImage: "tag")
                    }
                }
            }

            Spacer()

            Button(action: onToggleStar) {
                Image(systemName: paper.isStarred ? "star.fill" : "star")
                    .foregroundStyle(paper.isStarred ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(isImportPlaceholder)
            .help(paper.isStarred ? "Remove Star" : "Star Paper")
            .accessibilityLabel(paper.isStarred ? "Remove Star" : "Star Paper")

            Button(action: onRead) {
                Image(systemName: "book")
            }
            .buttonStyle(.borderless)
            .disabled(isImportPlaceholder)
            .help("Read")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 21)
        .background(rowBackground)
        .opacity(isImportPlaceholder ? 0.66 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(rowBorderColor, lineWidth: isMultiSelected ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: isHovering ? Color.black.opacity(0.08) : .clear, radius: 4, y: 1)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var arxivDisplayID: String? {
        paper.arxivImportPlaceholderCanonicalID
            ?? paper.sourceURL.flatMap(ArxivIDExtractor.firstCanonicalID(in:))
    }

    private var rowBackground: Color {
        if isMultiSelected {
            return Color.accentColor.opacity(0.16)
        }
        if isSelected {
            return Color.accentColor.opacity(0.10)
        }
        if isHovering {
            return Color(nsColor: .textBackgroundColor)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var rowBorderColor: Color {
        if isMultiSelected {
            return Color.accentColor.opacity(0.62)
        }
        if isSelected {
            return Color.accentColor.opacity(0.38)
        }
        if isHovering {
            return Color.primary.opacity(0.10)
        }
        return Color.clear
    }
}

private struct PaperDragPreview: View {
    var paper: Paper
    var selectedCount: Int = 1

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.paperCodexSystem(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(paper.title)
                    .font(.paperCodexSystem(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if selectedCount > 1 {
                    Text("\(selectedCount) papers")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 360, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
        )
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
            .font(.paperCodexSystem(size: 12.5, weight: .medium))
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
        Text(LocalizedStringKey(text))
            .foregroundStyle(.secondary)
            .padding(.vertical, 5)
    }
}

private struct RecentConversationsContent: View {
    var sessions: [PaperSession]
    var papersBySessionID: [String: [Paper]]
    @Binding var selectedSessionID: String?
    var onOpen: (PaperSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("Recent Conversations")
                    .font(.paperCodexSystem(size: 28, weight: .semibold))
                Spacer()
            }

            if sessions.isEmpty {
                ContentUnavailableView("No Conversations", systemImage: "text.bubble")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sessions) { session in
                            RecentConversationRow(
                                session: session,
                                papers: papersBySessionID[session.id, default: []],
                                isSelected: selectedSessionID == session.id,
                                onSelect: {
                                    selectedSessionID = session.id
                                },
                                onOpen: {
                                    onOpen(session)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(24)
    }
}

private struct RecentConversationRow: View {
    var session: PaperSession
    var papers: [Paper]
    var isSelected: Bool
    var onSelect: () -> Void
    var onOpen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Image(systemName: session.paperIDs.count > 1 ? "square.stack.3d.up.fill" : "doc.text")
                            .foregroundStyle(Color.accentColor)
                        Text(session.title)
                            .font(.paperCodexSystem(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(Self.relativeFormatter.localizedString(for: session.updatedAt, relativeTo: Date()))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    Text(detailText)
                        .font(.paperCodexSystem(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onOpen) {
                Image(systemName: "arrow.forward.circle")
                    .font(.paperCodexSystem(size: 18, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Open Session")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .help(session.title)
    }

    private var detailText: String {
        guard session.paperIDs.count > 1 else {
            return papers.first?.title ?? "Single paper"
        }
        let firstTitle = papers.first?.title ?? "Multiple papers"
        return "\(session.paperIDs.count) papers · \(firstTitle)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct RecentConversationDetailPanel: View {
    var session: PaperSession?
    var papers: [Paper]
    var onOpen: (PaperSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Conversation Details")
                .font(.paperCodexSystem(size: 20, weight: .semibold))

            if let session {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: session.paperIDs.count > 1 ? "square.stack.3d.up.fill" : "doc.text")
                                    .foregroundStyle(Color.accentColor)
                                Text(session.title)
                                    .font(.headline)
                                    .lineLimit(3)
                            }
                            Text("\(session.paperIDs.count) paper\(session.paperIDs.count == 1 ? "" : "s")")
                                .foregroundStyle(.secondary)
                            Text(Self.relativeFormatter.localizedString(for: session.updatedAt, relativeTo: Date()))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }

                        Button {
                            onOpen(session)
                        } label: {
                            Label("Open Session", systemImage: "arrow.forward.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Label("Papers", systemImage: "doc.on.doc")
                                .font(.headline)
                            if papers.isEmpty {
                                SidebarEmptyText("No papers")
                            } else {
                                ForEach(papers) { paper in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "doc.text")
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(paper.title)
                                                .font(.paperCodexSystem(size: 13, weight: .semibold))
                                                .lineLimit(2)
                                            Text(paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", "))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.trailing, 4)
                }
            } else {
                ContentUnavailableView("Select Conversation", systemImage: "text.bubble")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private enum LibrarySurface {
    case recentConversations
    case papers
}

private struct BulkLibraryActionBar: View {
    var selectedCount: Int
    var canMove: Bool
    var canTag: Bool
    var canOpenConversation: Bool
    var onRead: () -> Void
    var onChat: () -> Void
    var onMove: () -> Void
    var onTag: () -> Void
    var onDelete: () -> Void
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label("\(selectedCount) selected", systemImage: "checkmark.circle.fill")
                .font(.paperCodexSystem(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Spacer()
            Button(action: onRead) {
                Label("Read", systemImage: "book")
            }
            .disabled(!canOpenConversation)
            .help("Read selected papers together")
            Button(action: onChat) {
                Label("Chat", systemImage: "text.bubble")
            }
            .disabled(!canOpenConversation)
            .help("Chat with selected papers together")
            Button(action: onMove) {
                Label("Move", systemImage: "folder")
            }
            .disabled(!canMove)
            .help("Move selected papers to a folder")
            Button(action: onTag) {
                Label("Tag", systemImage: "tag")
            }
            .disabled(!canTag)
            .help("Add tags to selected papers")
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .help("Delete selected papers")
            Button(action: onClear) {
                Label("Clear", systemImage: "xmark.circle")
            }
            .help("Clear selection")
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct LibraryBulkMoveSheet: View {
    var categoryItems: [CategoryListItem]
    var selectedCount: Int
    var onMove: (String?) -> Void
    var onCancel: () -> Void

    @State private var targetCategoryID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Move Papers", systemImage: "folder")
                .font(.title3.weight(.semibold))
            Text("\(selectedCount) selected papers")
                .foregroundStyle(.secondary)
            Picker("Destination", selection: $targetCategoryID) {
                Text("No folder").tag("")
                ForEach(categoryItems) { item in
                    Text(String(repeating: "  ", count: item.depth) + item.category.name)
                        .tag(item.category.id)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button {
                    onMove(targetCategoryID.isEmpty ? nil : targetCategoryID)
                } label: {
                    Label("Move", systemImage: "arrow.right.folder")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}

private struct LibraryBulkTagSheet: View {
    var tags: [PaperTag]
    var selectedCount: Int
    var onApply: ([String]) -> Void
    var onCancel: () -> Void

    @State private var selectedTagIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Add Tags", systemImage: "tag")
                .font(.title3.weight(.semibold))
            Text("\(selectedCount) selected papers")
                .foregroundStyle(.secondary)
            if tags.isEmpty {
                ContentUnavailableView("No Tags", systemImage: "tag")
                    .frame(width: 380, height: 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(tags) { tag in
                        Button {
                            toggle(tag.id)
                        } label: {
                            Label(tag.name, systemImage: selectedTagIDs.contains(tag.id) ? "checkmark.circle.fill" : "circle")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedTagIDs.contains(tag.id) ? .accentColor : .secondary)
                    }
                }
                .frame(width: 420)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button {
                    onApply(Array(selectedTagIDs))
                } label: {
                    Label("Apply", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedTagIDs.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 470)
    }

    private func toggle(_ tagID: String) {
        if selectedTagIDs.contains(tagID) {
            selectedTagIDs.remove(tagID)
        } else {
            selectedTagIDs.insert(tagID)
        }
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

    func sorted(_ papers: [Paper], ascending: Bool) -> [Paper] {
        papers.sorted { left, right in
            if left.isStarred != right.isStarred {
                return left.isStarred
            }
            switch self {
            case .addedNewest:
                if left.importedAt != right.importedAt {
                    return ascending ? left.importedAt < right.importedAt : left.importedAt > right.importedAt
                }
                return titleComesBefore(left, right, ascending: true)
            case .title:
                return titleComesBefore(left, right, ascending: ascending)
            case .arxivID:
                return arxivIDComesBefore(left, right, ascending: ascending)
            }
        }
    }

    private func titleComesBefore(_ left: Paper, _ right: Paper, ascending: Bool) -> Bool {
        let titleComparison = left.title.localizedStandardCompare(right.title)
        if titleComparison != .orderedSame {
            return ascending ? titleComparison == .orderedAscending : titleComparison == .orderedDescending
        }
        return left.id < right.id
    }

    private func arxivIDComesBefore(_ left: Paper, _ right: Paper, ascending: Bool) -> Bool {
        let leftID = arxivID(for: left)
        let rightID = arxivID(for: right)
        switch (leftID, rightID) {
        case let (leftID?, rightID?):
            let comparison = leftID.localizedStandardCompare(rightID)
            if comparison != .orderedSame {
                return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
            }
            return titleComesBefore(left, right, ascending: true)
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return titleComesBefore(left, right, ascending: true)
        }
    }

    private func arxivID(for paper: Paper) -> String? {
        paper.arxivImportPlaceholderCanonicalID
            ?? paper.sourceURL.flatMap(ArxivIDExtractor.firstCanonicalID(in:))
    }
}

private struct LibraryArxivImportSheet: View {
    @EnvironmentObject private var model: AppModel
    var categoryItems: [CategoryListItem]
    var onClose: () -> Void

    @State private var inputText = ""
    @State private var targetCategoryID: String
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
            }

            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $inputText)
                    .font(.paperCodexSystem(size: 13, design: .monospaced))
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

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                Button {
                    let ids = parsedIDs
                    model.enqueueArxivIDsForLibrary(
                        ids,
                        categoryID: targetCategoryID.isEmpty ? nil : targetCategoryID
                    )
                    onClose()
                } label: {
                    Label("Add", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.borderedProminent)
                .disabled(parsedIDs.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 540)
        .onAppear {
            isInputFocused = true
        }
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
    @State private var isDropTargeted = false

    var title: String
    var countText: String
    var systemImage: String
    var isSelected: Bool
    var depth: Int
    var hasChildren: Bool
    var isExpanded: Bool
    var categoryDragPayload: String
    var onToggle: () -> Void
    var onSelect: () -> Void
    var onCreateChild: () -> Void
    var onManage: () -> Void
    var onDropPapers: ([String]) -> Void
    var onDropCategory: (String) -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 4) {
                CategoryDepthGuide(depth: depth)
                if hasChildren {
                    Button(action: onToggle) {
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
                SidebarRowButton(
                    title: title,
                    systemImage: systemImage,
                    selected: isSelected,
                    depth: 0,
                    trailingReserve: 70,
                    action: onSelect
                )
            }

            if isDropActive {
                Label("Drop", systemImage: "arrow.down.doc")
                    .font(.paperCodexSystem(size: 11, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .foregroundStyle(Color.accentColor)
                    .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                    .padding(.trailing, 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                HStack(spacing: 3) {
                    Text(countText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if isHovering || isSelected {
                        Button(action: onCreateChild) {
                            Image(systemName: "plus")
                                .font(.paperCodexSystem(size: 11, weight: .semibold))
                                .frame(width: 22, height: 22)
                                .foregroundStyle(Color.accentColor)
                                .background(Circle().fill(Color.accentColor.opacity(isHovering ? 0.16 : 0.10)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("New subcategory under \(title)")

                        Button(action: onManage) {
                            Image(systemName: "ellipsis")
                                .font(.paperCodexSystem(size: 11, weight: .bold))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("Manage \(title)")
                    }
                }
                .padding(.trailing, 6)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDropActive ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDropActive ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1.5)
        )
        .scaleEffect(isDropActive ? 1.02 : 1, anchor: .center)
        .animation(.easeOut(duration: 0.12), value: isDropActive)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onDrag {
            NSItemProvider(object: categoryDragPayload as NSString)
        }
        .onDrop(of: LibraryLayout.categoryDropContentTypes, isTargeted: $isDropTargeted) { providers in
            loadDroppedItems(from: providers)
        }
        .help("Drop papers or folders into \(title)")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }

    private var isDropActive: Bool {
        isDropTargeted
    }

    private func loadDroppedItems(from providers: [NSItemProvider]) -> Bool {
        let textProviders = providers.filter { $0.canLoadObject(ofClass: NSString.self) }
        guard !textProviders.isEmpty else {
            return false
        }
        for provider in textProviders {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let payload = (object as? NSString).map(String.init) else {
                    return
                }
                let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
                if let droppedCategoryID = LibraryLayout.droppedCategoryID(from: trimmedPayload) {
                    DispatchQueue.main.async {
                        onDropCategory(droppedCategoryID)
                    }
                    return
                }
                let paperIDs = trimmedPayload
                    .components(separatedBy: .whitespacesAndNewlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard !paperIDs.isEmpty else {
                    return
                }
                DispatchQueue.main.async {
                    onDropPapers(paperIDs)
                }
            }
        }
        return true
    }
}

private struct CategoryDepthGuide: View {
    var depth: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(depth, 0), id: \.self) { level in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.primary.opacity(level == depth - 1 ? 0.22 : 0.10))
                    .frame(width: 2, height: 24)
            }
        }
        .frame(width: CGFloat(max(depth, 0)) * 16, height: 28, alignment: .trailing)
    }
}

private struct TagSidebarRow: View {
    @State private var isHovering = false

    var title: String
    var countText: String
    var isSelected: Bool
    var onSelect: () -> Void
    var onManage: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            SidebarRowButton(
                title: title,
                systemImage: isSelected ? "tag.fill" : "tag",
                selected: isSelected,
                trailingReserve: 58,
                action: onSelect
            )
            HStack(spacing: 4) {
                Text(countText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                if isHovering || isSelected {
                    Button(action: onManage) {
                        Image(systemName: "ellipsis")
                            .font(.paperCodexSystem(size: 11, weight: .bold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Manage \(title)")
                }
            }
            .padding(.trailing, 6)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

private struct CategoryManagementSheet: View {
    var category: PaperCodexCore.Category
    var categoryItems: [CategoryListItem]
    var onSave: (String, String?) -> Void
    var onDelete: () -> Void
    var onCancel: () -> Void

    @State private var name: String
    @State private var parentID: String

    init(
        category: PaperCodexCore.Category,
        categoryItems: [CategoryListItem],
        onSave: @escaping (String, String?) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.category = category
        self.categoryItems = categoryItems
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _name = State(initialValue: category.name)
        _parentID = State(initialValue: category.parentID ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Manage Category", systemImage: "folder")
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
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    onSave(name, parentID.isEmpty ? nil : parentID)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 390)
    }
}

private struct TagManagementSheet: View {
    var tag: PaperTag
    var onSave: (String) -> Void
    var onDelete: () -> Void
    var onCancel: () -> Void

    @State private var name: String

    init(tag: PaperTag, onSave: @escaping (String) -> Void, onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.tag = tag
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _name = State(initialValue: tag.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Manage Tag", systemImage: "tag")
                .font(.title3.weight(.semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    onSave(name)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 340)
    }
}

private struct PaperNoteRow: View {
    var note: PaperNote
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title)
                        .font(.paperCodexSystem(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if !note.bodyMarkdown.isEmpty {
                        Text(note.bodyMarkdown)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Delete Note")
        }
        .padding(9)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
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
