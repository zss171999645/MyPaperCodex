import PaperCodexCore
import AppKit
import SwiftUI
import WebKit

private let chatComposerTextHeightDefaultsKey = "PaperCodexChatComposerTextHeight"
private let chatBottomFollowTolerance: CGFloat = 28

enum SessionPanelTab: Hashable {
    case chat
    case notes
}

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draftsByComposerKey: [String: String] = [:]
    @State private var isSendButtonHovered = false
    @State private var composerTextHeight = ChatComposerLayout.loadTextHeight()
    @State private var composerResizeStartHeight: CGFloat?
    @State private var sessionPendingRename: PaperSession?
    @State private var renameSessionTitle = ""
    @State private var selectedGeneratedImageURL: URL?
    @State private var isChatPinnedToBottom = true
    @State private var chatScrollViewportHeight: CGFloat = 0
    @State private var chatBottomAnchorY: CGFloat = .infinity

    var body: some View {
        VStack(spacing: 0) {
            sessionBar
            Divider()
            selectedPanelContent
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(item: $sessionPendingRename) { session in
            renameSessionSheet(session)
        }
        .onChange(of: model.selectedSessionPanelTab) { _, tab in
            guard tab == .notes, let paper = model.selectedPaper else {
                return
            }
            model.loadPaperNotes(for: paper)
        }
        .onChange(of: model.selectedPaper?.id) { _, _ in
            guard model.selectedSessionPanelTab == .notes, let paper = model.selectedPaper else {
                return
            }
            model.loadPaperNotes(for: paper)
        }
        .onChange(of: model.selectedSession?.id) { _, _ in
            selectedGeneratedImageURL = nil
        }
    }

    @ViewBuilder
    private var selectedPanelContent: some View {
        if model.usesObsidianCatalog {
            chatPanel
        } else {
        switch model.selectedSessionPanelTab {
        case .chat:
            chatPanel
        case .notes:
            SessionNotesPanel()
        }
        }
    }

    private var chatPanel: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.messages.isEmpty && visibleActiveCodexRun == nil {
                            ContentUnavailableView(
                                "No Messages",
                                systemImage: "text.bubble",
                                description: Text("Select text in the PDF, then ask Codex in this session. The selected source appears as a quoted reply.")
                            )
                            .padding(.top, 80)
                        } else {
                            ForEach(model.messages) { message in
                                MessageBubble(
                                    message: message,
                                    isBusy: isCurrentSessionSending,
                                    onCitation: { citationID in
                                        model.jumpToCitation(citationID)
                                    },
                                    onRetryFailure: { messageID in
                                        Task {
                                            await model.retryCodexFailure(messageID: messageID)
                                        }
                                    },
                                    onNewSession: {
                                        model.startFreshSessionFromCurrentPaperSet()
                                    },
                                    onGeneratedImagePreview: { url in
                                        selectedGeneratedImageURL = url
                                    }
                                )
                                .id(message.id)
                            }
                            if let activeCodexRun = visibleActiveCodexRun {
                                CodexRunBubble(run: activeCodexRun)
                                    .id("active-run")
                            }
                            Color.clear
                                .frame(height: 1)
                                .id("chat-bottom")
                                .background(
                                    GeometryReader { geometry in
                                        Color.clear.preference(
                                            key: ChatBottomAnchorPreferenceKey.self,
                                            value: geometry.frame(in: .named("chat-scroll")).maxY
                                        )
                                    }
                                )
                        }
                    }
                    .padding(16)
                }
                .coordinateSpace(name: "chat-scroll")
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ChatViewportHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                    }
                )
                .onPreferenceChange(ChatBottomAnchorPreferenceKey.self) { bottomAnchorY in
                    updateChatPinnedState(bottomAnchorY: bottomAnchorY)
                }
                .onPreferenceChange(ChatViewportHeightPreferenceKey.self) { viewportHeight in
                    updateChatPinnedState(viewportHeight: viewportHeight)
                }
                .onChange(of: model.messages.last?.id ?? "") { _, _ in
                    scrollToBottomIfPinned(proxy)
                }
                .onChange(of: visibleActiveCodexRun?.events.count ?? 0) { _, _ in
                    scrollToBottomIfPinned(proxy)
                }
                .onChange(of: model.selectedSession?.id) { _, _ in
                    isChatPinnedToBottom = true
                    scrollToBottom(proxy)
                }
                .onAppear {
                    isChatPinnedToBottom = true
                    scrollToBottom(proxy)
                }
            }
            composer
        }
        .overlay {
            if let selectedGeneratedImageURL {
                GeneratedImagePreviewOverlay(imageURL: selectedGeneratedImageURL) {
                    self.selectedGeneratedImageURL = nil
                }
                .zIndex(10)
            }
        }
    }

    private var visibleActiveCodexRun: ActiveCodexRun? {
        model.activeCodexRun(for: model.selectedSession?.id)
    }

    private var isCurrentSessionSending: Bool {
        model.isSessionSending(model.selectedSession?.id)
    }

    private var canEditComposer: Bool {
        !isCurrentSessionSending
    }

    private var trimmedDraft: String {
        currentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentDraft: String {
        draftsByComposerKey[composerDraftKey, default: ""]
    }

    private var composerDraftKey: String {
        let sessionID = model.selectedSession?.id ?? "no-session"
        if let session = model.selectedSession, session.paperIDs.count > 1 {
            return "multi|\(sessionID)"
        }
        let paperID = model.selectedPaper?.id ?? "no-paper"
        return "\(paperID)|\(sessionID)"
    }

    private var composerDraftBinding: Binding<String> {
        Binding(
            get: {
                draftsByComposerKey[composerDraftKey, default: ""]
            },
            set: { value in
                draftsByComposerKey[composerDraftKey] = value
            }
        )
    }

    private var canUseSendButton: Bool {
        if isCurrentSessionSending {
            return true
        }
        return !trimmedDraft.isEmpty
    }

    private var sessionBar: some View {
        HStack(spacing: 8) {
            Picker("Session Panel", selection: $model.selectedSessionPanelTab) {
                Label("Chat", systemImage: "text.bubble").tag(SessionPanelTab.chat)
                if !model.usesObsidianCatalog {
                    Label("Notes", systemImage: "note.text").tag(SessionPanelTab.notes)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 132)
            .help("Session Panel")

            Divider()
                .frame(height: 18)

            Picker("Session", selection: Binding(
                get: { model.selectedSession?.id ?? "" },
                set: { model.selectSession($0) }
            )) {
                ForEach(model.sessions) { session in
                    Text(sessionMenuTitle(session)).tag(session.id)
                }
            }
            .labelsHidden()
            .frame(minWidth: 120, maxWidth: .infinity)

            ReaderChatHeaderActionButton(title: "New", systemImage: "plus", tint: .blue) {
                model.newSessionButtonTapped()
            }

            ReaderChatHeaderActionButton(
                title: "Rename",
                systemImage: "pencil",
                tint: .gray,
                disabled: model.selectedSession == nil
            ) {
                if let session = model.selectedSession {
                    renameSessionTitle = session.title
                    sessionPendingRename = session
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .controlSize(.small)
    }

    private func sessionMenuTitle(_ session: PaperSession) -> String {
        guard session.paperIDs.count > 1 else {
            return session.title
        }
        return "\(session.title) · \(session.paperIDs.count) papers"
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }

    private func scrollToBottomIfPinned(_ proxy: ScrollViewProxy) {
        guard isChatPinnedToBottom else {
            return
        }
        scrollToBottom(proxy)
    }

    private func updateChatPinnedState(
        bottomAnchorY: CGFloat? = nil,
        viewportHeight: CGFloat? = nil
    ) {
        if let bottomAnchorY {
            chatBottomAnchorY = bottomAnchorY
        }
        if let viewportHeight {
            chatScrollViewportHeight = viewportHeight
        }
        guard chatScrollViewportHeight > 0, chatBottomAnchorY.isFinite else {
            return
        }
        isChatPinnedToBottom = chatBottomAnchorY <= chatScrollViewportHeight + chatBottomFollowTolerance
    }

    private func renameSessionSheet(_ session: PaperSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Rename Session", systemImage: "pencil")
                .font(.title3.weight(.semibold))
            TextField("Session title", text: $renameSessionTitle)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") {
                    sessionPendingRename = nil
                }
                Button("Save") {
                    model.renameSession(session, title: renameSessionTitle)
                    sessionPendingRename = nil
                }
                .buttonStyle(.borderedProminent)
                .disabled(renameSessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 380)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            composerTopDivider
            VStack(alignment: .leading, spacing: 8) {
                if let selection = model.currentSelection {
                    CurrentSelectionReplyCard(selection: selection) {
                        model.clearCurrentSelection()
                    }
                }

                QuickPromptLine(
                    prompts: model.quickPrompts,
                    diagnostic: model.codexDiagnostic,
                    modelOverride: model.codexModelOverride,
                    availableModelIDs: model.availableCodexModelIDs,
                    defaultModelID: model.codexDefaultModelID,
                    reasoningEffort: model.codexReasoningEffort,
                    onPrompt: { model.sendQuickPrompt($0) },
                    onModelOverride: { model.setCodexModelOverride($0) },
                    onReasoningEffort: { model.setCodexReasoningEffort($0) }
                ) {
                    Task {
                        await model.refreshCodexDiagnostic()
                        await model.refreshAvailableCodexModels()
                    }
                }

                HStack(alignment: .bottom, spacing: 8) {
                    ComposerTextView(
                        text: composerDraftBinding,
                        isEnabled: canEditComposer,
                        onSubmit: sendDraft
                    )
                        .frame(height: composerTextHeight)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Button {
                        if isCurrentSessionSending {
                            model.cancelActiveCodexRun()
                        } else {
                            sendDraft()
                        }
                    } label: {
                        Image(systemName: sendButtonIcon)
                            .font(.paperCodexSystem(size: 26))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(sendButtonColor)
                    .disabled(!canUseSendButton)
                    .onHover { isSendButtonHovered = $0 }
                    .help(sendButtonHelp)
                }
            }
            .padding(14)
        }
    }

    private var composerTopDivider: some View {
        WindowSafeComposerResizeHandle(
            onDragChanged: resizeComposerTextHeight,
            onDragEnded: finishComposerResize
        )
        .frame(maxWidth: .infinity)
        .frame(height: 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .help("Resize input")
    }

    private func resizeComposerTextHeight(translationY: CGFloat) {
        if composerResizeStartHeight == nil {
            composerResizeStartHeight = composerTextHeight
        }
        let nextHeight = (composerResizeStartHeight ?? composerTextHeight) + translationY
        composerTextHeight = ChatComposerLayout.clampedTextHeight(nextHeight)
    }

    private func finishComposerResize() {
        composerTextHeight = ChatComposerLayout.clampedTextHeight(composerTextHeight)
        ChatComposerLayout.saveTextHeight(composerTextHeight)
        composerResizeStartHeight = nil
    }

    private var sendButtonIcon: String {
        if isCurrentSessionSending {
            return isSendButtonHovered ? "xmark.circle.fill" : "hourglass.circle.fill"
        }
        return "arrow.up.circle.fill"
    }

    private var sendButtonColor: Color {
        if isCurrentSessionSending {
            return isSendButtonHovered ? .red : .blue
        }
        return .blue
    }

    private var sendButtonHelp: String {
        if isCurrentSessionSending {
            return "Stop Codex"
        }
        return "Send"
    }

    private func sendDraft() {
        let message = trimmedDraft
        guard !isCurrentSessionSending, !message.isEmpty else {
            return
        }
        draftsByComposerKey[composerDraftKey] = ""
        Task {
            await model.sendMessage(message)
        }
    }
}

private struct ChatBottomAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = .infinity

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChatViewportHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ReaderChatHeaderActionButton: View {
    @State private var isHovering = false

    var title: String
    var systemImage: String
    var tint: Color
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(LocalizedStringKey(title))
                    .lineLimit(1)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.paperCodexSystem(size: 11.5, weight: .semibold))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .foregroundStyle(disabled ? Color.secondary.opacity(0.55) : (isHovering ? tint : Color.primary.opacity(0.82)))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(disabled ? Color(nsColor: .controlBackgroundColor).opacity(0.55) : (isHovering ? tint.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(disabled ? Color.black.opacity(0.06) : (isHovering ? tint.opacity(0.38) : Color.black.opacity(0.10)), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(title)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.10)) {
                isHovering = hovering
            }
        }
    }
}

private struct SessionNotesPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var noteTitle = ""
    @State private var noteBody = ""
    @State private var editingNoteID: String?
    @State private var selectedNoteID: String?

    var body: some View {
        Group {
            if let paper = model.selectedPaper {
                VStack(spacing: 0) {
                    notesToolbar(for: paper)
                    Divider()
                    SessionNotesWorkspace(
                        paper: paper,
                        notes: model.paperNotesByID[paper.id, default: []],
                        selectedNoteID: $selectedNoteID,
                        noteTitle: $noteTitle,
                        noteBody: $noteBody,
                        editingNoteID: $editingNoteID,
                        onSelect: edit,
                        onNew: clearNoteDraft,
                        onSave: saveNote,
                        onDelete: deleteNote
                    )
                }
                .onAppear {
                    model.loadPaperNotes(for: paper)
                }
            } else {
                ContentUnavailableView("No Paper Selected", systemImage: "doc.text")
            }
        }
        .onChange(of: model.selectedPaper?.id) { _, _ in
            clearNoteDraft()
            if let paper = model.selectedPaper {
                model.loadPaperNotes(for: paper)
            }
        }
    }

    private func notesToolbar(for paper: Paper) -> some View {
        let notes = model.paperNotesByID[paper.id, default: []]
        return HStack(spacing: 10) {
            Label("Paper Notes", systemImage: "note.text")
                .font(.paperCodexSystem(size: 13.5, weight: .semibold))
            Text(paper.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text("\(notes.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .trailing)
            Button {
                clearNoteDraft()
            } label: {
                Label("New Note", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func edit(_ note: PaperNote) {
        selectedNoteID = note.id
        editingNoteID = note.id
        noteTitle = note.title
        noteBody = note.bodyMarkdown
    }

    private func saveNote(_ paper: Paper) {
        model.saveNote(paperID: paper.id, noteID: editingNoteID, title: noteTitle, bodyMarkdown: noteBody)
        clearNoteDraft()
    }

    private func deleteNote(_ note: PaperNote) {
        model.deleteNote(note)
        if editingNoteID == note.id {
            clearNoteDraft()
        } else if selectedNoteID == note.id {
            selectedNoteID = nil
        }
    }

    private func clearNoteDraft() {
        selectedNoteID = nil
        editingNoteID = nil
        noteTitle = ""
        noteBody = ""
    }
}

private struct SessionNotesWorkspace: View {
    var paper: Paper
    var notes: [PaperNote]
    @Binding var selectedNoteID: String?
    @Binding var noteTitle: String
    @Binding var noteBody: String
    @Binding var editingNoteID: String?
    var onSelect: (PaperNote) -> Void
    var onNew: () -> Void
    var onSave: (Paper) -> Void
    var onDelete: (PaperNote) -> Void

    var body: some View {
        HSplitView {
            noteList
                .frame(minWidth: 190, idealWidth: 240, maxWidth: 330, maxHeight: .infinity)
            noteEditor
                .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var noteList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onNew) {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("New Note")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if notes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.paperCodexSystem(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No notes")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(notes) { note in
                            SessionNoteListRow(
                                note: note,
                                isSelected: note.id == selectedNoteID,
                                onSelect: {
                                    onSelect(note)
                                },
                                onDelete: {
                                    onDelete(note)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var noteEditor: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(editingNoteID == nil ? "New Note" : "Edit Note", systemImage: "square.and.pencil")
                    .font(.paperCodexSystem(size: 13, weight: .semibold))
                Spacer()
                if editingNoteID != nil {
                    Button("Cancel") {
                        onNew()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            VStack(spacing: 10) {
                TextField("Note title", text: $noteTitle)
                    .textFieldStyle(.roundedBorder)

                TextEditor(text: $noteBody)
                    .font(.paperCodexSystem(size: 13))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )

                HStack {
                    Button {
                        onSave(paper)
                    } label: {
                        Label(editingNoteID == nil ? "Add Note" : "Save Note", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()

                    Text(paper.title)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SessionNoteListRow: View {
    var note: PaperNote
    var isSelected: Bool
    var onSelect: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(note.title)
                        .font(.paperCodexSystem(size: 12.8, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !note.bodyMarkdown.isEmpty {
                        Text(note.bodyMarkdown)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.paperCodexSystem(size: 11))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Delete Note")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(width: 3)
        }
        .contentShape(Rectangle())
    }
}

private enum ChatComposerLayout {
    static let minimumTextHeight: CGFloat = 72
    static let maximumTextHeight: CGFloat = 220
    static let defaultTextHeight: CGFloat = 96

    static func clampedTextHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, minimumTextHeight), maximumTextHeight)
    }

    static func loadTextHeight() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: chatComposerTextHeightDefaultsKey)
        guard stored > 0 else {
            return defaultTextHeight
        }
        return clampedTextHeight(CGFloat(stored))
    }

    static func saveTextHeight(_ height: CGFloat) {
        UserDefaults.standard.set(Double(clampedTextHeight(height)), forKey: chatComposerTextHeightDefaultsKey)
    }
}

private struct WindowSafeComposerResizeHandle: NSViewRepresentable {
    var onDragChanged: (CGFloat) -> Void
    var onDragEnded: () -> Void

    func makeNSView(context: Context) -> ResizeHandleView {
        let view = ResizeHandleView()
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ view: ResizeHandleView, context: Context) {
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
    }

    final class ResizeHandleView: NSView {
        var onDragChanged: (CGFloat) -> Void = { _ in }
        var onDragEnded: () -> Void = {}
        private var dragStartWindowY: CGFloat?
        private var isHovering = false
        private var trackingArea: NSTrackingArea?

        override var mouseDownCanMoveWindow: Bool {
            false
        }

        override var acceptsFirstResponder: Bool {
            true
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeUpDown)
        }

        override func mouseEntered(with event: NSEvent) {
            isHovering = true
            needsDisplay = true
            NSCursor.resizeUpDown.set()
        }

        override func mouseExited(with event: NSEvent) {
            isHovering = false
            needsDisplay = true
            NSCursor.arrow.set()
        }

        override func mouseDown(with event: NSEvent) {
            dragStartWindowY = event.locationInWindow.y
            window?.makeFirstResponder(self)
            NSCursor.resizeUpDown.set()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragStartWindowY else {
                return
            }
            onDragChanged(event.locationInWindow.y - dragStartWindowY)
        }

        override func mouseUp(with event: NSEvent) {
            dragStartWindowY = nil
            onDragEnded()
            needsDisplay = true
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil, isHovering {
                NSCursor.arrow.set()
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            let width: CGFloat = isHovering ? 58 : 44
            let rect = NSRect(
                x: bounds.midX - width / 2,
                y: bounds.midY - 2,
                width: width,
                height: 4
            )
            let color = isHovering
                ? NSColor.controlAccentColor.withAlphaComponent(0.68)
                : NSColor.secondaryLabelColor.withAlphaComponent(0.34)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        }
    }
}

private struct QuickPromptLine: View {
    var prompts: [QuickPrompt]
    var diagnostic: CodexDiagnostic?
    var modelOverride: String
    var availableModelIDs: [String]
    var defaultModelID: String
    var reasoningEffort: CodexReasoningEffort
    var onPrompt: (QuickPrompt) -> Void
    var onModelOverride: (String) -> Void
    var onReasoningEffort: (CodexReasoningEffort) -> Void
    var onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(prompts) { prompt in
                    Button(prompt.title) {
                        onPrompt(prompt)
                    }
                }
            } label: {
                Label("Quick Prompt", systemImage: "text.bubble")
                    .frame(minWidth: 138, alignment: .leading)
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            CodexStatusLine(
                diagnostic: diagnostic,
                modelOverride: modelOverride,
                availableModelIDs: availableModelIDs,
                defaultModelID: defaultModelID,
                reasoningEffort: reasoningEffort,
                onModelOverride: onModelOverride,
                onReasoningEffort: onReasoningEffort,
                onRefresh: onRefresh
            )
            .frame(maxWidth: 360)
        }
    }
}

private struct CodexStatusLine: View {
    var diagnostic: CodexDiagnostic?
    var modelOverride: String
    var availableModelIDs: [String]
    var defaultModelID: String
    var reasoningEffort: CodexReasoningEffort
    var onModelOverride: (String) -> Void
    var onReasoningEffort: (CodexReasoningEffort) -> Void
    var onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if shouldOfferCompatibleModel {
                Button("Use gpt-5.4-mini") {
                    onModelOverride("gpt-5.4-mini")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            Menu {
                Button {
                    onModelOverride("")
                } label: {
                    if modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(defaultModelLabel, systemImage: "checkmark")
                    } else {
                        Text(defaultModelLabel)
                    }
                }
                Divider()
                ForEach(availableModelIDs, id: \.self) { modelID in
                    Button {
                        onModelOverride(modelID)
                    } label: {
                        if modelID == modelOverride.trimmingCharacters(in: .whitespacesAndNewlines) {
                            Label(modelID, systemImage: "checkmark")
                        } else {
                            Text(modelID)
                        }
                    }
                }
            } label: {
                Label(modelLabel, systemImage: "slider.horizontal.3")
                    .labelStyle(.titleAndIcon)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .controlSize(.small)
            Menu {
                ForEach(CodexReasoningEffort.allCases, id: \.self) { effort in
                    Button {
                        onReasoningEffort(effort)
                    } label: {
                        if effort == reasoningEffort {
                            Label(effort.displayName, systemImage: "checkmark")
                        } else {
                            Text(effort.displayName)
                        }
                    }
                }
            } label: {
                Label(reasoningLabel, systemImage: "brain.head.profile")
                    .labelStyle(.titleAndIcon)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .controlSize(.small)
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Refresh Codex Status")
        }
        .help(detail)
    }

    private var title: String {
        guard let diagnostic else {
            return "Checking Codex"
        }
        if let version = diagnostic.version {
            return "\(diagnostic.title) · \(version)"
        }
        return diagnostic.title
    }

    private var detail: String {
        diagnostic?.detail ?? "Checking local Codex CLI."
    }

    private var modelLabel: String {
        let trimmed = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultModelLabel : trimmed
    }

    private var defaultModelLabel: String {
        let trimmed = defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Default" : "Default (\(trimmed))"
    }

    private var reasoningLabel: String {
        "Think \(reasoningEffort.displayName)"
    }

    private var shouldOfferCompatibleModel: Bool {
        diagnostic?.title == "Codex model incompatible"
            && modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var iconName: String {
        guard let diagnostic else {
            return "circle.dotted"
        }
        switch diagnostic.severity {
        case .ready:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .blocked:
            return "xmark.circle.fill"
        }
    }

    private var tint: Color {
        guard let diagnostic else {
            return .secondary
        }
        switch diagnostic.severity {
        case .ready:
            return .green
        case .warning:
            return .orange
        case .blocked:
            return .red
        }
    }
}

private struct CodexRunBubble: View {
    var run: ActiveCodexRun

    private var visibleEvents: [CodexRunEvent] {
        Array(run.events.filter { $0.kind == .thinking || $0.kind == .answer || $0.kind == .usage }.suffix(8))
    }

    private var tokenUsageSummary: String? {
        var aggregate = CodexTokenUsage()
        for event in run.events {
            if let tokenUsage = event.tokenUsage {
                aggregate.add(tokenUsage)
            }
        }
        return aggregate.isEmpty ? nil : aggregate.compactSummary
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Codex")
                        .font(.caption.weight(.semibold))
                    Text("Running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !visibleEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(visibleEvents) { event in
                            CodexRunEventRow(event: event)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer(minLength: 32)
        }
    }

    private var statusText: String {
        if let tokenUsageSummary {
            return tokenUsageSummary
        }
        return visibleEvents.isEmpty ? "Working" : "\(visibleEvents.count) update\(visibleEvents.count == 1 ? "" : "s")"
    }
}

private struct CodexRunEventRow: View {
    var event: CodexRunEvent
    @State private var isExpanded = false

    var body: some View {
        if event.kind == .terminal {
            DisclosureGroup(isExpanded: $isExpanded) {
                Text(event.detail)
                    .font(.paperCodexSystem(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } label: {
                eventHeader
            }
            .font(.caption)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                eventHeader
                Text(event.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(event.kind == .tool ? 3 : 2)
            }
        }
    }

    private var eventHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(event.displayTitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            if event.kind == .terminal, !isExpanded {
                Text(event.previewDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var iconName: String {
        switch event.kind {
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
            "chart.bar"
        case .warning:
            "exclamationmark.triangle"
        case .error:
            "xmark.octagon"
        case .raw:
            "doc.plaintext"
        }
    }

    private var tint: Color {
        switch event.kind {
        case .status:
            .blue
        case .thinking:
            .purple
        case .tool:
            .indigo
        case .terminal:
            .gray
        case .answer:
            .green
        case .usage:
            .indigo
        case .warning:
            .orange
        case .error:
            .red
        case .raw:
            .secondary
        }
    }
}

private struct MessageBubble: View {
    var message: ChatMessage
    var isBusy: Bool
    var onCitation: (String) -> Void
    var onRetryFailure: (String) -> Void
    var onNewSession: () -> Void
    var onGeneratedImagePreview: (URL) -> Void

    private var isUser: Bool {
        message.role == .user
    }

    private var parsed: ParsedCitationText {
        CitationParser.parse(message.content, maxVisibleCitations: isUser ? nil : 3)
    }

    private var parsedUserSource: ParsedUserSourceMessage {
        UserSourceAttachmentParser.parse(message.content)
    }

    private var userSourceAttachment: UserSourceAttachment? {
        isUser ? parsedUserSource.attachment : nil
    }

    private var failureNotice: CodexFailureNotice? {
        CodexFailureNotice.parse(message.content)
    }

    private var renderedMarkdown: String {
        if let failureNotice {
            return failureNotice.messageContent
        }
        if isUser {
            return parsedUserSource.visibleContent
        }
        return parsed.displayMarkdown
    }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 32)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(isUser ? "You" : "Codex")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let userSourceAttachment {
                    UserSourceReplyView(attachment: userSourceAttachment, onOpen: onCitation)
                }
                if !renderedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MarkdownMessageView(messageID: message.id, markdown: renderedMarkdown, onCitation: onCitation)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !isUser {
                    let imageURLs = generatedImageURLs(in: message.content)
                    if !imageURLs.isEmpty {
                        GeneratedImageGallery(urls: imageURLs, onPreview: onGeneratedImagePreview)
                    }
                }
                if failureNotice != nil {
                    HStack(spacing: 8) {
                        Button {
                            onRetryFailure(message.id)
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isBusy)

                        Button {
                            onNewSession()
                        } label: {
                            Label("New Session", systemImage: "plus.bubble")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isBusy)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(12)
            .background(isUser ? Color.blue.opacity(0.12) : Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            if !isUser {
                Spacer(minLength: 32)
            }
        }
    }
}

private func generatedImageURLs(in markdown: String) -> [URL] {
    let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif"]
    var urls: [URL] = []
    var seen: Set<String> = []
    for line in markdown.components(separatedBy: .newlines) {
        guard line.trimmingCharacters(in: .whitespaces).hasPrefix("!") else {
            continue
        }
        guard let open = line.range(of: "]("),
              let close = line[open.upperBound...].firstIndex(of: ")") else {
            continue
        }
        var raw = String(line[open.upperBound..<close])
        if raw.hasPrefix("file://"), let url = URL(string: raw) {
            raw = url.path
        }
        let url = URL(fileURLWithPath: raw)
        let path = url.standardizedFileURL.path
        guard supportedExtensions.contains(url.pathExtension.lowercased()),
              FileManager.default.fileExists(atPath: path),
              !seen.contains(path) else {
            continue
        }
        seen.insert(path)
        urls.append(url.standardizedFileURL)
    }
    return urls
}

private struct GeneratedImageGallery: View {
    var urls: [URL]
    var onPreview: (URL) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(urls, id: \.path) { url in
                    Button {
                        onPreview(url)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            ZStack(alignment: .topTrailing) {
                                LocalThumbnailImage(url: url, maxPixelSize: 260, contentMode: .fill) {
                                    Image(systemName: "photo")
                                        .frame(width: 126, height: 86)
                                        .background(Color(nsColor: .controlBackgroundColor))
                                }
                                .frame(width: 126, height: 86)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 7))

                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(5)
                                    .background(.black.opacity(0.46), in: Circle())
                                    .padding(5)
                            }
                            Text(url.lastPathComponent)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help("Preview generated image")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GeneratedImagePreviewOverlay: View {
    var imageURL: URL
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.56)
                .contentShape(Rectangle())
                .onTapGesture {
                    onDismiss()
                }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "photo")
                        .foregroundStyle(.white.opacity(0.76))
                    Text(imageURL.lastPathComponent)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 12)
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.callout.weight(.semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.82))
                    .help("Close preview")
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.black.opacity(0.88))

                ZoomableImageScrollView(imageURL: imageURL) {
                    onDismiss()
                }
            }
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 24, y: 16)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .onExitCommand {
            onDismiss()
        }
    }
}

private struct CurrentSelectionReplyCard: View {
    var selection: PDFSelectionInfo
    var onClear: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "quote.opening")
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text("Replying to source · p\(selection.page)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(selection.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove source")
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.65))
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct UserSourceReplyView: View {
    var attachment: UserSourceAttachment
    var onOpen: (String) -> Void

    var body: some View {
        Button {
            onOpen(attachment.anchorID)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "quote.opening")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Quoted source · p\(attachment.page)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(attachment.selectedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.75))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: 3)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("Open quoted source")
    }
}

private struct MarkdownMessageView: View {
    var messageID: String
    var markdown: String
    var onCitation: (String) -> Void
    @State private var height: CGFloat = 24

    var body: some View {
        MarkdownWebView(
            html: ChatMarkdownRenderer.renderDocument(markdown: markdown),
            height: $height,
            onCitation: onCitation
        )
        .id("\(messageID)-\(markdown.hashValue)")
        .frame(minHeight: 24)
        .frame(height: max(24, height))
        .onChange(of: markdown) {
            height = 24
        }
    }
}

private struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var isEnabled: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = SendingTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = context.coordinator.submit
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.drawsBackground = false
        textView.string = text
        textView.minSize = NSSize(width: 0, height: 72)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onSubmit = onSubmit
        guard let textView = scrollView.documentView as? SendingTextView else {
            return
        }
        textView.onSubmit = context.coordinator.submit
        textView.isEditable = isEnabled
        textView.textColor = isEnabled ? .labelColor : .secondaryLabelColor
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text = textView.string
        }

        func submit() {
            onSubmit()
        }
    }

    final class SendingTextView: NSTextView {
        var onSubmit: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            if isReturn, !event.modifierFlags.contains(.shift) {
                if hasMarkedText() {
                    super.keyDown(with: event)
                    return
                }
                onSubmit?()
                return
            }
            super.keyDown(with: event)
        }

        override func paste(_ sender: Any?) {
            if let imageMarkdown = ChatImagePasteboardReader.imageMarkdown(from: .general) {
                insertText(markdownInsertion(imageMarkdown), replacementRange: selectedRange())
                return
            }
            super.paste(sender)
        }

        private func markdownInsertion(_ markdown: String) -> String {
            if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "\(markdown)\n"
            }
            return "\n\(markdown)\n"
        }
    }
}

private enum ChatImagePasteboardReader {
    private static let supportedFileExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "tiff", "tif", "heic"]

    static func imageMarkdown(from pasteboard: NSPasteboard) -> String? {
        let urls = imageURLs(from: pasteboard)
        guard !urls.isEmpty else {
            return nil
        }
        return urls
            .map { "![Pasted image](\($0.standardizedFileURL.path))" }
            .joined(separator: "\n")
    }

    private static func imageURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            let imageURLs = urls.filter { supportedFileExtensions.contains($0.pathExtension.lowercased()) }
            if !imageURLs.isEmpty {
                return imageURLs
            }
        }
        guard let image = NSImage(pasteboard: pasteboard),
              let url = writeTemporaryPNG(image) else {
            return []
        }
        return [url]
    }

    private static func writeTemporaryPNG(_ image: NSImage) -> URL? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PaperCodexComposerImages", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(UUID().uuidString.lowercased()).png")
            try pngData.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

private struct MarkdownWebView: NSViewRepresentable {
    var html: String
    @Binding var height: CGFloat
    var onCitation: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height, onCitation: onCitation)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "height")
        let webView = ScrollForwardingWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        context.coordinator.currentHTML = html
        webView.loadHTMLString(html, baseURL: URL(fileURLWithPath: "/"))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onCitation = onCitation
        if context.coordinator.currentHTML != html {
            context.coordinator.currentHTML = html
            webView.loadHTMLString(html, baseURL: URL(fileURLWithPath: "/"))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var height: CGFloat
        var onCitation: (String) -> Void
        var currentHTML: String?

        init(height: Binding<CGFloat>, onCitation: @escaping (String) -> Void) {
            _height = height
            self.onCitation = onCitation
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "height" else {
                return
            }
            let value: CGFloat?
            if let number = message.body as? NSNumber {
                value = CGFloat(truncating: number)
            } else if let double = message.body as? Double {
                value = CGFloat(double)
            } else {
                value = nil
            }
            if let value, value > 0, abs(value - height) > 1 {
                DispatchQueue.main.async {
                    self.height = value
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.ceil(document.documentElement.scrollHeight)") { [weak self] result, _ in
                guard let self else {
                    return
                }
                let value: CGFloat?
                if let number = result as? NSNumber {
                    value = CGFloat(truncating: number)
                } else if let double = result as? Double {
                    value = CGFloat(double)
                } else {
                    value = nil
                }
                if let value, value > 0 {
                    DispatchQueue.main.async {
                        self.height = value
                    }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url,
               let citationID = CitationParser.citationID(from: url) {
                onCitation(citationID)
                decisionHandler(.cancel)
                return
            }
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "height")
        webView.navigationDelegate = nil
    }

    final class ScrollForwardingWebView: WKWebView {
        override func scrollWheel(with event: NSEvent) {
            if let outerScrollView = findOuterScrollView() {
                outerScrollView.scrollWheel(with: event)
                return
            }
            super.scrollWheel(with: event)
        }

        private func findOuterScrollView() -> NSScrollView? {
            var view = superview
            while let current = view {
                if let scrollView = current.enclosingScrollView {
                    return scrollView
                }
                view = current.superview
            }
            return nil
        }
    }
}
