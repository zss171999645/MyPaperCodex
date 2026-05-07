import PaperCodexCore
import SwiftUI

struct CollectionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedRowIDs: Set<String> = []
    @State private var isCreatingCollection = false
    @State private var isAddingColumn = false
    @State private var collectionPendingRename: PaperCollectionDocument?
    @State private var collectionPendingDelete: PaperCollectionDocument?

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
        VStack(alignment: .leading, spacing: 0) {
            collectionToolbar(collection)
            Divider()
            CollectionSpreadsheet(
                collection: collection,
                selectedRowIDs: $selectedRowIDs,
                onCellCommit: { rowID, columnID, value in
                    model.updateCollectionCell(
                        collectionID: collection.id,
                        rowID: rowID,
                        columnID: columnID,
                        value: value
                    )
                },
                onOpenPaper: { paperID in
                    if let paper = model.papers.first(where: { $0.id == paperID }) {
                        model.openPaper(paper)
                    }
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func collectionToolbar(_ collection: PaperCollectionDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.title)
                        .font(.paperCodexSystem(size: 26, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 10) {
                        Label("\(collection.rows.count) papers", systemImage: "doc.text")
                        Label("\(collection.columns.count) columns", systemImage: "rectangle.grid.3x2")
                        Text(model.collectionJSONPath(for: collection.id))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    collectionPendingRename = collection
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Rename Collection")
                Button {
                    model.revealCollectionSource(collection.id)
                } label: {
                    Image(systemName: "curlybraces.square")
                }
                .buttonStyle(.borderless)
                .help("Reveal collection.json")
                Button(role: .destructive) {
                    collectionPendingDelete = collection
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete Collection")
            }

            HStack(spacing: 10) {
                Button {
                    isAddingColumn = true
                } label: {
                    Label("Column", systemImage: "rectangle.badge.plus")
                }
                .buttonStyle(.bordered)

                Menu {
                    Button {
                        model.addPapers(
                            model.papers.filter { !$0.isArxivImportPlaceholder }.map(\.id),
                            toCollectionID: collection.id
                        )
                    } label: {
                        Label("All Library Papers", systemImage: "books.vertical")
                    }
                    Divider()
                    ForEach(model.categories) { category in
                        Button {
                            model.addCategory(category.id, toCollectionID: collection.id)
                        } label: {
                            Label(category.name, systemImage: "folder")
                        }
                    }
                } label: {
                    Label("Add Papers", systemImage: "plus")
                }
                .menuStyle(.button)

                Button {
                    let selectedPapers = model.papers(in: collection, rowIDs: selectedRowIDs.isEmpty ? nil : selectedRowIDs)
                    model.openPapersForChat(selectedPapers.map(\.id))
                } label: {
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

                Spacer()

                Label("Codex can edit the JSON source directly", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .controlSize(.small)
        }
        .padding(20)
    }

    private func navButton(title: String, systemImage: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        SidebarRowButton(title: title, systemImage: systemImage, selected: selected, action: action)
    }
}

private struct CollectionSpreadsheet: View {
    var collection: PaperCollectionDocument
    @Binding var selectedRowIDs: Set<String>
    var onCellCommit: (String, String, String) -> Void
    var onOpenPaper: (String) -> Void

    private var totalWidth: CGFloat {
        72 + collection.columns.reduce(CGFloat(0)) { $0 + CGFloat($1.width) }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(Array(collection.rows.enumerated()), id: \.element.id) { index, row in
                    CollectionTableRow(
                        index: index,
                        row: row,
                        columns: collection.columns,
                        isSelected: selectedRowIDs.contains(row.id),
                        onToggleSelection: {
                            toggle(row.id)
                        },
                        onOpenPaper: {
                            onOpenPaper(row.paperID)
                        },
                        onCellCommit: { columnID, value in
                            onCellCommit(row.id, columnID, value)
                        }
                    )
                }
            }
            .frame(width: max(totalWidth, 820), alignment: .topLeading)
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: selectedRowIDs.isEmpty ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(selectedRowIDs.isEmpty ? Color.secondary : Color.accentColor)
                Text("#")
                    .font(.paperCodexSystem(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72, height: 36, alignment: .leading)
            .padding(.horizontal, 10)
            .background(CollectionTableStyle.headerBackground)
            .overlay(CollectionGridLine(), alignment: .trailing)
            .onTapGesture {
                if selectedRowIDs.count == collection.rows.count {
                    selectedRowIDs.removeAll()
                } else {
                    selectedRowIDs = Set(collection.rows.map(\.id))
                }
            }

            ForEach(collection.columns) { column in
                HStack(spacing: 7) {
                    Image(systemName: column.valueKind.systemImage)
                        .foregroundStyle(column.isLocked ? Color.secondary : Color.accentColor)
                    Text(column.title)
                        .lineLimit(1)
                    if column.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.75))
                    }
                }
                .font(.paperCodexSystem(size: 12.5, weight: .semibold))
                .frame(width: CGFloat(column.width), height: 36, alignment: .leading)
                .padding(.horizontal, 10)
                .background(CollectionTableStyle.headerBackground)
                .overlay(CollectionGridLine(), alignment: .trailing)
            }
        }
        .overlay(CollectionGridLine(), alignment: .bottom)
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
    var onToggleSelection: () -> Void
    var onOpenPaper: () -> Void
    var onCellCommit: (String, String) -> Void

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
                CollectionTableCell(
                    value: row.values[column.id, default: ""],
                    column: column,
                    onOpenPaper: column.id == "paper_title" ? onOpenPaper : nil,
                    onCommit: { value in
                        onCellCommit(column.id, value)
                    }
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
    var onOpenPaper: (() -> Void)?
    var onCommit: (String) -> Void

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if column.isLocked {
                lockedContent
            } else {
                TextField(column.title, text: $draft)
                    .textFieldStyle(.plain)
                    .font(.paperCodexSystem(size: 13))
                    .focused($isFocused)
                    .onAppear {
                        draft = value
                    }
                    .onChange(of: value) { _, newValue in
                        if !isFocused {
                            draft = newValue
                        }
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused, draft != value {
                            onCommit(draft)
                        }
                    }
                    .onSubmit {
                        onCommit(draft)
                    }
            }
        }
    }

    @ViewBuilder
    private var lockedContent: some View {
        if column.valueKind == .tags || column.valueKind == .categories {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(splitChips(value), id: \.self) { chip in
                        Text(chip)
                            .font(.paperCodexSystem(size: 11.5, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
        } else if column.id == "paper_title", let onOpenPaper {
            Button(action: onOpenPaper) {
                Text(value.isEmpty ? "Untitled" : value)
                    .font(.paperCodexSystem(size: 13, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Open Paper")
        } else {
            Text(value.isEmpty ? " " : value)
                .font(.paperCodexSystem(size: 13))
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func splitChips(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
