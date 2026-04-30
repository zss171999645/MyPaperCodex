import Foundation
import AppKit
import CryptoKit
import PDFKit
import PaperCodexCore

struct CheckFailure: Error, CustomStringConvertible {
    var description: String
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw CheckFailure(description: message)
    }
}

func runModelsChecks() throws {
    let span = Span(
        id: Span.makeID(paperID: "paper-a", page: 5, blockIndex: 17),
        paperID: "paper-a",
        page: 5,
        bbox: BoundingBox(x: 10, y: 20, width: 120, height: 34),
        text: "Diffusion models denoise latent variables.",
        charRange: TextRange(location: 12, length: 42),
        sectionHint: "Method",
        confidence: 0.92
    )

    try check(span.id == "paper:paper-a:p5:b17", "span stable ID should include paper, page, and block")
    try check(span.page == 5, "span page should round-trip")
    try check(span.bbox.width == 120, "span bbox width should round-trip")

    let longSpan = Span(
        id: Span.makeID(paperID: "paper-a", page: 5, blockIndex: 18),
        paperID: "paper-a",
        page: 5,
        bbox: BoundingBox(x: 10, y: 60, width: 300, height: 120),
        text: String(repeating: "Long citation evidence sentence. ", count: 18),
        charRange: TextRange(location: 60, length: 540),
        sectionHint: nil,
        confidence: 0.9
    )
    let compactedLongSpan = SpanCompactor.compact([longSpan])
    try check(compactedLongSpan.count > 1, "oversized imported spans should be split into smaller citation blocks")
    try check(compactedLongSpan.allSatisfy { $0.text.count <= 420 }, "split citation blocks should stay within the target size")
    try check(compactedLongSpan.first?.id == longSpan.id, "first split should preserve the original citation id")
    try check(compactedLongSpan.dropFirst().allSatisfy { $0.id.hasPrefix("\(longSpan.id)s") }, "later splits should keep resolvable citation aliases")

    let anchor = Anchor(
        id: Anchor.makeID(paperID: "paper-a", page: 5, suffix: "01HX"),
        paperID: "paper-a",
        page: 5,
        selectedText: "selected paragraph",
        bboxList: [BoundingBox(x: 4, y: 8, width: 40, height: 16)],
        matchedSpanIDs: ["paper:paper-a:p5:b17"],
        beforeContext: "before",
        afterContext: "after",
        createdSessionID: "session-a",
        createdAt: Date(timeIntervalSince1970: 1_777_220_000),
        confidence: 0.88
    )

    try check(anchor.id == "paper:paper-a:p5:a01HX", "anchor stable ID should include paper, page, and suffix")
    try check(anchor.matchedSpanIDs == ["paper:paper-a:p5:b17"], "anchor should keep matched span IDs")

    let paper = Paper(
        id: "paper-a",
        filePath: "/tmp/paper.pdf",
        fileHash: "sha256",
        title: "Representation Autoencoders",
        authors: ["Alice", "Bob"],
        year: 2026,
        sourceURL: "https://arxiv.org/abs/0000.00000",
        importedAt: Date(timeIntervalSince1970: 1_777_220_000),
        updatedAt: Date(timeIntervalSince1970: 1_777_220_010)
    )
    let session = PaperSession(
        id: "session-a",
        title: "Mechanism Notes",
        paperIDs: ["paper-a", "paper-b"],
        codexSessionID: "codex-session",
        workspacePath: "/tmp/session",
        createdAt: Date(timeIntervalSince1970: 1_777_220_000),
        updatedAt: Date(timeIntervalSince1970: 1_777_220_020)
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let decodedPaper = try decoder.decode(Paper.self, from: encoder.encode(paper))
    let decodedSession = try decoder.decode(PaperSession.self, from: encoder.encode(session))
    try check(decodedPaper == paper, "paper should JSON round-trip")
    try check(decodedSession == session, "session should JSON round-trip")

    let placeholderID = Paper.makeArxivImportPlaceholderID(for: "2604.18586v2")
    let placeholder = Paper(
        id: placeholderID,
        filePath: "",
        fileHash: Paper.arxivImportPlaceholderFileHash(canonicalID: "2604.18586"),
        title: "2604.18586",
        authors: [],
        year: nil,
        sourceURL: "https://arxiv.org/abs/2604.18586",
        importedAt: Date(timeIntervalSince1970: 1_777_220_000),
        updatedAt: Date(timeIntervalSince1970: 1_777_220_000)
    )
    try check(placeholderID == "pending-arxiv-2604-18586v2", "arXiv import placeholder IDs should be stable and path-safe")
    try check(placeholder.isArxivImportPlaceholder, "pending arXiv imports should be represented as placeholder papers")
    try check(placeholder.arxivImportPlaceholderCanonicalID == "2604.18586", "placeholder papers should expose their canonical arXiv ID")
}

func runLocalStoreV2ModelChecks() throws {
    let now = Date(timeIntervalSince1970: 1_777_300_000)
    let file = PaperFileRecord(
        id: "file-a",
        paperID: "paper-a",
        storageState: .savedLocal,
        localPath: "/tmp/paper-a/original.pdf",
        contentHash: "hash-a",
        byteCount: 42,
        mimeType: "application/pdf",
        remoteFileID: nil,
        encryptionState: .none,
        createdAt: now,
        updatedAt: now
    )
    let source = PaperSourceRecord(
        id: "source-a",
        paperID: "paper-a",
        sourceType: .arxiv,
        sourceID: "2604.18586",
        url: "https://arxiv.org/abs/2604.18586",
        version: "v1",
        metadataJSON: #"{"primary_category":"cs.CV"}"#,
        createdAt: now
    )
    let note = PaperNote(
        id: "note-a",
        paperID: "paper-a",
        anchorID: nil,
        title: "Reading note",
        bodyMarkdown: "Important limitation.",
        createdAt: now,
        updatedAt: now,
        deletedAt: nil,
        syncRevision: 1
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decodedFile = try decoder.decode(PaperFileRecord.self, from: encoder.encode(file))
    let decodedSource = try decoder.decode(PaperSourceRecord.self, from: encoder.encode(source))
    let decodedNote = try decoder.decode(PaperNote.self, from: encoder.encode(note))
    try check(decodedFile == file, "paper file record should JSON round-trip")
    try check(decodedSource == source, "paper source record should JSON round-trip")
    try check(decodedNote == note, "paper note should JSON round-trip")
    try check(PaperStorageState.feedPDFCache.rawValue == "feed_pdf_cache", "feed PDF cache state should be stable")
}

func runReaderTabStateChecks() throws {
    var state = ReaderTabState()
    let paperA = ReaderPaperTab(paperID: "paper-a", title: "Paper A", detail: "/tmp/a.pdf", isSaved: true)
    let paperB = ReaderPaperTab(paperID: "paper-b", title: "Paper B", detail: "/tmp/b.pdf", isSaved: true)
    let paperC = ReaderPaperTab(paperID: "paper-c", title: "Paper C", detail: "/tmp/c.pdf", isSaved: true)

    state.open(paperA)
    state.open(paperB)
    state.open(paperA)
    try check(state.tabs.map(\.paperID) == ["paper-a", "paper-b"], "opening an existing reader tab should focus it without duplicating it")
    try check(state.activePaperID == "paper-a", "opening an existing reader tab should make it active")

    state.open(paperC)
    _ = state.select("paper-a")
    let nextAfterClosingMiddle = state.close("paper-b")
    try check(nextAfterClosingMiddle == "paper-a", "closing an inactive tab should keep the current tab active")
    try check(state.tabs.map(\.paperID) == ["paper-a", "paper-c"], "closing a reader tab should remove only that tab")

    let nextAfterClosingActive = state.close("paper-a")
    try check(nextAfterClosingActive == "paper-c", "closing the active reader tab should select the nearest remaining tab")
    try check(state.activePaperID == "paper-c", "reader tab state should update the active paper after close")

    let savedPaperC = ReaderPaperTab(paperID: "paper-c-saved", title: "Paper C", detail: "/library/c.pdf", isSaved: true)
    state.replace("paper-c", with: savedPaperC)
    try check(state.tabs.map(\.paperID) == ["paper-c-saved"], "saving a cached paper should replace the existing reader tab")
    try check(state.activePaperID == "paper-c-saved", "replacing the active reader tab should keep it active under the new paper id")

    let last = state.close("paper-c-saved")
    try check(last == nil, "closing the last reader tab should leave no active paper")
    try check(state.tabs.isEmpty, "closing the last reader tab should clear open tabs")
}

func runReaderPositionRepositoryChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-reader-positions-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let databaseURL = tempRoot.appendingPathComponent("store.sqlite")
    let repository = try PaperRepository(databasePath: databaseURL.path)
    try repository.migrate()

    let now = Date(timeIntervalSince1970: 1_777_260_000)
    let paper = Paper(
        id: "paper-a",
        filePath: "/tmp/paper-a.pdf",
        fileHash: "hash-reader-position-a",
        title: "Paper A",
        authors: ["Alice"],
        year: 2026,
        sourceURL: nil,
        importedAt: now,
        updatedAt: now
    )
    try repository.upsertPaper(paper)

    let sessionA = PaperSession(
        id: "session-a",
        title: "Session A",
        paperIDs: [paper.id],
        codexSessionID: nil,
        workspacePath: tempRoot.appendingPathComponent("session-a").path,
        createdAt: now,
        updatedAt: now
    )
    let sessionB = PaperSession(
        id: "session-b",
        title: "Session B",
        paperIDs: [paper.id],
        codexSessionID: nil,
        workspacePath: tempRoot.appendingPathComponent("session-b").path,
        createdAt: now,
        updatedAt: now
    )
    try repository.upsertSession(sessionA)
    try repository.upsertSession(sessionB)

    let positionA = PaperReaderPosition(
        sessionID: sessionA.id,
        paperID: paper.id,
        pageIndex: 4,
        pagePointX: 120.5,
        pagePointY: 730.25,
        scaleFactor: 1.35,
        updatedAt: now
    )
    let positionB = PaperReaderPosition(
        sessionID: sessionB.id,
        paperID: paper.id,
        pageIndex: 9,
        pagePointX: 82,
        pagePointY: 240,
        scaleFactor: 0.92,
        updatedAt: now.addingTimeInterval(30)
    )

    try repository.upsertReaderPosition(positionA)
    try repository.upsertReaderPosition(positionB)

    let fetchedPositionA = try repository.fetchReaderPosition(sessionID: sessionA.id, paperID: paper.id)
    let fetchedPositionB = try repository.fetchReaderPosition(sessionID: sessionB.id, paperID: paper.id)
    try check(fetchedPositionA == positionA, "reader position should be scoped by session and paper")
    try check(fetchedPositionB == positionB, "different sessions should keep independent positions for the same paper")

    let reopened = try PaperRepository(databasePath: databaseURL.path)
    try reopened.migrate()
    let reopenedPositionA = try reopened.fetchReaderPosition(sessionID: sessionA.id, paperID: paper.id)
    try check(reopenedPositionA == positionA, "reader position should survive repository reopen")
}

func runUILayoutSourceChecks() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let libraryViewURL = root.appendingPathComponent("Sources/PaperCodexApp/LibraryView.swift")
    let librarySource = try String(contentsOf: libraryViewURL)

    try check(
        librarySource.contains("static let splitPaneTopInset: CGFloat"),
        "library split panes should use an explicit titlebar compensation inset"
    )
    try check(
        librarySource.components(separatedBy: "LibraryLayout.splitPaneTopInset").count - 1 >= 2,
        "library list and inspector panes should share the same top inset constant"
    )
    try check(
        librarySource.contains("CategorySidebarRow"),
        "library category rows should have a dedicated hoverable row component"
    )
    try check(
        librarySource.contains("onCreateChild"),
        "library category rows should expose a direct child-category creation action"
    )
    try check(
        librarySource.contains("newCategoryParentID = item.category.id"),
        "hover category add buttons should preselect the hovered category as parent"
    )
    try check(
        librarySource.contains("@FocusState private var isNameFocused"),
        "category creation sheet should focus the name field for fast child folder creation"
    )
    try check(
        librarySource.contains("isShowingArxivImport"),
        "library toolbar should expose a direct arXiv import sheet"
    )
    try check(
        librarySource.contains("LibrarySortOption"),
        "library list should expose explicit sort options"
    )
    try check(
        librarySource.contains("sortedPapers"),
        "library should sort papers after filtering"
    )
    try check(
        librarySource.contains("librarySortAscending"),
        "library sorting should support ascending and descending directions"
    )
    try check(
        librarySource.contains("sortDirectionButton"),
        "library toolbar should expose a one-click sort direction toggle"
    )
    try check(
        librarySource.contains("systemImage: \"number\""),
        "library toolbar should show an arXiv import button next to PDF import"
    )
    try check(
        librarySource.contains("model.enqueueArxivIDsForLibrary"),
        "library arXiv import sheet should enqueue IDs and close instead of waiting in the sheet"
    )
    try check(
        librarySource.contains("isImportPlaceholder: paper.isArxivImportPlaceholder"),
        "library paper rows should render pending arXiv imports as placeholders"
    )
    try check(
        librarySource.contains(".disabled(isImportPlaceholder)"),
        "pending arXiv placeholder rows should disable read/open actions until the PDF is ready"
    )
    try check(
        librarySource.contains(".onDrag {") && librarySource.contains("NSItemProvider(object: paperDragPayload(for: paper) as NSString)"),
        "library paper rows should expose selected paper IDs as an NSItemProvider drag payload"
    )
    try check(
        librarySource.contains(".onDrop(of: LibraryLayout.categoryDropContentTypes"),
        "library category rows should accept dropped paper IDs as plain text payloads"
    )
    try check(
        librarySource.contains("isDropTargeted"),
        "library category rows should visibly highlight valid drop targets"
    )
    try check(
        librarySource.contains("selectedPaperIDs.count > 1"),
        "library bulk actions should appear only for true multi-selection, not ordinary single selection"
    )
    try check(
        librarySource.contains("seedSelectionForCommandToggle"),
        "command-click should extend from the currently focused paper before toggling another row"
    )
    try check(
        librarySource.contains("clearPaperMultiSelection()"),
        "plain paper clicks should clear multi-selection like Finder"
    )
    try check(
        !librarySource.contains(".highPriorityGesture(paperDragGesture"),
        "library paper rows should not attach a competing high-priority drag gesture over native drag/drop"
    )
    try check(
        librarySource.contains(".onDrag {") && librarySource.contains("NSItemProvider(object: paperDragPayload(for: paper) as NSString)"),
        "library paper rows should use native drag payloads for folder assignment"
    )
    try check(
        librarySource.contains("categoryDropContentTypes"),
        "library category rows should accept native plain-text paper drag payloads"
    )
    try check(
        librarySource.contains("bulkActionBarOverlayYOffset"),
        "library bulk action overlay should sit lower over the list instead of hugging the top edge"
    )
    try check(
        librarySource.contains("bulkActionBarOverlayOpacity"),
        "library bulk action overlay should render with reduced opacity"
    )
    try check(
        librarySource.contains("dragPreviewPaperIDs(for:"),
        "native paper drag previews should reflect the seeded multi-selection set"
    )
    try check(
        !librarySource.contains("DragGesture(minimumDistance: 8"),
        "library paper dragging should not rely on a parallel custom drag gesture"
    )
    try check(
        !librarySource.contains("ActiveLibraryPaperDrag"),
        "library paper dragging should avoid stale custom drag state when native drag/drop is used"
    )

    let appModelURL = root.appendingPathComponent("Sources/PaperCodexApp/AppModel.swift")
    let appModelSource = try String(contentsOf: appModelURL)
    let settingsViewURL = root.appendingPathComponent("Sources/PaperCodexApp/SettingsView.swift")
    let settingsViewSource = try String(contentsOf: settingsViewURL)
    let discoverViewURL = root.appendingPathComponent("Sources/PaperCodexApp/DiscoverView.swift")
    let discoverSource = try String(contentsOf: discoverViewURL)
    try check(
        appModelSource.contains("assignPapers(_ paperIDs: [String], toCategory categoryID: String)"),
        "AppModel should provide a batch paper-to-category assignment path for drag and drop"
    )
    try check(
        appModelSource.contains("assignPapers(_ paperIDs: [String], toTags tagIDs: [String])"),
        "AppModel should provide a batch paper-to-tags assignment path"
    )
    try check(
        appModelSource.contains("deletePapers(_ paperIDs: [String])"),
        "AppModel should provide a batch library delete path"
    )
    try check(
        appModelSource.contains("pendingArxivLibraryImportIDs"),
        "AppModel should track active arXiv library imports for placeholder status"
    )
    try check(
        appModelSource.contains("completeQueuedArxivLibraryImports"),
        "AppModel should finish queued arXiv imports in the background after the sheet closes"
    )
    try check(
        appModelSource.contains("makeArxivImportPlaceholderPaper"),
        "AppModel should create saved placeholder papers for immediate library display"
    )
    try check(
        librarySource.contains("selectedPaperIDs"),
        "library should keep explicit multi-selection state"
    )
    try check(
        librarySource.contains("BulkLibraryActionBar"),
        "library should show a contextual bulk action bar for selected papers"
    )
    try check(
        librarySource.contains("LibraryBulkMoveSheet"),
        "library should provide a bulk move sheet"
    )
    try check(
        librarySource.contains("LibraryBulkTagSheet"),
        "library should provide a bulk tag sheet"
    )
    try check(
        librarySource.contains("isConfirmingBulkDelete"),
        "library should confirm destructive bulk deletes"
    )
    try check(
        appModelSource.contains("codexSystemPromptDefaultsKey"),
        "AppModel should persist the configurable Codex system prompt"
    )
    try check(
        appModelSource.contains("systemPromptTemplate: codexSystemPrompt"),
        "AppModel should pass the configured Codex system prompt into prompt building"
    )
    try check(
        settingsViewSource.contains("codexSystemPromptSettings"),
        "settings should include a dedicated Codex system prompt section"
    )
    try check(
        settingsViewSource.contains("TextEditor(text: $draftCodexSystemPrompt)"),
        "settings should expose the Codex system prompt in an editable text area"
    )
    try check(
        settingsViewSource.contains("model.resetCodexSystemPrompt()"),
        "settings should let users restore the default Codex system prompt"
    )
    try check(
        appModelSource.contains("globalLanguageModeDefaultsKey"),
        "AppModel should persist the global language mode"
    )
    try check(
        appModelSource.contains("languageMode: globalLanguageMode"),
        "AppModel should pass the global language mode into prompt building"
    )
    try check(
        settingsViewSource.contains("globalLanguageSettings"),
        "settings should include a dedicated global language section"
    )
    try check(
        settingsViewSource.contains("Picker(\"App language\""),
        "settings should expose an app-wide language picker"
    )
    try check(
        settingsViewSource.contains("Controls the whole app interface"),
        "settings should describe language as an app-wide setting, not only answer language"
    )
    try check(
        discoverSource.contains("languageMode: model.globalLanguageMode"),
        "Discover cards should render with the configured global language"
    )
    try check(
        discoverSource.contains("paper.displayTitle(language: model.globalLanguageMode.discoverLanguageCode)"),
        "Discover save sheet should use the configured global language"
    )
    let rootViewSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexApp.swift"))
    let sidebarRowSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/SidebarRowButton.swift"))
    let buildScriptSource = try String(contentsOf: root.appendingPathComponent("scripts/build-app-bundle.sh"))
    try check(
        rootViewSource.contains(".environment(\\.locale"),
        "root view should drive SwiftUI localization from the app language setting"
    )
    try check(
        sidebarRowSource.contains("LocalizedStringKey(title)"),
        "shared sidebar rows should localize dynamic navigation titles"
    )
    try check(
        buildScriptSource.contains("*.lproj"),
        "app bundle build should copy localization resources"
    )

    let chatViewURL = root.appendingPathComponent("Sources/PaperCodexApp/ChatView.swift")
    let chatSource = try String(contentsOf: chatViewURL)
    try check(
        chatSource.contains("chatComposerTextHeightDefaultsKey"),
        "chat composer height should be persisted locally"
    )
    try check(
        chatSource.contains("ComposerResizeHandle"),
        "chat composer should expose a visible resize handle"
    )
    try check(
        chatSource.contains("DragGesture(minimumDistance: 1, coordinateSpace: .global)"),
        "chat composer resize handle should use an explicit vertical drag gesture"
    )
    try check(
        chatSource.contains("ChatComposerLayout.clampedTextHeight"),
        "chat composer height changes should be clamped through a shared layout helper"
    )

    let pdfKitViewURL = root.appendingPathComponent("Sources/PaperCodexApp/PDFKitView.swift")
    let pdfKitSource = try String(contentsOf: pdfKitViewURL)
    try check(
        pdfKitSource.contains("centerJumpTarget"),
        "PDF citation jumps should use an explicit centered viewport path"
    )
    try check(
        pdfKitSource.contains("centerPDFPagePointInViewport"),
        "PDF citation jumps should scroll the target point into the middle of the viewport"
    )
    try check(
        !pdfKitSource.contains("first.y + first.height"),
        "PDF citation jumps should not align the highlight top edge to the viewport top"
    )
    let interactionSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/InteractionFeedback.swift"))
    try check(
        interactionSource.contains("InteractionNoticeStack"),
        "global feedback should render non-blocking notices instead of forcing every message into an alert"
    )
    try check(
        rootViewSource.contains("PaperCodexCommands"),
        "the app should expose keyboard shortcuts through a Commands scene"
    )
    try check(
        rootViewSource.contains("GlobalOperationStatusView"),
        "the root view should show the current long-running operation"
    )
    try check(
        appModelSource.contains("postNotice("),
        "AppModel should publish success and failure notices for interaction feedback"
    )
    try check(
        appModelSource.contains("CacheStorageSummary"),
        "AppModel should expose a cache and storage summary for Settings"
    )

    try check(
        librarySource.contains("dropPDFs(from providers:"),
        "library should accept dropped PDF files for import"
    )
    try check(
        !librarySource.contains(".onTapGesture(count: 2)"),
        "library paper rows should not use a row-level double-tap recognizer that delays single-click selection"
    )
    try check(
        librarySource.contains("lastPaperRowClick"),
        "library paper rows should detect a second quick click from the immediate single-click handler"
    )
    try check(
        librarySource.contains("@State private var isHovering = false"),
        "library paper rows should track hover state for row feedback and selection affordances"
    )
    try check(
        librarySource.contains("bulkActionBarOverlay"),
        "library bulk action controls should float over the list instead of shifting rows down"
    )
    try check(
        !librarySource.contains("onSelectionToggle"),
        "library paper rows should not show checkbox-style selection controls"
    )
    try check(
        !librarySource.contains("showSelectionToggle"),
        "library paper rows should rely on command/shift multi-select instead of hover checkboxes"
    )
    try check(
        librarySource.contains("arxivDisplayID"),
        "library paper rows should show the arXiv ID in the visible card area when available"
    )
    try check(
        librarySource.contains(".font(.system(size: 12.5"),
        "library arXiv, folder, and tag chips should be slightly larger than caption text"
    )
    try check(
        librarySource.contains("paperIDsForDrag(startingWith:"),
        "dragging a library paper should carry the selected paper set when the row is part of a multi-selection"
    )
    try check(
        librarySource.contains("CategoryDepthGuide"),
        "library folder hierarchy should render an explicit depth guide"
    )
    try check(
        librarySource.contains("LazyVStack(spacing: 1)"),
        "library paper rows should reduce inter-card gaps and make the card hit area larger"
    )
    try check(
        librarySource.contains("categoryManagementSheet"),
        "library should provide category rename, move, and delete management"
    )
    try check(
        librarySource.contains("tagManagementSheet"),
        "library should provide tag rename and delete management"
    )
    try check(
        librarySource.contains("collapsedCategoryIDs"),
        "library category tree should support folding"
    )
    try check(
        librarySource.contains("countText:"),
        "library sidebar rows should show category and tag counts"
    )
    try check(
        librarySource.contains("paperNotesSection"),
        "library inspector should expose per-paper notes"
    )
    try check(
        appModelSource.contains("updateCategory(") && appModelSource.contains("deleteCategory("),
        "AppModel should manage category rename, move, and delete operations"
    )
    try check(
        appModelSource.contains("updateTag(") && appModelSource.contains("deleteTag("),
        "AppModel should manage tag rename and delete operations"
    )
    try check(
        appModelSource.contains("saveNote("),
        "AppModel should persist paper notes"
    )
    try check(
        appModelSource.contains("librarySelectedCategoryID"),
        "AppModel should keep library category selection outside LibraryView local state"
    )
    try check(
        appModelSource.contains("readerReturnRoute"),
        "AppModel should remember whether the reader was opened from Library or Discover"
    )
    try check(
        discoverSource.contains("restoreDiscoverScrollPosition"),
        "Discover should restore the last visible paper when returning from the reader"
    )

    let readerSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/ReaderView.swift"))
    try check(
        readerSource.contains("ReaderPDFToolbar"),
        "reader should provide explicit PDF toolbar controls"
    )
    try check(
        appModelSource.contains("returnFromCitationJump"),
        "AppModel should keep a citation return path"
    )
    try check(
        pdfKitSource.contains("PDFKitCommand"),
        "PDFKit view should accept explicit toolbar commands"
    )
    try check(
        interactionSource.contains("case restorePosition(PaperReaderPosition)"),
        "PDFKit commands should provide an explicit restore-position command for citation return"
    )
    try check(
        !pdfKitSource.contains("lastAppliedReadingPositionDate"),
        "PDF reading-position saves should not trigger viewport restoration through updatedAt changes"
    )
    try check(
        pdfKitSource.contains("CitationAwarePDFView"),
        "PDFKit view should use a click-aware PDFView subclass for in-PDF citation previews"
    )
    try check(
        pdfKitSource.contains("showCitationPreviewPopover"),
        "PDFKit view should show a popup preview for in-text citations"
    )
    try check(
        pdfKitSource.contains("ReferenceEntryCard"),
        "PDFKit view should render clicked reference-list entries as a card"
    )
    try check(
        pdfKitSource.contains("InTextCitationPreview"),
        "PDFKit view should render non-reference citations as a lightweight preview popup"
    )
    try check(
        readerSource.contains("model.returnFromReader()"),
        "reader back navigation should return to the previous browsing surface instead of always resetting to Library"
    )

    try check(
        chatSource.contains("ScrollViewReader"),
        "chat should auto-scroll to the newest message and active run"
    )
    try check(
        chatSource.contains("isCurrentSessionSending"),
        "chat should distinguish the active session run from other sessions"
    )
    try check(
        chatSource.contains("canEditComposer"),
        "other session composers should remain editable while Codex runs elsewhere"
    )
    try check(
        chatSource.contains("composerTopDivider"),
        "chat input separator should be owned by the composer above the input area"
    )
    try check(
        chatSource.contains("renameSessionSheet"),
        "chat sessions should be renameable from the session bar"
    )
    try check(
        chatSource.contains("GeneratedImageGallery"),
        "chat should render generated local images as an explicit gallery"
    )
    try check(
        chatSource.contains("hasMarkedText()"),
        "chat composer should let IME marked text handle Return before submitting"
    )
    try check(
        appModelSource.contains("appendCodexCancellationMessage"),
        "cancelling Codex should leave a visible trace in the session"
    )

    try check(
        discoverSource.contains("DiscoverPaperStatusBadge"),
        "Discover cards should show per-paper processing and cache state"
    )
    try check(
        discoverSource.contains("activeFilterChips"),
        "Discover should show removable active filter chips"
    )
    try check(
        discoverSource.contains("Cache visible"),
        "Discover cache actions should clarify visible versus full-result scope"
    )

    try check(
        settingsViewSource.contains("SettingsSectionAnchor"),
        "settings should expose section anchors in the sidebar"
    )
    try check(
        settingsViewSource.contains("isArxivFeedDirty"),
        "settings should show dirty/saved state for editable sections"
    )
    try check(
        settingsViewSource.contains("testEmbeddingProvider"),
        "settings should provide an embedding-provider test action"
    )
    try check(
        settingsViewSource.contains("moveQuickPrompt"),
        "settings should allow quick prompts to be reordered"
    )
    try check(
        settingsViewSource.contains("revealPath("),
        "settings should reveal library and cache paths in Finder"
    )
}

func runRepositoryChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-repository-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let databaseURL = tempRoot.appendingPathComponent("store.sqlite")
    let repository = try PaperRepository(databasePath: databaseURL.path)
    try repository.migrate()

    let now = Date(timeIntervalSince1970: 1_777_220_000)
    let paper = Paper(
        id: "paper-a",
        filePath: "/tmp/paper-a.pdf",
        fileHash: "hash-a",
        title: "Paper A",
        authors: ["Alice", "Bob"],
        year: 2026,
        sourceURL: nil,
        importedAt: now,
        updatedAt: now
    )
    let paperB = Paper(
        id: "paper-b",
        filePath: "/tmp/paper-b.pdf",
        fileHash: "hash-b",
        title: "Paper B",
        authors: ["Carol"],
        year: 2025,
        sourceURL: nil,
        importedAt: now,
        updatedAt: now
    )
    let category = Category(id: "cat-methods", parentID: nil, name: "Methods", sortOrder: 1)
    let childCategory = Category(id: "cat-vae", parentID: "cat-methods", name: "VAE", sortOrder: 2)
    let tag = PaperTag(id: "tag-control", name: "control")
    let unassignedTag = PaperTag(id: "tag-diffusion", name: "diffusion")
    let page = PageIndex(
        paperID: "paper-a",
        page: 2,
        text: "Full text for page two.",
        confidence: 0.93
    )
    let span = Span(
        id: Span.makeID(paperID: "paper-a", page: 2, blockIndex: 3),
        paperID: "paper-a",
        page: 2,
        bbox: BoundingBox(x: 1, y: 2, width: 3, height: 4),
        text: "A stable span.",
        charRange: TextRange(location: 10, length: 14),
        sectionHint: "Method",
        confidence: 0.91
    )
    let anchor = Anchor(
        id: Anchor.makeID(paperID: "paper-a", page: 2, suffix: "sel1"),
        paperID: "paper-a",
        page: 2,
        selectedText: "A stable span.",
        bboxList: [span.bbox],
        matchedSpanIDs: [span.id],
        beforeContext: "Before",
        afterContext: "After",
        createdSessionID: "session-a",
        createdAt: now,
        confidence: 0.9
    )
    let session = PaperSession(
        id: "session-a",
        title: "Mechanism Notes",
        paperIDs: ["paper-a"],
        codexSessionID: "codex-a",
        workspacePath: tempRoot.appendingPathComponent("session-a").path,
        createdAt: now,
        updatedAt: now
    )
    let message = ChatMessage(
        id: "message-a",
        sessionID: "session-a",
        role: .user,
        content: "Use [[cite:\(anchor.id)]] here.",
        createdAt: now
    )

    try repository.upsertPaper(paper)
    try repository.upsertPaper(paperB)
    try repository.upsertCategory(category)
    try repository.upsertCategory(childCategory)
    try repository.upsertTag(tag)
    try repository.upsertTag(unassignedTag)
    try repository.assignPaper("paper-a", toCategory: "cat-vae")
    try repository.assignPaper("paper-a", toTag: "tag-control")
    try repository.upsertPage(page)
    try repository.upsertSpan(span)
    try repository.upsertAnchor(anchor)
    try repository.upsertSession(session)
    try repository.appendMessage(message)

    let fetchedPapers = try repository.fetchPapers()
    let fetchedPapersByID = try repository.fetchPapers(ids: ["paper-b", "missing-paper", "paper-a"])
    let fetchedPaperByHash = try repository.fetchPaper(fileHash: "hash-a")
    let missingPaperByHash = try repository.fetchPaper(fileHash: "missing-hash")
    let fetchedCategories = try repository.fetchCategories()
    let fetchedAllTags = try repository.fetchTags()
    let fetchedTags = try repository.fetchTags(forPaperID: "paper-a")
    let fetchedCategoryIDs = try repository.fetchCategoryIDs(forPaperID: "paper-a")
    let fetchedPages = try repository.fetchPages(paperID: "paper-a")
    let fetchedSpans = try repository.fetchSpans(paperID: "paper-a")
    let fetchedSpanByID = try repository.fetchSpan(id: span.id)
    let fetchedAnchors = try repository.fetchAnchors(paperID: "paper-a")
    let fetchedAnchorByID = try repository.fetchAnchor(id: anchor.id)
    let fetchedSessions = try repository.fetchSessions(paperID: "paper-a")
    let fetchedMessages = try repository.fetchMessages(sessionID: "session-a")

    try check(fetchedPapers == [paper, paperB], "papers should round-trip through SQLite")
    try check(fetchedPapersByID == [paperB, paper], "papers should be fetchable by ID in requested order")
    try check(fetchedPaperByHash == paper, "paper should be fetchable by file hash for duplicate detection")
    try check(missingPaperByHash == nil, "missing file hash should not return a paper")
    try check(fetchedCategories == [category, childCategory], "categories should preserve hierarchy and sort order")
    try check(fetchedAllTags == [tag, unassignedTag], "all tags should round-trip sorted by name")
    try check(fetchedTags == [tag], "paper tags should round-trip")
    try check(fetchedCategoryIDs == ["cat-vae"], "paper category links should round-trip")
    try check(fetchedPages == [page], "page indexes should round-trip")
    try check(fetchedSpans == [span], "spans should round-trip")
    try check(fetchedSpanByID == span, "spans should be fetchable by citation ID")
    try check(fetchedAnchors == [anchor], "anchors should round-trip")
    try check(fetchedAnchorByID == anchor, "anchors should be fetchable by citation ID")
    try check(fetchedSessions == [session], "sessions should round-trip")
    try check(fetchedMessages == [message], "messages should round-trip")

    var multiPaperSession = session
    multiPaperSession.paperIDs = ["paper-b", "paper-a"]
    multiPaperSession.updatedAt = Date(timeIntervalSince1970: 1_777_220_100)
    try repository.upsertSession(multiPaperSession)
    let fetchedSessionByID = try repository.fetchSession(id: "session-a")
    let fetchedSessionsForPaperB = try repository.fetchSessions(paperID: "paper-b")
    try check(fetchedSessionByID == multiPaperSession, "session should be fetchable by ID with ordered paper IDs")
    try check(fetchedSessionsForPaperB == [multiPaperSession], "sessions should be visible from every linked paper")

    try repository.removePaper("paper-a", fromCategory: "cat-vae")
    try repository.removePaper("paper-a", fromTag: "tag-control")
    let removedCategoryIDs = try repository.fetchCategoryIDs(forPaperID: "paper-a")
    let removedTags = try repository.fetchTags(forPaperID: "paper-a")
    try check(removedCategoryIDs.isEmpty, "paper category links should be removable")
    try check(removedTags.isEmpty, "paper tag links should be removable")

    try repository.assignPaper("paper-a", toCategory: "cat-vae")
    try repository.assignPaper("paper-a", toTag: "tag-control")
    try repository.deletePapers(ids: ["paper-a", "missing-paper"])
    let papersAfterDelete = try repository.fetchPapers(ids: ["paper-a", "paper-b"])
    let deletedPaperCategoryIDs = try repository.fetchCategoryIDs(forPaperID: "paper-a")
    let deletedPaperTags = try repository.fetchTags(forPaperID: "paper-a")
    let sessionsAfterPaperDelete = try repository.fetchSessions(paperID: "paper-a")
    try check(papersAfterDelete == [paperB], "repository should delete requested papers while preserving others")
    try check(deletedPaperCategoryIDs.isEmpty, "repository should remove category links for deleted papers")
    try check(deletedPaperTags.isEmpty, "repository should remove tag links for deleted papers")
    try check(sessionsAfterPaperDelete.isEmpty, "repository should remove session paper links for deleted papers")
}

func runLocalStoreV2MigrationChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-local-store-v2-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let repository = try PaperRepository(databasePath: tempRoot.appendingPathComponent("store.sqlite").path)
    try repository.migrate()

    let now = Date(timeIntervalSince1970: 1_777_300_000)
    let paper = Paper(
        id: "paper-a",
        filePath: tempRoot.appendingPathComponent("paper-a/original.pdf").path,
        fileHash: "hash-a",
        title: "Paper A",
        authors: ["Alice"],
        year: 2026,
        sourceURL: "https://arxiv.org/abs/2604.18586",
        importedAt: now,
        updatedAt: now
    )
    let versionedPaper = Paper(
        id: "paper-b",
        filePath: tempRoot.appendingPathComponent("paper-b/original.pdf").path,
        fileHash: "hash-b",
        title: "Paper B",
        authors: ["Bob"],
        year: 2026,
        sourceURL: "http://arxiv.org/pdf/2604.18587v2.pdf?download=1",
        isSaved: false,
        importedAt: now,
        updatedAt: now
    )
    try repository.upsertPaper(paper)
    try repository.upsertPaper(versionedPaper)
    try repository.upsertCategory(Category(id: "cat-methods", parentID: nil, name: "Methods", sortOrder: 1))
    try repository.upsertCategory(Category(id: "cat-vae", parentID: "cat-methods", name: "VAE", sortOrder: 2))
    try repository.upsertTag(PaperTag(id: "tag-diffusion", name: "Diffusion"))
    try repository.assignPaper("paper-a", toCategory: "cat-vae")
    try repository.assignPaper("paper-a", toTag: "tag-diffusion")

    let database = try SQLiteDatabase(path: tempRoot.appendingPathComponent("store.sqlite").path)
    let paperColumns = try database.tableColumns("papers")
    let paperMetadata = try database.query("SELECT id, canonical_key, source_kind, arxiv_id, arxiv_id_versioned FROM papers ORDER BY id;") { row in
        "\(try row.text(0))|\(try row.text(1))|\(try row.text(2))|\(row.optionalText(3) ?? "")|\(row.optionalText(4) ?? "")"
    }
    let folders = try database.query("SELECT id, parent_id, name FROM folders ORDER BY sort_order, name;") { row in
        "\(try row.text(0))|\(row.optionalText(1) ?? "")|\(try row.text(2))"
    }
    let folderCreatedAt = try database.query("SELECT created_at FROM paper_folders WHERE paper_id = ? AND folder_id = ?;", bindings: [.text("paper-a"), .text("cat-vae")]) { row in
        try row.text(0)
    }.first
    let fileRows = try database.query("SELECT paper_id, storage_state, local_path, content_hash FROM paper_files ORDER BY paper_id;") { row in
        "\(try row.text(0))|\(try row.text(1))|\(try row.text(2))|\(try row.text(3))"
    }
    let sources = try database.query("SELECT paper_id, source_type, source_id, version, url FROM paper_sources ORDER BY paper_id;") { row in
        "\(try row.text(0))|\(try row.text(1))|\(row.optionalText(2) ?? "")|\(row.optionalText(3) ?? "")|\(row.optionalText(4) ?? "")"
    }

    try check(paperColumns.contains("canonical_key"), "V2 migration should add canonical paper columns")
    try check(
        paperMetadata == [
            "paper-a|arxiv:2604.18586|arxiv|2604.18586|2604.18586",
            "paper-b|arxiv:2604.18587|arxiv|2604.18587|2604.18587v2"
        ],
        "V2 paper metadata should stay current after normal repository writes"
    )
    try check(folders == ["cat-methods||Methods", "cat-vae|cat-methods|VAE"], "V2 migration should backfill folders from categories")
    try check(folderCreatedAt.flatMap { ISO8601DateFormatter().date(from: $0) } != nil, "V2 folder membership timestamps should be ISO8601 dates")
    try check(
        fileRows == [
            "paper-a|saved_local|\(paper.filePath)|hash-a",
            "paper-b|cache_preview|\(versionedPaper.filePath)|hash-b"
        ],
        "V2 migration should backfill paper file records"
    )
    try check(
        sources == [
            "paper-a|arxiv|2604.18586||https://arxiv.org/abs/2604.18586",
            "paper-b|arxiv|2604.18587|v2|http://arxiv.org/pdf/2604.18587v2.pdf?download=1"
        ],
        "V2 migration should backfill arXiv source records"
    )

    try repository.migrate()
    let fileRowsAfterRemigration = try database.query("SELECT paper_id, storage_state, local_path, content_hash FROM paper_files ORDER BY paper_id;") { row in
        "\(try row.text(0))|\(try row.text(1))|\(try row.text(2))|\(try row.text(3))"
    }
    try check(fileRowsAfterRemigration == fileRows, "V2 migration should be idempotent after live repository writes")
}

func runLibraryDataStoreChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-library-store-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let repository = try PaperRepository(databasePath: tempRoot.appendingPathComponent("store.sqlite").path)
    try repository.migrate()
    let database = try SQLiteDatabase(path: tempRoot.appendingPathComponent("store.sqlite").path)
    let store = LibraryDataStore(database: database)
    let now = Date(timeIntervalSince1970: 1_777_300_000)
    let deletedAt = Date(timeIntervalSince1970: 1_777_300_100)
    let reassignedAt = Date(timeIntervalSince1970: 1_777_300_200)

    let folder = LibraryFolder(id: "folder-root", parentID: nil, name: "Root", sortOrder: 0, deletedAt: nil, syncRevision: 1)
    let deletedFolder = LibraryFolder(id: "folder-deleted", parentID: nil, name: "Deleted", sortOrder: 1, deletedAt: deletedAt, syncRevision: 2)
    let tag = HierarchicalPaperTag(id: "tag-ai", parentID: nil, name: "AI", color: "#0A84FF", sortOrder: 0, deletedAt: nil, syncRevision: 1)
    let deletedTag = HierarchicalPaperTag(id: "tag-deleted", parentID: nil, name: "Deleted", color: "#FF3B30", sortOrder: 1, deletedAt: deletedAt, syncRevision: 2)
    let note = PaperNote(id: "note-a", paperID: "paper-a", anchorID: nil, title: "Idea", bodyMarkdown: "Use in intro.", createdAt: now, updatedAt: now, deletedAt: nil, syncRevision: 1)
    try store.upsertFolder(folder)
    try store.upsertFolder(deletedFolder)
    try store.upsertTag(tag)
    try store.upsertTag(deletedTag)
    try repository.upsertPaper(Paper(id: "paper-a", filePath: "/tmp/a.pdf", fileHash: "hash-a", title: "A", authors: [], year: nil, sourceURL: nil, importedAt: now, updatedAt: now))
    try store.assignPaper("paper-a", toFolder: "folder-root", at: now)
    try store.assignPaper("paper-a", toFolder: "folder-deleted", at: now)
    try store.assignPaper("paper-a", toTag: "tag-ai", at: now)
    try store.assignPaper("paper-a", toTag: "tag-deleted", at: now)
    try store.upsertNote(note)

    try database.run("""
    UPDATE paper_folders SET deleted_at = ? WHERE paper_id = ? AND folder_id = ?;
    """, bindings: [
        .text(ISO8601DateFormatter().string(from: deletedAt)),
        .text("paper-a"),
        .text("folder-root")
    ])
    let folderIDsAfterSoftDelete = try store.fetchFolderIDs(forPaperID: "paper-a")
    try check(folderIDsAfterSoftDelete.isEmpty, "LibraryDataStore should hide soft-deleted folder memberships")
    try store.assignPaper("paper-a", toFolder: "folder-root", at: reassignedAt)

    let tagMembershipCreatedAt = try database.query("""
    SELECT created_at FROM paper_tag_memberships WHERE paper_id = ? AND tag_id = ?;
    """, bindings: [.text("paper-a"), .text("tag-ai")]) { row in
        try row.text(0)
    }.first

    let fetchedFolders = try store.fetchFolders()
    let fetchedTags = try store.fetchTags()
    let fetchedFolderIDs = try store.fetchFolderIDs(forPaperID: "paper-a")
    let fetchedTagIDs = try store.fetchTagIDs(forPaperID: "paper-a")
    let fetchedNotes = try store.fetchNotes(paperID: "paper-a")
    let legacyFetchedTags = try repository.fetchTags(forPaperID: "paper-a")
    try check(fetchedFolders == [folder], "LibraryDataStore should round-trip folders")
    try check(fetchedTags == [tag], "LibraryDataStore should round-trip hierarchical tags")
    try check(fetchedFolderIDs == ["folder-root"], "LibraryDataStore should round-trip folder memberships")
    try check(fetchedTagIDs == ["tag-ai"], "LibraryDataStore should round-trip tag memberships")
    try check(fetchedNotes == [note], "LibraryDataStore should round-trip paper notes")
    try check(tagMembershipCreatedAt.flatMap { ISO8601DateFormatter().date(from: $0) } == now, "LibraryDataStore should persist tag membership creation dates")
    try check(legacyFetchedTags.contains(PaperTag(id: "tag-ai", name: "AI")), "LibraryDataStore tag assignments should remain visible to legacy repository tag fetches")
}

func runArxivCacheDataStoreChecks() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-arxiv-cache-store-\(UUID().uuidString).sqlite")
    let repository = try PaperRepository(databasePath: databaseURL.path)
    try repository.migrate()
    let database = try SQLiteDatabase(path: databaseURL.path)
    let now = Date(timeIntervalSince1970: 1_777_300_000)
    let future = Date(timeInterval: 3_600, since: now)
    let past = Date(timeInterval: -3_600, since: now)
    let dates = ISO8601DateFormatter()
    let store = ArxivCacheDataStore(database: database, now: { now })

    let missingStatus = try store.feedCacheStatus(date: "2026-04-28")
    try check(!missingStatus.metadataCached, "arXiv cache store should report missing metadata cache")
    try check(missingStatus.cachedAssetCount == 0, "arXiv cache store should report zero assets for missing dates")
    try check(missingStatus.cachedPDFCount == 0, "arXiv cache store should report zero PDFs for missing dates")

    try store.upsertFeedDate(
        date: "2026-04-29",
        source: "codearxiv",
        feedVersion: "v1",
        filterSnapshotJSON: #"{"tags":[]}"#,
        cachedAt: now,
        expiresAt: nil
    )
    try database.run("""
    INSERT INTO arxiv_assets (
      asset_key, arxiv_id, date, kind, local_path, url, content_hash, byte_count, cached_at, last_accessed_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    """, bindings: [
        .text("asset:2604.18586:thumbnail"),
        .text("2604.18586"),
        .text("2026-04-29"),
        .text("thumbnail"),
        .text("/cache/2604.18586.png"),
        .text("https://example.test/2604.18586.png"),
        .text("hash-asset"),
        .int64(321),
        .text(dates.string(from: now)),
        .null
    ])
    try store.upsertPDFCache(
        arxivID: "2604.18586",
        date: "2026-04-29",
        localPath: "/cache/2604.18586.pdf",
        contentHash: "hash-pdf",
        byteCount: 123,
        cachedAt: now,
        lastAccessedAt: now,
        promotedPaperID: nil
    )
    let status = try store.feedCacheStatus(date: "2026-04-29")
    try check(status.metadataCached, "arXiv cache store should report metadata cache with nil expiry")
    try check(status.cachedAssetCount == 1, "arXiv cache store should count cached assets")
    try check(status.cachedPDFCount == 1, "arXiv cache store should count cached PDFs")

    try store.upsertFeedDate(
        date: "2026-04-30",
        source: "codearxiv",
        feedVersion: "v2",
        filterSnapshotJSON: #"{"tags":["ml"]}"#,
        cachedAt: now,
        expiresAt: future
    )
    try store.upsertFeedDate(
        date: "2026-05-01",
        source: "codearxiv",
        feedVersion: "v3",
        filterSnapshotJSON: nil,
        cachedAt: now,
        expiresAt: past
    )
    try store.upsertFeedDate(
        date: "2026-05-02",
        source: "codearxiv",
        feedVersion: nil,
        filterSnapshotJSON: nil,
        cachedAt: now,
        expiresAt: nil
    )
    try store.upsertFeedDate(
        date: "2026-05-03",
        source: "codearxiv",
        feedVersion: "v4",
        filterSnapshotJSON: nil,
        cachedAt: now,
        expiresAt: now
    )

    let futureStatus = try store.feedCacheStatus(date: "2026-04-30")
    let expiredStatus = try store.feedCacheStatus(date: "2026-05-01")
    let nullableFeedStatus = try store.feedCacheStatus(date: "2026-05-02")
    let equalExpiryStatus = try store.feedCacheStatus(date: "2026-05-03")
    try check(futureStatus.metadataCached, "arXiv cache store should report metadata cache with future expiry")
    try check(!expiredStatus.metadataCached, "arXiv cache store should ignore expired metadata cache")
    try check(nullableFeedStatus.metadataCached, "arXiv cache store should accept nullable feed metadata fields")
    try check(!equalExpiryStatus.metadataCached, "arXiv cache store should require expiry to be strictly later than now")

    try store.upsertPDFCache(
        arxivID: "2604.18586",
        date: "2026-04-30",
        localPath: "/cache/2604.18586-v2.pdf",
        contentHash: "hash-pdf-updated",
        byteCount: 456,
        cachedAt: now,
        lastAccessedAt: nil,
        promotedPaperID: nil
    )
    try store.upsertPDFCache(
        arxivID: "2604.18587",
        date: "2026-05-02",
        localPath: "/cache/2604.18587.pdf",
        contentHash: nil,
        byteCount: nil,
        cachedAt: now,
        lastAccessedAt: nil,
        promotedPaperID: nil
    )

    let oldDateStatus = try store.feedCacheStatus(date: "2026-04-29")
    let updatedDateStatus = try store.feedCacheStatus(date: "2026-04-30")
    let nullablePDFStatus = try store.feedCacheStatus(date: "2026-05-02")
    let updatedPDFRows = try database.query("""
    SELECT date, local_path, content_hash, byte_count, last_accessed_at, promoted_paper_id
    FROM arxiv_pdf_cache
    WHERE arxiv_id = ?;
    """, bindings: [.text("2604.18586")]) { row in
        "\(try row.text(0))|\(try row.text(1))|\(row.optionalText(2) ?? "")|\(row.optionalInt(3).map(String.init) ?? "")|\(row.optionalText(4) ?? "")|\(row.optionalText(5) ?? "")"
    }
    let nullablePDFRows = try database.query("""
    SELECT content_hash, byte_count, last_accessed_at, promoted_paper_id
    FROM arxiv_pdf_cache
    WHERE arxiv_id = ?;
    """, bindings: [.text("2604.18587")]) { row in
        "\(row.optionalText(0) ?? "")|\(row.optionalInt(1).map(String.init) ?? "")|\(row.optionalText(2) ?? "")|\(row.optionalText(3) ?? "")"
    }

    try check(oldDateStatus.cachedPDFCount == 0, "arXiv cache store should move updated PDFs away from old feed dates")
    try check(updatedDateStatus.cachedPDFCount == 1, "arXiv cache store should count updated PDFs under the latest feed date")
    try check(
        updatedPDFRows == ["2026-04-30|/cache/2604.18586-v2.pdf|hash-pdf-updated|456||"],
        "arXiv cache store should update cached PDF path, hash, and byte count"
    )
    try check(nullablePDFStatus.cachedPDFCount == 1, "arXiv cache store should count PDF caches with nullable fields")
    try check(nullablePDFRows == ["|||"], "arXiv cache store should persist nullable PDF cache fields")
}

func runSyncDataStoreChecks() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-sync-store-\(UUID().uuidString).sqlite")
    let repository = try PaperRepository(databasePath: databaseURL.path)
    try repository.migrate()
    let database = try SQLiteDatabase(path: databaseURL.path)
    let syncEntityColumns = try database.tableColumns("sync_entities")
    let store = SyncDataStore(database: database)
    let dates = ISO8601DateFormatter()
    let now = Date(timeIntervalSince1970: 1_777_300_000)
    let retryAt = Date(timeIntervalSince1970: 1_777_300_060)
    let tombstoneAt = Date(timeIntervalSince1970: 1_777_300_500)

    try check(syncEntityColumns.contains("local_updated_at"), "V2 migration should create sync entity local update timestamps")
    try store.markDirty(entityType: "paper", entityID: "paper-a", localRevision: 2, deleted: false, at: now)
    try store.markDirty(entityType: "paper", entityID: "paper-a", localRevision: 5, deleted: true, at: tombstoneAt)
    try store.markDirty(entityType: "paper", entityID: "paper-a", localRevision: 3, deleted: false, at: now)
    try store.enqueue(
        id: "change-a",
        entityType: "paper",
        entityID: "paper-a",
        operation: "upsert",
        payloadJSON: #"{"id":"paper-a"}"#,
        baseRemoteRevision: nil,
        createdAt: now
    )
    try store.enqueue(
        id: "change-a",
        entityType: "paper",
        entityID: "paper-a",
        operation: "upsert",
        payloadJSON: #"{"id":"paper-a"}"#,
        baseRemoteRevision: nil,
        createdAt: retryAt
    )
    var conflictingDuplicateError: String?
    do {
        try store.enqueue(
            id: "change-a",
            entityType: "paper",
            entityID: "paper-a",
            operation: "delete",
            payloadJSON: #"{"id":"paper-a","deleted":true}"#,
            baseRemoteRevision: 4,
            createdAt: now
        )
    } catch {
        conflictingDuplicateError = String(describing: error)
    }
    var conflictingEntityError: String?
    do {
        try store.enqueue(
            id: "change-a",
            entityType: "paper",
            entityID: "paper-b",
            operation: "upsert",
            payloadJSON: #"{"id":"paper-a"}"#,
            baseRemoteRevision: nil,
            createdAt: now
        )
    } catch {
        conflictingEntityError = String(describing: error)
    }
    try store.setCursor(scope: "library", cursor: "cursor-1", updatedAt: now)

    let dirtyEntityIDs = try store.fetchDirtyEntityIDs(entityType: "paper")
    let pendingOutboxIDs = try store.fetchPendingOutboxIDs()
    let cursor = try store.fetchCursor(scope: "library")
    let syncEntityRows = try database.query("""
    SELECT local_revision, deleted, local_updated_at
    FROM sync_entities
    WHERE entity_type = ? AND entity_id = ?;
    """, bindings: [.text("paper"), .text("paper-a")]) { row in
        "\(row.int(0))|\(row.int(1))|\(try row.text(2))"
    }
    let outboxCount = try database.query("""
    SELECT COUNT(*)
    FROM sync_outbox
    WHERE id = ?;
    """, bindings: [.text("change-a")]) { row in
        row.int(0)
    }.first
    let outboxCreatedAt = try database.query("""
    SELECT created_at
    FROM sync_outbox
    WHERE id = ?;
    """, bindings: [.text("change-a")]) { row in
        try row.text(0)
    }.first

    try check(dirtyEntityIDs == ["paper-a"], "SyncDataStore should track dirty entities")
    try check(syncEntityRows == ["5|1|\(dates.string(from: tombstoneAt))"], "SyncDataStore should preserve max dirty revision, tombstone, and update timestamp")
    try check(pendingOutboxIDs == ["change-a"], "SyncDataStore should track pending outbox changes")
    try check(outboxCount == 1, "SyncDataStore should treat exact duplicate outbox IDs as idempotent")
    try check(outboxCreatedAt == dates.string(from: now), "SyncDataStore should keep the original outbox creation date")
    try check(conflictingDuplicateError?.contains("change-a") == true, "SyncDataStore should reject conflicting duplicate outbox IDs")
    try check(conflictingEntityError?.contains("change-a") == true, "SyncDataStore should reject duplicate outbox IDs with different entities")
    try check(cursor == "cursor-1", "SyncDataStore should persist cursors")
}

func runSQLiteHelperChecks() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-sqlite-helpers-\(UUID().uuidString).sqlite")
    let database = try SQLiteDatabase(path: databaseURL.path)
    try database.transaction {
        try database.execute("CREATE TABLE sample (id TEXT PRIMARY KEY, value TEXT);")
        try database.run("INSERT INTO sample (id, value) VALUES (?, ?);", bindings: [.text("a"), .text("one")])
    }

    let columns = try database.tableColumns("sample")
    let values = try database.query("SELECT value FROM sample WHERE id = ?;", bindings: [.text("a")]) { row in
        try row.text(0)
    }

    try check(columns == Set(["id", "value"]), "SQLite tableColumns should read table schema")
    try check(values == ["one"], "SQLite transaction should commit successful work")
}

func runCitationChecks() throws {
    let parsed = CitationParser.parse("Answer [[cite:paper:paper-a:p5:b17]] and [[cite:paper:paper-a:p5:asel1]].")
    try check(parsed.citations.map(\.id) == ["paper:paper-a:p5:b17", "paper:paper-a:p5:asel1"], "citation parser should preserve citation IDs")
    try check(parsed.displayText == "Answer [1] and [2].", "citation parser should replace markers with display indices")
    try check(parsed.displayMarkdown.contains("[1](papercodex-cite://open?id=paper%3Apaper-a%3Ap5%3Ab17)"), "citation parser should produce inline clickable markdown links")
    try check(parsed.displayMarkdown.contains("[2](papercodex-cite://open?id=paper%3Apaper-a%3Ap5%3Aasel1)"), "citation parser should keep anchor citations clickable inline")

    let manyCitations = CitationParser.parse(
        "A [[cite:paper:paper-a:p1:b1]] B [[cite:paper:paper-a:p1:b2]] C [[cite:paper:paper-a:p1:b3]] D [[cite:paper:paper-a:p1:b4]]",
        maxVisibleCitations: 3
    )
    try check(manyCitations.citations.map(\.displayIndex) == [1, 2, 3], "citation parser should cap visible citations")
    try check(!manyCitations.displayMarkdown.contains("p1%3Ab4"), "citation parser should omit citation links above the visible cap")
    try check(manyCitations.displayText == "A [1] B [2] C [3] D ", "citation parser should remove extra citation markers from display text")
    try check(
        CitationParser.baseSpanCitationID(for: "paper:paper-a:p1:b17s2") == "paper:paper-a:p1:b17",
        "split citation aliases should resolve to their original span citation"
    )

    let malformed = CitationParser.parse("Broken [[cite:not-a-paper]] marker.")
    try check(malformed.citations.isEmpty, "malformed markers should not become citations")
    try check(malformed.brokenMarkers == ["[[cite:not-a-paper]]"], "malformed markers should be reported")

    let rendered = ChatMarkdownRenderer.renderDocument(
        markdown: "## Result\n\nValue $x^2$.\n\n![figure](/tmp/figure.png)\n\n\(parsed.displayMarkdown)"
    )
    try check(rendered.contains("window.MathJax"), "markdown renderer should configure MathJax for formulas")
    try check(rendered.contains("<h2>Result</h2>"), "markdown renderer should render markdown headings")
    try check(rendered.contains(#"<img alt="figure" src="file:///tmp/figure.png">"#), "markdown renderer should render absolute local images")
    try check(rendered.contains(#"href="papercodex-cite://open?id=paper%3Apaper-a%3Ap5%3Ab17""#), "markdown renderer should preserve clickable citation links")
}

func runUserSourceAttachmentChecks() throws {
    let message = """
    Compare this with the method section.

    [selected source]
    anchor_id: paper:paper-a:p3:aselection
    paper_id: paper-a
    page: 3
    text: "The selected paragraph explains the training objective."
    nearby_spans: paper:paper-a:p3:b9
    before: "Previous paragraph."
    after: "Next paragraph."
    """

    let parsed = UserSourceAttachmentParser.parse(message)
    try check(parsed.visibleContent == "Compare this with the method section.", "user source attachment parser should hide selected-source metadata from chat display")
    try check(parsed.attachment?.anchorID == "paper:paper-a:p3:aselection", "user source attachment should keep its anchor citation ID")
    try check(parsed.attachment?.paperID == "paper-a", "user source attachment should keep the selected paper ID")
    try check(parsed.attachment?.page == 3, "user source attachment should keep the selected page")
    try check(parsed.attachment?.selectedText == "The selected paragraph explains the training objective.", "user source attachment should keep the selected text")

    let plain = UserSourceAttachmentParser.parse("No attached source.")
    try check(plain.visibleContent == "No attached source.", "plain user messages should remain unchanged")
    try check(plain.attachment == nil, "plain user messages should not create source attachments")
}

func runAnchorResolverChecks() throws {
    let before = Span(
        id: Span.makeID(paperID: "paper-a", page: 2, blockIndex: 1),
        paperID: "paper-a",
        page: 2,
        bbox: BoundingBox(x: 20, y: 720, width: 300, height: 20),
        text: "Before context explains the setup.",
        charRange: TextRange(location: 0, length: 34),
        sectionHint: nil,
        confidence: 0.95
    )
    let target = Span(
        id: Span.makeID(paperID: "paper-a", page: 2, blockIndex: 2),
        paperID: "paper-a",
        page: 2,
        bbox: BoundingBox(x: 20, y: 690, width: 360, height: 22),
        text: "The selected mechanism controls latent trajectories.",
        charRange: TextRange(location: 35, length: 52),
        sectionHint: nil,
        confidence: 0.95
    )
    let after = Span(
        id: Span.makeID(paperID: "paper-a", page: 2, blockIndex: 3),
        paperID: "paper-a",
        page: 2,
        bbox: BoundingBox(x: 20, y: 660, width: 300, height: 20),
        text: "After context describes the consequence.",
        charRange: TextRange(location: 88, length: 39),
        sectionHint: nil,
        confidence: 0.95
    )
    let otherPage = Span(
        id: Span.makeID(paperID: "paper-a", page: 3, blockIndex: 1),
        paperID: "paper-a",
        page: 3,
        bbox: BoundingBox(x: 20, y: 690, width: 360, height: 22),
        text: "A different page should not be matched.",
        charRange: TextRange(location: 0, length: 39),
        sectionHint: nil,
        confidence: 0.95
    )

    guard let anchor = AnchorResolver().resolve(
        paperID: "paper-a",
        page: 2,
        selectedText: "controls latent trajectories",
        bboxList: [BoundingBox(x: 40, y: 686, width: 220, height: 28)],
        spans: [before, target, after, otherPage],
        anchorID: Anchor.makeID(paperID: "paper-a", page: 2, suffix: "sel1"),
        sessionID: "session-a",
        createdAt: Date(timeIntervalSince1970: 1_777_220_000)
    ) else {
        throw CheckFailure(description: "anchor resolver should return an anchor for a matched selection")
    }

    try check(anchor.matchedSpanIDs == [target.id], "anchor resolver should match the selected page span")
    try check(anchor.beforeContext == before.text, "anchor resolver should include preceding span context")
    try check(anchor.afterContext == after.text, "anchor resolver should include following span context")
    try check(anchor.confidence > 0.8, "anchor resolver should assign high confidence for text and bbox matches")

    let unmatchedAnchor = AnchorResolver().resolve(
        paperID: "paper-a",
        page: 2,
        selectedText: "unrelated words from a different document",
        bboxList: [BoundingBox(x: 500, y: 120, width: 40, height: 18)],
        spans: [before, target, after, otherPage],
        anchorID: Anchor.makeID(paperID: "paper-a", page: 2, suffix: "missing"),
        sessionID: "session-a",
        createdAt: Date(timeIntervalSince1970: 1_777_220_000)
    )
    try check(unmatchedAnchor == nil, "anchor resolver should not create a fake anchor when matching fails")
}

func runPromptChecks() throws {
    let now = Date(timeIntervalSince1970: 1_777_220_000)
    let paper = Paper(
        id: "paper-a",
        filePath: "/tmp/paper.pdf",
        fileHash: "hash-a",
        title: "Paper A",
        authors: ["Alice"],
        year: 2026,
        sourceURL: "https://example.com/paper",
        importedAt: now,
        updatedAt: now
    )
    let span = Span(
        id: Span.makeID(paperID: "paper-a", page: 5, blockIndex: 17),
        paperID: "paper-a",
        page: 5,
        bbox: BoundingBox(x: 1, y: 2, width: 3, height: 4),
        text: "This curated span should stay in workspace files instead of being inlined.",
        charRange: TextRange(location: 0, length: 52),
        sectionHint: "Method",
        confidence: 0.9
    )
    let anchor = Anchor(
        id: Anchor.makeID(paperID: "paper-a", page: 5, suffix: "sel1"),
        paperID: "paper-a",
        page: 5,
        selectedText: "controls latent trajectories",
        bboxList: [span.bbox],
        matchedSpanIDs: [span.id],
        beforeContext: "The selected mechanism",
        afterContext: "with a decoder.",
        createdSessionID: "session-a",
        createdAt: now,
        confidence: 0.87
    )
    let prompt = PromptBuilder().buildPrompt(
        request: PromptRequest(
            userMessage: "Compare this selection with Paper B.",
            workspacePath: "/tmp/session-a",
            papers: [paper],
            selectedAnchors: [anchor],
            relevantSpans: [span]
        )
    )

    try check(prompt.contains("Compare this selection with Paper B."), "prompt should include the user message")
    try check(prompt.contains("Global language preference: Automatic"), "prompt should include the default automatic language preference")
    try check(PaperCodexLanguageMode.chinese.discoverLanguageCode == "zh", "Chinese language mode should prefer Chinese discover metadata")
    try check(PaperCodexLanguageMode.english.discoverLanguageCode == "en", "English language mode should prefer English discover metadata")
    try check(PaperCodexLanguageMode.automatic.metadataLanguageCode == "en", "automatic language mode should preserve English library metadata by default")
    try check(prompt.contains("anchor_id: paper:paper-a:p5:asel1"), "prompt should include selected anchor ID")
    try check(prompt.contains("workspace: /tmp/session-a"), "prompt should include workspace guidance")
    try check(prompt.contains("original_pdf: /tmp/session-a/papers/paper-a/original.pdf"), "prompt should point Codex at the workspace PDF copy")
    try check(prompt.contains("full_text: /tmp/session-a/papers/paper-a/full_text.txt"), "prompt should point Codex at the full text workspace file")
    try check(prompt.contains("spans_jsonl: /tmp/session-a/papers/paper-a/spans.jsonl"), "prompt should point Codex at the full span index")
    try check(prompt.contains("[[cite:paper:{paper_id}:p{page}:b{block_index}]]"), "prompt should include citation contract")
    try check(prompt.contains("Use citations sparingly"), "prompt should ask Codex to keep citation count low")
    try check(prompt.contains("at most three citation markers"), "prompt should hard-limit normal citation count")
    try check(prompt.contains("research trends"), "default system prompt should cover broader research trend analysis")
    try check(prompt.contains("broader research landscape"), "default system prompt should connect papers to the wider research landscape")
    try check(prompt.contains("Match the user's language"), "default system prompt should require language matching")
    try check(prompt.contains("Do not begin with praise"), "default system prompt should prevent generic praise openings")
    try check(prompt.contains("Do not invent paper links"), "default system prompt should forbid fabricated paper links")
    try check(prompt.contains("Use `$...$` for inline math"), "default system prompt should specify render-safe LaTeX conventions")
    try check(!prompt.localizedCaseInsensitiveContains("alphaxiv"), "default system prompt should not retain alphaXiv-specific product instructions")
    try check(!prompt.contains("<alphaxiv"), "default system prompt should not emit alphaXiv-specific XML tags")
    try check(!prompt.contains("[relevant span]"), "prompt should not inline a limited curated span list")
    try check(!prompt.contains("This curated span should stay in workspace files"), "prompt should make Codex inspect workspace files instead of reading a narrowed prompt excerpt")

    try check(PromptBuilder.defaultSystemPrompt.contains("{{workspace_path}}"), "default Codex system prompt should be editable as a workspace-aware template")
    let customPrompt = PromptBuilder().buildPrompt(
        request: PromptRequest(
            userMessage: "Explain Figure 2.",
            workspacePath: "/tmp/custom-session",
            papers: [paper],
            selectedAnchors: [],
            relevantSpans: [],
            systemPromptTemplate: "CUSTOM CODEX SYSTEM\nworkspace: {{workspace_path}}\nAnswer in Chinese."
        )
    )
    try check(customPrompt.hasPrefix("CUSTOM CODEX SYSTEM"), "custom Codex system prompt should replace the built-in default")
    try check(customPrompt.contains("workspace: /tmp/custom-session"), "custom Codex system prompt should render the workspace placeholder")
    try check(!customPrompt.contains("Use citations sparingly"), "custom Codex system prompt should not silently append the default instructions")
    let englishPrompt = PromptBuilder().buildPrompt(
        request: PromptRequest(
            userMessage: "Explain Figure 2.",
            workspacePath: "/tmp/custom-session",
            papers: [paper],
            selectedAnchors: [],
            relevantSpans: [],
            languageMode: .english
        )
    )
    try check(englishPrompt.contains("Global language preference: English"), "prompt should include the English global language preference")
    try check(englishPrompt.contains("Answer in English by default"), "English language mode should ask Codex to answer in English")
    try check(englishPrompt.contains("[global language]"), "English prompt should keep English section labels")
    let chinesePrompt = PromptBuilder().buildPrompt(
        request: PromptRequest(
            userMessage: "Explain Figure 2.",
            workspacePath: "/tmp/custom-session",
            papers: [paper],
            selectedAnchors: [],
            relevantSpans: [],
            languageMode: .chinese
        )
    )
    try check(chinesePrompt.contains("你是 Paper Codex 中的 Codex"), "Chinese language mode should switch the full system prompt to Chinese")
    try check(chinesePrompt.contains("全局语言偏好：中文"), "prompt should include the Chinese global language preference")
    try check(chinesePrompt.contains("[全局语言]"), "Chinese prompt should switch prompt section labels to Chinese")
    try check(!chinesePrompt.contains("[global language]"), "Chinese prompt should not keep English-only language section labels")
    try check(!chinesePrompt.contains("Response style:"), "Chinese language mode should not keep the English built-in system prompt")
}

func runWorkspaceChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-workspace-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let sourcePDF = tempRoot.appendingPathComponent("source.pdf")
    try writeFixturePDF(to: sourcePDF, lines: ["Page text"])
    let workspaceRoot = tempRoot.appendingPathComponent("workspace", isDirectory: true)
    let now = Date(timeIntervalSince1970: 1_777_220_000)
    let paper = Paper(
        id: "paper-a",
        filePath: sourcePDF.path,
        fileHash: "hash-a",
        title: "Paper A",
        authors: ["Alice"],
        year: 2026,
        sourceURL: nil,
        importedAt: now,
        updatedAt: now
    )
    let session = PaperSession(
        id: "session-a",
        title: "Mechanism Notes",
        paperIDs: ["paper-a"],
        codexSessionID: nil,
        workspacePath: workspaceRoot.path,
        createdAt: now,
        updatedAt: now
    )
    let page = PageIndex(paperID: "paper-a", page: 1, text: "Page text", confidence: 0.95)
    let span = Span(
        id: Span.makeID(paperID: "paper-a", page: 1, blockIndex: 1),
        paperID: "paper-a",
        page: 1,
        bbox: BoundingBox(x: 1, y: 2, width: 3, height: 4),
        text: "Page text continues",
        charRange: TextRange(location: 0, length: 9),
        sectionHint: nil,
        confidence: 0.95
    )
    let wrappedSpan = Span(
        id: Span.makeID(paperID: "paper-a", page: 1, blockIndex: 2),
        paperID: "paper-a",
        page: 1,
        bbox: BoundingBox(x: 1, y: 20, width: 5, height: 4),
        text: "onto the next visual line.",
        charRange: TextRange(location: 20, length: 26),
        sectionHint: nil,
        confidence: 0.95
    )
    let anchor = Anchor(
        id: Anchor.makeID(paperID: "paper-a", page: 1, suffix: "sel1"),
        paperID: "paper-a",
        page: 1,
        selectedText: "Page text",
        bboxList: [span.bbox],
        matchedSpanIDs: [span.id],
        beforeContext: "",
        afterContext: "",
        createdSessionID: "session-a",
        createdAt: now,
        confidence: 0.95
    )

    try SessionWorkspaceManager().writeWorkspace(
        session: session,
        papers: [paper],
        pagesByPaperID: ["paper-a": [page]],
        spansByPaperID: ["paper-a": [span, wrappedSpan]],
        anchorsByPaperID: ["paper-a": [anchor]]
    )

    let paperDir = workspaceRoot.appendingPathComponent("papers/paper-a", isDirectory: true)
    try check(FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent("session.json").path), "workspace should contain session.json")
    try check(FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent("prompt_contract.md").path), "workspace should contain prompt contract")
    try check(FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent("turns", isDirectory: true).path), "workspace should contain turns directory")
    try check(FileManager.default.fileExists(atPath: paperDir.appendingPathComponent("metadata.json").path), "workspace should contain paper metadata")
    try check(FileManager.default.fileExists(atPath: paperDir.appendingPathComponent("original.pdf").path), "workspace should contain a readable copy of the original PDF")
    try check(FileManager.default.fileExists(atPath: paperDir.appendingPathComponent("full_text.txt").path), "workspace should contain full extracted text with citations")
    try check(FileManager.default.fileExists(atPath: paperDir.appendingPathComponent("pages.jsonl").path), "workspace should contain pages jsonl")
    try check(FileManager.default.fileExists(atPath: paperDir.appendingPathComponent("spans.jsonl").path), "workspace should contain spans jsonl")
    try check(FileManager.default.fileExists(atPath: paperDir.appendingPathComponent("anchors.jsonl").path), "workspace should contain anchors jsonl")

    let spans = try String(contentsOf: paperDir.appendingPathComponent("spans.jsonl"), encoding: .utf8)
    try check(spans.contains("paper:paper-a:p1:b1"), "spans jsonl should include span ID")
    try check(spans.split(separator: "\n").count == 1, "workspace spans should compact wrapped visual lines into one citation block")
    try check(spans.contains("Page text continues onto the next visual line."), "compacted workspace span should contain merged visual-line text")
    let fullText = try String(contentsOf: paperDir.appendingPathComponent("full_text.txt"), encoding: .utf8)
    try check(fullText.contains("original_pdf: \(paperDir.appendingPathComponent("original.pdf").path)"), "full text should point to the local workspace PDF copy")
    try check(fullText.contains("[[cite:paper:paper-a:p1:b1]] Page text continues onto the next visual line."), "full text should include compacted extracted spans with exact citation markers")
}

func runPDFChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-pdf-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let pdfURL = tempRoot.appendingPathComponent("fixture.pdf")
    try writeFixturePDF(
        to: pdfURL,
        lines: [
            "Paper Codex extracts selectable text.",
            "This paragraph becomes a stable span."
        ]
    )

    let index = try PDFIndexExtractor().extract(paperID: "paper-a", pdfURL: pdfURL)
    try check(index.pages.count == 1, "fixture PDF should produce one page")
    try check(index.pages[0].text.contains("Paper Codex extracts selectable text."), "page text should contain first fixture line")
    try check(index.spans.contains { $0.text.contains("stable span") }, "spans should include selectable text")
    try check(index.spans.allSatisfy { $0.page == 1 }, "spans should use one-based page numbers")
    try check(index.spans.allSatisfy { $0.bbox.width > 0 && $0.bbox.height > 0 }, "spans should include non-empty bounding boxes")

    guard let document = PDFDocument(url: pdfURL),
          let page = document.page(at: 0),
          let text = page.string,
          let selection = page.selection(for: NSRange(location: 0, length: text.count)) else {
        throw CheckFailure(description: "could not create fixture PDF selection")
    }
    let capturedSelection = PDFSelectionGeometry.capture(selection: selection, in: document)
    try check(capturedSelection?.page == 1, "captured PDF selection should use one-based page numbers")
    try check(capturedSelection?.bboxList.count == 2, "captured multiline PDF selection should preserve per-line boxes")
    try check(capturedSelection?.text.contains("stable span") == true, "captured PDF selection should preserve selected text")

    let abstractPDFURL = tempRoot.appendingPathComponent("abstract.pdf")
    try writeFixturePDF(
        to: abstractPDFURL,
        lines: [
            "Transformer-based large language models have considerably",
            "advanced our understanding of language in the human",
            "brain; however, their validity is questioned.",
            "Autoregressive transformers are increasingly used in neuroscience.",
            "They support studies of language processing at scale",
            "while preserving source citation locality."
        ]
    )
    let abstractIndex = try PDFIndexExtractor().extract(paperID: "paper-b", pdfURL: abstractPDFURL)
    try check(abstractIndex.spans.count == 2, "wrapped paragraph lines should be merged into medium citation spans")
    try check(abstractIndex.spans[0].text.contains("considerably advanced"), "merged citation span should join wrapped lines")
    try check(abstractIndex.spans[0].text.contains("validity is questioned."), "merged citation span should keep the paragraph ending")
    try check(abstractIndex.spans.allSatisfy { $0.text.count <= 420 }, "citation spans should not become oversized blocks")

    let resolver = PDFReferenceResolver(pageTexts: [
        1: """
        Representation learning is widely used in sequence modeling [1, 2].
        Another body citation uses an author year form (Vaswani et al., 2017).

        References
        [1] Vaswani, A., Shazeer, N., Parmar, N. Attention Is All You Need. NeurIPS 2017.
        [2] Ho, J., Jain, A., Abbeel, P. Denoising Diffusion Probabilistic Models. NeurIPS 2020.
        """
    ])
    let numericPreview = resolver.preview(forLine: "Representation learning is widely used in sequence modeling [1, 2].", page: 1)
    try check(numericPreview?.citationText == "[1, 2]", "PDF resolver should extract the clicked numeric citation marker")
    try check(numericPreview?.references.map(\.marker) == ["1", "2"], "PDF resolver should map numeric in-text citations to reference entries")
    let clickedNumericPreview = resolver.preview(forLine: "Representation learning is widely used in sequence modeling [1, 2].", clickedText: "2", page: 1)
    try check(clickedNumericPreview?.references.map(\.marker) == ["1", "2"], "PDF resolver should open a numeric preview when the clicked word is inside the citation")
    let clickedBodyTextPreview = resolver.preview(forLine: "Representation learning is widely used in sequence modeling [1, 2].", clickedText: "Representation", page: 1)
    try check(clickedBodyTextPreview == nil, "PDF resolver should not steal ordinary text clicks from citation-bearing lines")
    let authorYearPreview = resolver.preview(forLine: "Another body citation uses an author year form (Vaswani et al., 2017).", page: 1)
    try check(authorYearPreview?.references.first?.text.contains("Attention Is All You Need") == true, "PDF resolver should map author-year citations to matching reference text")
    let clickedAuthorPreview = resolver.preview(forLine: "Vaswani et al. (2017) introduced a transformer architecture.", clickedText: "Vaswani", page: 1)
    try check(clickedAuthorPreview?.references.first?.text.contains("Attention Is All You Need") == true, "PDF resolver should support narrative author-year citation clicks")
    let referenceEntry = resolver.referenceEntry(containingLine: "[2] Ho, J., Jain, A., Abbeel, P. Denoising Diffusion Probabilistic Models. NeurIPS 2020.", page: 1)
    try check(referenceEntry?.title == "Denoising Diffusion Probabilistic Models", "PDF resolver should parse reference-list entries into cards")
    let referencePreview = resolver.preview(forLine: "[1] Vaswani, A., Shazeer, N., Parmar, N. Attention Is All You Need. NeurIPS 2017.", page: 1)
    try check(referencePreview == nil, "reference-list lines should not be treated as ordinary in-text citation popups")
    let unnumberedResolver = PDFReferenceResolver(pageTexts: [
        3: """
        References
        Vaswani, A., Shazeer, N., Parmar, N. (2017). Attention Is All You Need. NeurIPS.
        Ho, J., Jain, A., Abbeel, P. (2020). Denoising Diffusion Probabilistic Models. NeurIPS.
        """
    ])
    let unnumberedPreview = unnumberedResolver.preview(forLine: "Transformer baselines remain common (Vaswani et al., 2017).", clickedText: "2017", page: 3)
    try check(unnumberedPreview?.references.first?.title == "Attention Is All You Need", "PDF resolver should parse unnumbered author-year references")
    let unnumberedReferenceEntry = unnumberedResolver.referenceEntry(containingLine: "Ho, J., Jain, A., Abbeel, P. (2020). Denoising Diffusion Probabilistic Models. NeurIPS.", page: 3)
    try check(unnumberedReferenceEntry?.title == "Denoising Diffusion Probabilistic Models", "PDF resolver should render unnumbered references as cards")
}

func runCodexCLIChecks() throws {
    let codexPath = try CodexCLI.findCodexExecutable()
    try check(FileManager.default.isExecutableFile(atPath: codexPath), "codex executable should be runnable")

    let cli = CodexCLI(executablePath: codexPath)
    let isolatedWorkingDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-codex-cli-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: isolatedWorkingDirectory, withIntermediateDirectories: true)
    let sanitizedEnvironment = CodexCLI.sanitizedProcessEnvironment(
        workingDirectoryURL: isolatedWorkingDirectory,
        baseEnvironment: [
            "HOME": "/Users/chunqiu",
            "PWD": "/Users/chunqiu/Documents/New project 2",
            "OLDPWD": "/Users/chunqiu/Documents"
        ]
    )
    let isolatedWorkingDirectoryPath = isolatedWorkingDirectory.standardizedFileURL.path
    try check(sanitizedEnvironment["PWD"] == isolatedWorkingDirectoryPath, "Codex subprocesses should advertise the explicit working directory")
    try check(sanitizedEnvironment["OLDPWD"] == nil, "Codex subprocesses should not inherit protected-folder OLDPWD values")
    try check(sanitizedEnvironment["HOME"] == "/Users/chunqiu", "Codex subprocess environment should preserve unrelated variables")
    let pwdOutput = try CodexCLI(executablePath: "/bin/pwd")
        .run(arguments: [], currentDirectoryURL: isolatedWorkingDirectory)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    try check(pwdOutput == isolatedWorkingDirectoryPath, "Codex subprocesses should run from the explicit working directory")
    let start = cli.startArguments(prompt: "hello", workspacePath: "/tmp/session-a")
    try check(start == ["exec", "--skip-git-repo-check", "--json", "--enable", "image_generation", "-C", "/tmp/session-a", "hello"], "start args should allow non-git session workspaces with image generation enabled")
    let startWithOutput = cli.startArguments(prompt: "hello", workspacePath: "/tmp/session-a", outputLastMessagePath: "/tmp/last.txt")
    try check(startWithOutput == ["exec", "--skip-git-repo-check", "--json", "--enable", "image_generation", "-C", "/tmp/session-a", "--output-last-message", "/tmp/last.txt", "hello"], "start args should support output-last-message")
    let startWithModel = cli.startArguments(prompt: "hello", workspacePath: "/tmp/session-a", outputLastMessagePath: "/tmp/last.txt", modelOverride: "gpt-5.4")
    try check(startWithModel == ["exec", "--skip-git-repo-check", "--json", "--enable", "image_generation", "--model", "gpt-5.4", "-C", "/tmp/session-a", "--output-last-message", "/tmp/last.txt", "hello"], "start args should support an app-local model override")
    let startWithReasoning = cli.startArguments(prompt: "hello", workspacePath: "/tmp/session-a", reasoningEffort: .high)
    try check(startWithReasoning == ["exec", "--skip-git-repo-check", "--json", "--enable", "image_generation", "-c", "model_reasoning_effort=\"high\"", "-C", "/tmp/session-a", "hello"], "start args should support an app-local reasoning effort override")
    let startWithDefaultReasoning = cli.startArguments(prompt: "hello", workspacePath: "/tmp/session-a", reasoningEffort: .default)
    try check(startWithDefaultReasoning == start, "default reasoning effort should not add a Codex config override")

    let resume = cli.resumeArguments(sessionID: "session-a", prompt: "continue")
    try check(resume == ["exec", "resume", "--skip-git-repo-check", "--json", "--enable", "image_generation", "session-a", "continue"], "resume args should use codex exec resume with JSON output and image generation enabled")
    let resumeWithModel = cli.resumeArguments(sessionID: "session-a", prompt: "continue", modelOverride: "gpt-5.4")
    try check(resumeWithModel == ["exec", "resume", "--skip-git-repo-check", "--json", "--enable", "image_generation", "--model", "gpt-5.4", "session-a", "continue"], "resume args should support an app-local model override")
    let resumeWithReasoning = cli.resumeArguments(sessionID: "session-a", prompt: "continue", reasoningEffort: .xhigh)
    try check(resumeWithReasoning == ["exec", "resume", "--skip-git-repo-check", "--json", "--enable", "image_generation", "-c", "model_reasoning_effort=\"xhigh\"", "session-a", "continue"], "resume args should support an app-local reasoning effort override")
    let parsedThreadID = CodexCLI.parseThreadID(from: #"{"type":"thread.started","thread_id":"019dcaf6-01d5-7060-bc43-40401e3693c3"}"#)
    try check(parsedThreadID == "019dcaf6-01d5-7060-bc43-40401e3693c3", "Codex thread ID should be parsed from JSONL output")

    let threadEvent = try CodexJSONEventParser.parseLine(#"{"type":"thread.started","thread_id":"019dcaf6-01d5-7060-bc43-40401e3693c3"}"#)
    try check(threadEvent?.kind == .status, "thread events should become status updates")
    try check(threadEvent?.detail.contains("019dcaf6") == true, "thread status should include the session id")
    let reasoningEvent = try CodexJSONEventParser.parseLine(#"{"type":"agent_reasoning","text":"Reading paper context"}"#)
    try check(reasoningEvent?.kind == .thinking, "reasoning summaries should become thinking updates")
    try check(reasoningEvent?.detail == "Reading paper context", "reasoning event should preserve summary text")
    let commandEvent = try CodexJSONEventParser.parseLine(#"{"type":"exec_command","cmd":"rg -n diffusion paper.md"}"#)
    try check(commandEvent?.kind == .terminal, "terminal command events should be classified for terminal display")
    try check(commandEvent?.title == "rg -n diffusion paper.md", "terminal command events should use the command as the display title")
    try check(commandEvent?.detail == "Running command", "terminal command events should not duplicate the command in the detail text")
    try check(commandEvent?.displayTitle == "rg -n diffusion paper.md", "terminal display title should show the command")
    try check(commandEvent?.previewDetail == "Running command", "terminal preview should use a compact first line")
    let outputEvent = try CodexJSONEventParser.parseLine(#"{"type":"exec_command_output","stdout":"paper.md:12: diffusion\n"}"#)
    try check(outputEvent?.kind == .terminal, "terminal output events should be classified for terminal display")
    try check(outputEvent?.title == "Command output", "terminal output events should be displayed as command output")
    try check(outputEvent?.detail.contains("paper.md:12") == true, "terminal output events should include stdout text")
    let longOutputEvent = CodexRunEvent(kind: .terminal, title: "Command output", detail: String(repeating: "a", count: 180) + "\nsecond line")
    try check(longOutputEvent.previewDetail.count <= 96, "terminal preview should be truncated")
    try check(!longOutputEvent.previewDetail.contains("second line"), "terminal preview should only show the first line")
    let toolEvent = try CodexJSONEventParser.parseLine(#"{"type":"tool_call","name":"web.search","arguments":{"query":"paper"}}"#)
    try check(toolEvent?.kind == .tool, "non-terminal tool calls should be classified as tool events")
    try check(toolEvent?.title == "web.search", "tool events should show the tool name")

    let parsedVersion = CodexCLI.parseVersion(from: "codex-cli 0.114.0\n")
    try check(parsedVersion == "0.114.0", "Codex version parser should read codex-cli output")
    let executableCandidates = [
        CodexExecutableCandidate(path: "/opt/homebrew/bin/codex", version: "0.114.0"),
        CodexExecutableCandidate(path: "/Applications/Codex.app/Contents/Resources/codex", version: "0.125.0-alpha.3")
    ]
    let selectedExecutable = CodexCLI.selectBestExecutable(candidates: executableCandidates)
    try check(selectedExecutable?.path == "/Applications/Codex.app/Contents/Resources/codex", "newest Codex executable should be selected when multiple copies exist")
    let imageExecutable = CodexCLI.selectBestExecutable(candidates: executableCandidates, preferWorkspaceImageOutput: true)
    try check(imageExecutable?.path == "/opt/homebrew/bin/codex", "image-generation runs should prefer the CLI that writes generated images into the workspace")
    let firstUnknownExecutable = CodexCLI.selectBestExecutable(candidates: [
        CodexExecutableCandidate(path: "/first/codex", version: nil),
        CodexExecutableCandidate(path: "/second/codex", version: nil)
    ])
    try check(firstUnknownExecutable?.path == "/first/codex", "candidate order should be preserved when versions are unknown")
    let help = "Usage: codex exec [OPTIONS]\n      --json\n  -o, --output-last-message <FILE>\nCommands:\n  resume\n"
    let capabilities = CodexCLI.parseCapabilities(fromExecHelp: help)
    try check(capabilities.supportsJSONOutput, "Codex help parser should detect JSON output support")
    try check(capabilities.supportsOutputLastMessage, "Codex help parser should detect last-message output support")
    try check(capabilities.supportsResume, "Codex help parser should detect resume support")
    let cancelHandle = CodexRunHandle()
    let cancelSemaphore = DispatchSemaphore(value: 0)
    let cancelStarted = Date()
    DispatchQueue.global().async {
        do {
            _ = try CodexCLI(executablePath: "/bin/sleep")
                .runStreaming(arguments: ["5"], runHandle: cancelHandle) { _ in }
        } catch {
        }
        cancelSemaphore.signal()
    }
    Thread.sleep(forTimeInterval: 0.1)
    cancelHandle.cancel()
    let cancelResult = cancelSemaphore.wait(timeout: .now() + 2)
    try check(cancelResult == .success, "Codex run handle should terminate a running process")
    try check(Date().timeIntervalSince(cancelStarted) < 2, "Codex run cancellation should return promptly")
    let diagnostic = CodexDiagnostic.ready(
        executablePath: "/opt/homebrew/bin/codex",
        version: "0.114.0",
        capabilities: capabilities
    )
    try check(diagnostic.title == "Codex ready", "ready diagnostic should have a stable title")
    try check(diagnostic.detail.contains("0.114.0"), "ready diagnostic should include the CLI version")

    let config = """
    model = "gpt-5.5"

    [profiles.fast]
    model = "gpt-5.4"
    """
    try check(CodexCLI.parseConfiguredModel(from: config) == "gpt-5.5", "Codex config parser should read the top-level model")
    let modelIssue = CodexCLI.configuredModelIssue(configText: config, cliVersion: "0.114.0")
    try check(modelIssue?.contains("gpt-5.5") == true, "model compatibility issue should name the configured model")
    let blockedDiagnostic = CodexCLI.diagnostic(
        executablePath: "/opt/homebrew/bin/codex",
        version: "0.114.0",
        capabilities: capabilities,
        configText: config
    )
    try check(blockedDiagnostic.severity == .blocked, "diagnostic should be blocked when the configured model needs a newer CLI")
    try check(blockedDiagnostic.title == "Codex model incompatible", "model compatibility failures should have a specific diagnostic title")
    let overrideDiagnostic = CodexCLI.diagnostic(
        executablePath: "/opt/homebrew/bin/codex",
        version: "0.114.0",
        capabilities: capabilities,
        configText: config,
        modelOverride: "gpt-5.4"
    )
    try check(overrideDiagnostic.severity == .ready, "app-local model override should bypass the incompatible default model")
    try check(overrideDiagnostic.detail.contains("gpt-5.4"), "override diagnostic should name the selected model")
    try check(CodexCLI.configuredModelIssue(configText: #"model = "gpt-5.4""#, cliVersion: "0.114.0") == nil, "other configured models should not be blocked by the gpt-5.5 compatibility rule")

    let detectedModels = CodexCLI.availableModelIDs(
        cliVersion: "0.120.0",
        embeddedText: "gpt-5.4 gpt-5.3-codex gpt-5.1-codex-mini gpt-5-4 gpt-account-id gptAuthTokens gpt.com",
        configText: #"model = "gpt-5.2""#
    )
    try check(detectedModels.contains("gpt-5.4"), "Codex model detector should include embedded GPT models")
    try check(detectedModels.contains("gpt-5.1-codex-mini"), "Codex model detector should include embedded Codex model variants")
    try check(detectedModels.contains("gpt-5.2"), "Codex model detector should include the configured model")
    try check(!detectedModels.contains("gpt-account-id"), "Codex model detector should filter telemetry strings")
    try check(!detectedModels.contains("gptAuthTokens"), "Codex model detector should filter auth implementation strings")
    try check(!detectedModels.contains("gpt-5-4"), "Codex model detector should filter hyphenated version noise")
    let oldVersionModels = CodexCLI.availableModelIDs(
        cliVersion: "0.114.0",
        embeddedText: "gpt-5.5 gpt-5.4",
        configText: nil
    )
    try check(!oldVersionModels.contains("gpt-5.5"), "Codex model detector should filter models blocked by the current CLI version")
}

func runGeneratedImageChecks() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-generated-images-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let oldImage = root.appendingPathComponent("ig_old.png")
    let newImage = root.appendingPathComponent("ig_new.png")
    let nestedDir = root.appendingPathComponent("nested", isDirectory: true)
    try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
    let nestedImage = nestedDir.appendingPathComponent("ig_nested.jpeg")
    let note = root.appendingPathComponent("note.txt")

    try Data([0x89, 0x50, 0x4e, 0x47]).write(to: oldImage)
    let before = try GeneratedImageCollector.snapshot(in: root)
    try Data([0x89, 0x50, 0x4e, 0x47]).write(to: newImage)
    try Data([0xff, 0xd8, 0xff, 0xd9]).write(to: nestedImage)
    try "not an image".write(to: note, atomically: true, encoding: .utf8)

    let generated = try GeneratedImageCollector.newImages(in: root, excluding: before)
    try check(generated.map(\.lastPathComponent).sorted() == ["ig_nested.jpeg", "ig_new.png"], "generated image collector should return only new images")
    let markdown = GeneratedImageCollector.markdown(for: generated)
    try check(markdown.contains("![Generated image](\(newImage.path))"), "generated image markdown should include absolute image paths")
    try check(!markdown.contains(oldImage.path), "generated image markdown should not include previous images")
}

func runImageRequestChecks() throws {
    try check(ImageGenerationRequestDetector.isImageRequest("生成一张图，展示实验流程"), "Chinese image-generation wording should request image generation")
    try check(ImageGenerationRequestDetector.isImageRequest("make an infographic about this paper"), "English infographic wording should request image generation")
    try check(!ImageGenerationRequestDetector.isImageRequest("解释一下图 2 的结果"), "discussing an existing figure should not force image generation")
    try check(!ImageGenerationRequestDetector.isImageRequest("这个论文讲了什么"), "ordinary paper QA should not request image generation")
}

func runCodexRecoveryChecks() throws {
    let notice = CodexFailureNotice(detail: "Codex process failed with status 1: session not found")
    try check(notice.messageContent.hasPrefix("Codex failed:"), "failure notice should use a stable prefix")
    try check(notice.messageContent.contains("session not found"), "failure notice should preserve Codex stderr detail")
    try check(CodexFailureNotice.parse(notice.messageContent) == notice, "failure notice should parse from stored chat content")
    try check(CodexFailureNotice.parse("A normal answer") == nil, "normal answers should not be treated as recovery notices")
}

func runPathChecks() throws {
    let overrideRoot = PaperCodexPaths.supportRoot(environment: [
        "PAPER_CODEX_SUPPORT_ROOT": "/tmp/paper-codex-isolated-root"
    ])
    try check(overrideRoot.path == "/tmp/paper-codex-isolated-root", "support root should honor explicit environment override")

    let defaultRoot = PaperCodexPaths.supportRoot(environment: [:])
    try check(defaultRoot.lastPathComponent == "PaperCodex", "default support root should end in PaperCodex")
    try check(defaultRoot.path.contains("Application Support"), "default support root should live under Application Support")
}

func runBundleChecks() throws {
    let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("scripts/build-app-bundle.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)
    let oldHost = ["nas", "pucao", "cn"].joined(separator: ".")
    let insecureHTTPKey = "NSExceptionAllows" + "InsecureHTTPLoads"
    try check(!script.contains(oldHost), "app bundle should not keep the old remote feed host")
    try check(!script.contains(insecureHTTPKey), "app bundle should not allow insecure HTTP for old feed hosts")
}

func runFixtureLibraryChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-fixture-\(UUID().uuidString)", isDirectory: true)
    try seedFixtureLibrary(at: tempRoot)

    let repository = try PaperRepository(databasePath: tempRoot.appendingPathComponent("store.sqlite").path)
    let papers = try repository.fetchPapers()
    let categories = try repository.fetchCategories()
    let tags = try repository.fetchTags()
    let sessions = try repository.fetchSessions(paperID: "fixture-paper-a")
    let spans = try repository.fetchSpans(paperID: "fixture-paper-a")

    try check(papers.count == 2, "fixture library should contain two real PDF papers")
    try check(categories.count >= 2, "fixture library should contain nested categories")
    try check(tags.count >= 2, "fixture library should contain tags")
    try check(sessions.first?.paperIDs == ["fixture-paper-a", "fixture-paper-b"], "fixture session should include both papers in order")
    try check(!spans.isEmpty, "fixture library should persist extracted text spans")
}

func runWatchedFolderChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-watch-\(UUID().uuidString)", isDirectory: true)
    let supportRoot = tempRoot.appendingPathComponent("support", isDirectory: true)
    let inbox = tempRoot.appendingPathComponent("inbox", isDirectory: true)
    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    let databaseURL = supportRoot.appendingPathComponent("store.sqlite")
    try FileManager.default.createDirectory(at: supportRoot, withIntermediateDirectories: true)

    try writeFixturePDF(to: inbox.appendingPathComponent("paper-a.pdf"), lines: [
        "Watched folders import real PDF files.",
        "The scanner should persist page text and spans."
    ])
    try writeFixturePDF(to: inbox.appendingPathComponent("paper-b.pdf"), lines: [
        "A second PDF exercises deterministic folder scans.",
        "Duplicate scans should not create duplicate papers."
    ])
    try "ignore me".write(to: inbox.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

    let repository = try PaperRepository(databasePath: databaseURL.path)
    try repository.migrate()
    let now = Date(timeIntervalSince1970: 1_777_220_000)
    let folder = WatchedFolder(id: "watch-inbox", path: inbox.path, createdAt: now, lastScannedAt: nil)
    try repository.upsertWatchedFolder(folder)
    let storedFolders = try repository.fetchWatchedFolders()
    try check(storedFolders == [folder], "watched folder should persist")

    let scanner = WatchedFolderScanner(repository: repository, supportRoot: supportRoot)
    let firstScanResults = try scanner.scanAllWatchedFolders(now: now.addingTimeInterval(5))
    try check(firstScanResults.count == 1, "scan-all should scan one watched folder")
    let firstScan = firstScanResults[0]
    try check(firstScan.importedPapers.count == 2, "first watched folder scan should import two PDFs")
    try check(firstScan.existingPapers.isEmpty, "first watched folder scan should not report existing papers")
    let firstPapers = try repository.fetchPapers()
    try check(firstPapers.count == 2, "watched folder scan should persist imported papers")
    let storedFolder = try repository.fetchWatchedFolders().first
    try check(storedFolder?.lastScannedAt == now.addingTimeInterval(5), "watched folder scan should update last scanned time")

    try writeFixturePDF(to: inbox.appendingPathComponent("paper-c.pdf"), lines: [
        "A third PDF appears after the folder is already being watched.",
        "The next scan should import only this new paper."
    ])
    let changeScan = try scanner.scanAllWatchedFolders(now: now.addingTimeInterval(10))[0]
    try check(changeScan.importedPapers.count == 1, "changed watched folder scan should import the new PDF")
    try check(changeScan.existingPapers.count == 2, "changed watched folder scan should report prior papers as existing")
    let changedPapers = try repository.fetchPapers()
    try check(changedPapers.count == 3, "changed watched folder scan should persist the new paper")

    let secondScan = try scanner.scanAllWatchedFolders(now: now.addingTimeInterval(15))[0]
    try check(secondScan.importedPapers.isEmpty, "second watched folder scan should not re-import duplicates")
    try check(secondScan.existingPapers.count == 3, "second watched folder scan should report all existing papers")
    let secondPapers = try repository.fetchPapers()
    try check(secondPapers.count == 3, "duplicate watched folder scan should keep paper count stable")

    try repository.deleteWatchedFolder(id: folder.id)
    let removedFolders = try repository.fetchWatchedFolders()
    try check(removedFolders.isEmpty, "watched folder should be removable")
}

func runArxivFeedChecks() throws {
    let sample = """
    {
      "date": "2026-04-22",
      "count": 1,
      "groups": [
        {"key": "white", "count": 1},
        {"key": "neutral", "count": 0},
        {"key": "black", "count": 0}
      ],
      "tag_options": ["Diffusion", "Med", "Toolkit"],
      "papers": [
        {
          "id": "2604.18586",
          "arxiv_id": "2604.18586",
          "arxiv_id_versioned": "2604.18586v1",
          "title": {"en": "Who Shapes Brazil's Vaccine Debate?", "zh": "谁塑造了巴西的疫苗辩论？"},
          "abstract": {"en": "A longitudinal vaccine discourse study.", "zh": "一项疫苗话语纵向研究。"},
          "summary": {"en": "Semi-supervised stance detection over YouTube comments.", "zh": "对 YouTube 评论进行半监督立场检测。"},
          "authors": ["Geovana S. de Oliveira", "Ana P. C. Silva"],
          "categories": ["cs.CY", "cs.AI"],
          "primary_category": "cs.CY",
          "list_categories": ["cs.AI", "cs.CL"],
          "tags": ["text-cls", "SSL"],
          "comment": "Paper accepted at WebSci'26",
          "published": "2026-03-04T19:21:01Z",
          "updated": "2026-03-04T19:21:01Z",
          "list_date": "2026-04-22",
          "thumbnail_version": 3,
          "embedding": [0.1, 0.2, 0.3],
          "similarity": 0.91,
          "filter_group": "white",
          "is_favorite": true,
          "links": {
            "abs": "https://arxiv.org/abs/2604.18586",
            "pdf": "https://arxiv.org/pdf/2604.18586.pdf",
            "github": "https://github.com/example/paper-code",
            "code": "https://github.com/example/paper-code",
            "project": "https://example.org/paper",
            "hugging_face": "https://huggingface.co/example/paper"
          },
          "assets": {
            "small": {"path": "images/2026-04-22/2604.18586_small.png", "url": "/api/v1/assets/2026-04-22/2604.18586_small.png"},
            "large": {"path": "images/2026-04-22/2604.18586.png", "url": "/api/v1/assets/2026-04-22/2604.18586.png"}
          }
        }
      ]
    }
    """
    let decoder = JSONDecoder()
    let response = try decoder.decode(ArxivFeedResponse.self, from: Data(sample.utf8))
    try check(response.date == "2026-04-22", "arXiv feed response should decode the date")
    try check(response.papers.count == 1, "arXiv feed response should decode papers")
    try check(response.groups?.map(\.key) == ["white", "neutral", "black"], "local arXiv feed should decode group summaries")
    try check(response.tagOptions == ["Diffusion", "Med", "Toolkit"], "local arXiv feed should decode tag options")
    let paper = response.papers[0]
    try check(paper.id == "2604.18586", "arXiv paper should decode stable arxiv id")
    try check(paper.displayTitle(language: "zh") == "谁塑造了巴西的疫苗辩论？", "arXiv paper should prefer Chinese title in zh mode")
    try check(paper.displaySummary(language: "en") == "Semi-supervised stance detection over YouTube comments.", "arXiv paper should prefer English summary in en mode")
    try check(paper.assets.small?.path == "images/2026-04-22/2604.18586_small.png", "arXiv paper should decode small asset path")
    try check(paper.links.github == "https://github.com/example/paper-code", "arXiv paper should decode GitHub link")
    try check(paper.links.project == "https://example.org/paper", "arXiv paper should decode project link")
    try check(paper.links.huggingFace == "https://huggingface.co/example/paper", "arXiv paper should decode Hugging Face link")
    try check(paper.similarity == 0.91, "arXiv paper should decode similarity score")
    try check(paper.filterGroup == "white", "arXiv paper should decode local filter group")

    let quickPrompt = QuickPrompt(
        id: "qp-summary",
        title: "Summarize",
        content: "Summarize the main contribution."
    )
    let quickPromptEncoder = JSONEncoder()
    let decodedQuickPrompt = try decoder.decode(QuickPrompt.self, from: quickPromptEncoder.encode(quickPrompt))
    try check(decodedQuickPrompt == quickPrompt, "quick prompt should JSON round-trip")

    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-arxiv-cache-\(UUID().uuidString)", isDirectory: true)
    let cache = ArxivFeedCache(root: tempRoot)
    try cache.saveFeed(response)
    let cached = try cache.loadFeed(date: "2026-04-22")
    try check(cached == response, "arXiv feed cache should round-trip feed JSON")
    let assetURL = try cache.saveAsset(Data("small".utf8), path: "images/2026-04-22/2604.18586_small.png")
    try check(FileManager.default.fileExists(atPath: assetURL.path), "arXiv feed cache should store asset bytes")
    try check(
        response.uniqueAssets(includeLarge: false).map(\.path) == ["images/2026-04-22/2604.18586_small.png"],
        "arXiv feed should expose unique small assets for preload progress"
    )
    try check(
        response.uniqueAssets(includeLarge: true).map(\.path) == [
            "images/2026-04-22/2604.18586_small.png",
            "images/2026-04-22/2604.18586.png"
        ],
        "arXiv feed should expose unique small and large assets for preload progress"
    )
    let smallAssetSummary = try cache.assetCacheSummary(for: response, includeLarge: false)
    let fullAssetSummary = try cache.assetCacheSummary(for: response, includeLarge: true)
    try check(smallAssetSummary == ArxivFeedAssetCacheSummary(cached: 1, total: 1), "arXiv cache should count cached small assets")
    try check(fullAssetSummary == ArxivFeedAssetCacheSummary(cached: 1, total: 2), "arXiv cache should count cached full image assets")
    let emptyPDFSummary = try cache.pdfCacheSummary(for: response)
    try check(emptyPDFSummary == ArxivFeedAssetCacheSummary(cached: 0, total: 1), "arXiv cache should count missing PDFs")
    let savedPDFURL = try cache.savePDF(Data("%PDF-1.4\n".utf8), arxivID: paper.id, date: paper.listDate ?? response.date)
    try check(FileManager.default.fileExists(atPath: savedPDFURL.path), "arXiv cache should store cached PDF bytes")
    let exactCachedPDFURL = try cache.cachedPDFURL(arxivID: paper.id, date: paper.listDate ?? response.date)
    let discoveredCachedPDFURL = try cache.cachedPDFURL(arxivID: paper.id)
    try check(exactCachedPDFURL == savedPDFURL, "arXiv cache should find a PDF by exact feed date")
    try check(
        discoveredCachedPDFURL?.resolvingSymlinksInPath().path == savedPDFURL.resolvingSymlinksInPath().path,
        "arXiv cache should find a PDF across cached dates"
    )
    let pdfSummary = try cache.pdfCacheSummary(for: response)
    try check(pdfSummary == ArxivFeedAssetCacheSummary(cached: 1, total: 1), "arXiv cache should count cached PDFs")

    let metadata = PaperImportMetadata(
        title: paper.displayTitle(language: "en"),
        authors: paper.authors,
        year: paper.publishedYear,
        sourceURL: paper.links.abs
    )
    try check(metadata.year == 2026, "paper import metadata should derive published year")

    let importRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-arxiv-import-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: importRoot, withIntermediateDirectories: true)
    let importPDFURL = importRoot.appendingPathComponent("2604.18586.pdf")
    try writeFixturePDF(
        to: importPDFURL,
        lines: [
            "A real PDF import should keep arXiv feed metadata.",
            "The downloaded paper then becomes readable in Paper Codex."
        ]
    )
    let repository = try PaperRepository(databasePath: importRoot.appendingPathComponent("store.sqlite").path)
    try repository.migrate()
    let imported = try PaperLibraryImporter(repository: repository, supportRoot: importRoot)
        .importPDF(from: importPDFURL, metadata: metadata)
    try check(imported.didImport, "arXiv PDF import should create a new library paper")
    try check(imported.paper.title == "Who Shapes Brazil's Vaccine Debate?", "arXiv import should preserve feed title")
    try check(imported.paper.authors == paper.authors, "arXiv import should preserve feed authors")
    try check(imported.paper.year == 2026, "arXiv import should preserve feed year")
    try check(imported.paper.sourceURL == "https://arxiv.org/abs/2604.18586", "arXiv import should preserve source URL")

    let duplicateRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-arxiv-duplicate-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: duplicateRoot, withIntermediateDirectories: true)
    let duplicatePDFURL = duplicateRoot.appendingPathComponent("2604.18586.pdf")
    try FileManager.default.copyItem(at: importPDFURL, to: duplicatePDFURL)
    let duplicateRepository = try PaperRepository(databasePath: duplicateRoot.appendingPathComponent("store.sqlite").path)
    try duplicateRepository.migrate()
    let duplicateImporter = PaperLibraryImporter(repository: duplicateRepository, supportRoot: duplicateRoot)
    let manualImport = try duplicateImporter.importPDF(from: duplicatePDFURL)
    try check(manualImport.paper.sourceURL == nil, "manual import fixture should start without source URL")
    let enrichedDuplicate = try duplicateImporter.importPDF(from: duplicatePDFURL, metadata: metadata)
    try check(!enrichedDuplicate.didImport, "duplicate arXiv import should reuse the existing PDF")
    try check(enrichedDuplicate.paper.title == "Who Shapes Brazil's Vaccine Debate?", "duplicate arXiv import should enrich title")
    try check(enrichedDuplicate.paper.authors == paper.authors, "duplicate arXiv import should enrich authors")
    try check(enrichedDuplicate.paper.year == 2026, "duplicate arXiv import should enrich year")
    try check(enrichedDuplicate.paper.sourceURL == "https://arxiv.org/abs/2604.18586", "duplicate arXiv import should enrich source URL")

    let cacheRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-arxiv-cache-import-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    let cachePDFURL = cacheRoot.appendingPathComponent("2604.18586.pdf")
    try FileManager.default.copyItem(at: importPDFURL, to: cachePDFURL)
    let cacheRepository = try PaperRepository(databasePath: cacheRoot.appendingPathComponent("store.sqlite").path)
    try cacheRepository.migrate()
    let cacheImporter = PaperLibraryImporter(repository: cacheRepository, supportRoot: cacheRoot)
    let cachedImport = try cacheImporter.importPDF(from: cachePDFURL, metadata: metadata, isSaved: false)
    try check(!cachedImport.paper.isSaved, "opening an arXiv paper should create an unsaved cached paper")
    try check(cachedImport.paper.filePath.contains("/cache/papers/"), "unsaved arXiv paper should live under disposable cache")
    let savedPapersAfterCacheOpen = try cacheRepository.fetchPapers()
    let cachedPapersByID = try cacheRepository.fetchPapers(ids: [cachedImport.paper.id])
    try check(savedPapersAfterCacheOpen.isEmpty, "unsaved cached paper should not appear in the library list")
    try check(cachedPapersByID.first?.id == cachedImport.paper.id, "cached paper should remain addressable for reader sessions")
    try check(cachedPapersByID.first?.isSaved == false, "cached paper fetched by ID should remain unsaved")
    let oldCachedPath = cachedImport.paper.filePath
    let promotedImport = try cacheImporter.importPDF(
        from: cachePDFURL,
        metadata: metadata,
        isSaved: true,
        storageSubpath: "cs.AI"
    )
    try check(!promotedImport.didImport, "saving a cached arXiv paper should reuse the cached import")
    try check(promotedImport.paper.isSaved, "saving a cached arXiv paper should promote it into the library")
    try check(promotedImport.paper.filePath.contains("/papers/cs-ai/"), "saved arXiv paper should follow the configured organization path")
    try check(FileManager.default.fileExists(atPath: promotedImport.paper.filePath), "promoted arXiv PDF should exist at the library path")
    try check(!FileManager.default.fileExists(atPath: oldCachedPath), "promoted arXiv PDF should be moved out of disposable cache")
}

func runLocalDiscoverEngineChecks() throws {
    let range = try DiscoverDateRange(start: "2026-04-27", end: "2026-04-29")
    try check(range.dates == ["2026-04-27", "2026-04-28", "2026-04-29"], "discover date range should expand inclusive dates")
    let last7Days = try DiscoverQuickRange.last7Days.dateRange(endingAt: "2026-04-29")
    try check(last7Days.start == "2026-04-23", "last 7 days should include the ending date")
    try check(last7Days.end == "2026-04-29", "quick range should preserve the ending date")

    let queryA = DiscoverQuery(
        keyword: "diffusion policy",
        dateRange: range,
        categories: ["cs.CV", "cs.AI"],
        similaritySourceIDs: ["tag-robot", "cat-vision"],
        rankingVersion: "rank-v1"
    )
    let queryB = DiscoverQuery(
        keyword: "  diffusion   policy ",
        dateRange: range,
        categories: ["cs.AI", "cs.CV", "cs.AI"],
        similaritySourceIDs: ["cat-vision", "tag-robot", "tag-robot"],
        rankingVersion: "rank-v1"
    )
    try check(queryA.normalized == queryB.normalized, "discover query normalization should ignore whitespace and duplicate order")
    try check(queryA.cacheKey == queryB.cacheKey, "discover query cache key should be stable for equivalent queries")

    let enrichment = DiscoverPaperEnrichment(
        arxivID: "2604.18803",
        processorVersion: DiscoverPaperEnrichment.currentProcessorVersion,
        promptVersion: DiscoverPaperEnrichment.currentPromptVersion,
        modelIdentity: "codex",
        titleZH: "本地论文阅读器",
        summaryZH: "提出一个本地优先的论文发现和阅读流程。",
        contribution: "把 arXiv 检索、缓存和阅读工作流连接起来。",
        tags: ["paper-reader", "local-first"],
        links: ["github": "https://github.com/example/paper-reader"],
        generatedAt: Date(timeIntervalSince1970: 1_777_300_000),
        error: nil
    )
    try check(enrichment.isCurrent, "fresh enrichment should be current")

    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-discover-engine-\(UUID().uuidString)", isDirectory: true)
    let cache = LocalDiscoverCache(root: tempRoot)
    try cache.saveQueryResult(
        DiscoverQueryResult(query: queryA.normalized, arxivIDs: ["2604.18803"], generatedAt: enrichment.generatedAt)
    )
    try cache.saveEnrichment(enrichment)
    let cachedQuery = try cache.loadQueryResult(cacheKey: queryA.cacheKey)
    let cachedEnrichment = try cache.loadEnrichment(arxivID: "2604.18803")
    try check(cachedQuery?.arxivIDs == ["2604.18803"], "discover query cache should round-trip ordered ids")
    try check(cachedEnrichment?.titleZH == "本地论文阅读器", "discover enrichment cache should round-trip processed metadata")

    let embeddingText = "Recursive multi-agent systems coordinate latent-state reasoning."
    let embeddingRecord = DiscoverEmbeddingRecord(
        sourceID: "arxiv:2604.18803",
        model: "text-embedding-v4",
        textHash: DiscoverEmbeddingText.hash(embeddingText),
        vector: [0.1, 0.2, 0.3],
        generatedAt: enrichment.generatedAt
    )
    try cache.saveEmbedding(embeddingRecord)
    let cachedEmbedding = try cache.loadEmbedding(
        sourceID: "arxiv:2604.18803",
        model: "text-embedding-v4",
        text: embeddingText
    )
    let staleEmbedding = try cache.loadEmbedding(
        sourceID: "arxiv:2604.18803",
        model: "text-embedding-v4",
        text: "\(embeddingText) changed"
    )
    try check(cachedEmbedding?.vector == [0.1, 0.2, 0.3], "discover embedding cache should round-trip vectors keyed by text hash")
    try check(staleEmbedding == nil, "discover embedding cache should ignore stale text hashes")

    let embeddingEndpointA = try OpenAICompatibleEmbeddingClient.endpointURL(for: "https://api.openai.com")
    let embeddingEndpointB = try OpenAICompatibleEmbeddingClient.endpointURL(for: "https://dashscope.aliyuncs.com/compatible-mode/v1")
    let embeddingEndpointC = try OpenAICompatibleEmbeddingClient.endpointURL(for: "https://example.com/custom/embeddings")
    try check(embeddingEndpointA.absoluteString == "https://api.openai.com/v1/embeddings", "embedding endpoint should append /v1/embeddings to provider roots")
    try check(embeddingEndpointB.absoluteString == "https://dashscope.aliyuncs.com/compatible-mode/v1/embeddings", "embedding endpoint should append /embeddings to /v1 base URLs")
    try check(embeddingEndpointC.absoluteString == "https://example.com/custom/embeddings", "embedding endpoint should preserve explicit embeddings URLs")

    let codexJSON = """
    {
      "title_zh": "本地优先的发现引擎",
      "summary_zh": "这个工作把 arXiv 检索、本地缓存和快速浏览结合起来。",
      "contribution": "提出一个本地优先的新论文发现流程。",
      "tags": ["local-first", "arxiv", "local-first"],
      "links": {"github": "https://github.com/example/discover"}
    }
    """
    let parsed = try DiscoverEnrichmentParser.parse(
        codexJSON,
        arxivID: "2604.18804",
        modelIdentity: "codex-test",
        generatedAt: Date(timeIntervalSince1970: 1_777_300_010)
    )
    try check(parsed.titleZH == "本地优先的发现引擎", "discover parser should read Chinese title")
    try check(parsed.tags == ["local-first", "arxiv"], "discover parser should dedupe tags while preserving order")
    try check(parsed.links["github"] == "https://github.com/example/discover", "discover parser should preserve extracted links")
}

func runLocalArxivClientChecks() throws {
    let extractedIDs = ArxivIDExtractor.extractVersionedIDs(
        from: """
        read arXiv:2604.18803v2 and https://arxiv.org/abs/2501.01234.
        Also fetch random text 2604.18803 and old id hep-th/9901001v3 plus https://arxiv.org/pdf/2408.99999.pdf
        """
    )
    try check(
        extractedIDs == ["2604.18803v2", "2501.01234", "hep-th/9901001v3", "2408.99999"],
        "arXiv ID extractor should parse multiple canonical and versioned ids from arbitrary text"
    )
    try check(
        ArxivIDExtractor.extractCanonicalIDs(from: extractedIDs.joined(separator: " ")) == ["2604.18803", "2501.01234", "hep-th/9901001", "2408.99999"],
        "arXiv ID extractor should expose canonical ids without version suffixes"
    )

    let apiRange = try DiscoverDateRange(start: "2026-04-27", end: "2026-04-29")
    let apiQuery = try LocalArxivClient.submittedDateSearchQuery(range: apiRange, categories: ["cs.AI", "cs.CL"])
    let apiURL = try LocalArxivClient.apiSearchURL(query: apiQuery, start: 2_000, maxResults: 1_000)
    let defaultConfiguration = LocalArxivClientConfiguration(categories: ["cs.AI"])
    let defaultAPIURL = try LocalArxivClient.apiSearchURL(
        query: apiQuery,
        start: 0,
        maxResults: defaultConfiguration.apiPageSize
    )
    try check(apiQuery == "(cat:cs.AI OR cat:cs.CL) AND submittedDate:[202604270000 TO 202604292359]", "local arXiv client should build submittedDate category range queries")
    try check(apiURL.absoluteString.contains("sortBy=submittedDate"), "local arXiv API URL should sort by submitted date")
    try check(apiURL.absoluteString.contains("sortOrder=descending"), "local arXiv API URL should sort newest papers first")
    try check(apiURL.absoluteString.contains("start=2000"), "local arXiv API URL should support paging start")
    try check(apiURL.absoluteString.contains("max_results=1000"), "local arXiv API URL should support paging size")
    try check(defaultConfiguration.apiPageSize == 100, "local arXiv client should default to small API pages to avoid export API timeouts")
    try check(defaultAPIURL.absoluteString.contains("max_results=100"), "local arXiv default API URL should avoid 1000-result search requests")

    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let clientSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexCore/LocalArxivClient.swift"))
    try check(clientSource.contains("isRetriableNetworkError"), "local arXiv client should retry transient network failures")
    try check(clientSource.contains("http.statusCode == 429"), "local arXiv client should handle export API rate limiting")
    try check(clientSource.contains("arXivAPIRequestDelayNanoseconds"), "local arXiv metadata batches should be throttled")

    let multiDateHTML = """
    <html><body>
    <h3>Wed, 29 Apr 2026 (showing first 2 of 2 entries)</h3>
    <dl>
      <dt><a href="/abs/2604.20002">arXiv:2604.20002</a></dt>
      <dt><a href="/abs/2604.20001v2">arXiv:2604.20001v2</a></dt>
    </dl>
    <h3>Tue, 28 Apr 2026 (showing first 1 of 1 entries)</h3>
    <dl>
      <dt><a href="/abs/2604.19999">arXiv:2604.19999</a></dt>
    </dl>
    </body></html>
    """
    let listPages = try LocalArxivClient.parseListPages(multiDateHTML)
    try check(listPages.map(\.date) == ["2026-04-29", "2026-04-28"], "local arXiv parser should parse every date section")
    try check(listPages[0].ids == ["2604.20002", "2604.20001"], "local arXiv parser should dedupe versioned ids per section")
    try check(listPages[1].ids == ["2604.19999"], "local arXiv parser should parse ids in later sections")

    let listHTML = """
    <html><body>
    <h3>Wed, 29 Apr 2026 (showing first 3 of 3 entries)</h3>
    <dl>
      <dt><a name="item1">[1]</a><a href="/abs/2604.18803">arXiv:2604.18803</a></dt>
      <dt><a name="item2">[2]</a><a href="/abs/2604.18804v2">arXiv:2604.18804v2</a></dt>
      <dt><a name="item3">[3]</a><a href="/abs/2604.18803v2">arXiv:2604.18803v2</a></dt>
    </dl>
    <h3>Tue, 28 Apr 2026 (showing first 1 of 1 entries)</h3>
    </body></html>
    """
    let parsedList = try LocalArxivClient.parseListPage(listHTML)
    try check(parsedList.date == "2026-04-29", "local arXiv list parser should parse newest date heading")
    try check(parsedList.ids == ["2604.18803", "2604.18804"], "local arXiv list parser should dedupe versioned IDs")

    let atomXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:arxiv="http://arxiv.org/schemas/atom">
      <entry>
        <id>http://arxiv.org/abs/2604.18803v1</id>
        <updated>2026-04-29T12:00:00Z</updated>
        <published>2026-04-29T08:00:00Z</published>
        <title>  A Local Paper Reader  </title>
        <summary>  We present a local-first paper reader.  </summary>
        <author><name>Alice Example</name></author>
        <author><name>Bob Example</name></author>
        <arxiv:comment>Code: https://github.com/example/paper-reader</arxiv:comment>
        <arxiv:primary_category term="cs.CL" />
        <category term="cs.CL" />
        <category term="cs.AI" />
      </entry>
    </feed>
    """
    let parsedPapers = try LocalArxivClient.parseAtomFeed(
        atomXML,
        listDate: "2026-04-29",
        listCategoriesByID: ["2604.18803": ["cs.CL"]]
    )
    try check(parsedPapers.count == 1, "local arXiv Atom parser should parse one entry")
    let paper = parsedPapers[0]
    try check(paper.id == "2604.18803", "local arXiv Atom parser should normalize arXiv ID")
    try check(paper.arxivIDVersioned == "2604.18803v1", "local arXiv Atom parser should keep versioned ID")
    try check(paper.title.en == "A Local Paper Reader", "local arXiv Atom parser should normalize title whitespace")
    try check(paper.abstract.en == "We present a local-first paper reader.", "local arXiv Atom parser should normalize abstract whitespace")
    try check(paper.links.abs == "https://arxiv.org/abs/2604.18803", "local arXiv mapper should provide canonical abs link")
    try check(paper.links.pdf == "https://arxiv.org/pdf/2604.18803.pdf", "local arXiv mapper should provide canonical PDF link")
    try check(paper.links.github == "https://github.com/example/paper-reader", "local arXiv mapper should extract GitHub links from comments")
    try check(paper.listCategories == ["cs.CL"], "local arXiv mapper should preserve list categories")
}

func runLocalDiscoverPreferenceChecks() throws {
    let preferences = LocalDiscoverPreferences(
        categories: ["cs.CV", "cs.CL", "cs.CV"],
        whitelistTags: ["agent", "code", "agent"],
        blacklistTags: ["survey"],
        similaritySourceTagIDs: ["tag-agent", "tag-agent"],
        enrichment: LocalEnrichmentPreferences(autoEnrichOnOpen: true, autoEnrichOnSave: true),
        embedding: EmbeddingProviderSettings(enabled: true, baseURL: "https://dashscope.aliyuncs.com", model: "text-embedding-v4")
    )
    let normalized = preferences.normalized
    try check(normalized.categories == ["cs.CV", "cs.CL"], "local discover preferences should dedupe categories")
    try check(normalized.whitelistTags == ["agent", "code"], "local discover preferences should dedupe whitelist tags")
    try check(normalized.similaritySourceTagIDs == ["tag-agent"], "local discover preferences should dedupe similarity sources")
    try check(normalized.embedding.model == "text-embedding-v4", "embedding settings should preserve model")

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(LocalDiscoverPreferences.self, from: encoder.encode(normalized))
    try check(decoded == normalized, "local discover preferences should JSON round-trip")
}

func runSimilarityRankerChecks() throws {
    let papers = [
        ArxivFeedPaper(
            id: "a",
            arxivID: "a",
            arxivIDVersioned: nil,
            title: ArxivLocalizedText(en: "A", zh: ""),
            abstract: ArxivLocalizedText(en: "A", zh: ""),
            summary: ArxivLocalizedText(en: "", zh: ""),
            authors: [],
            categories: ["cs.CL"],
            primaryCategory: "cs.CL",
            listCategories: ["cs.CL"],
            tags: ["agent"],
            comment: "",
            published: "2026-04-29T00:00:00Z",
            updated: nil,
            listDate: "2026-04-29",
            thumbnailVersion: nil,
            embedding: [1, 0],
            links: ArxivFeedLinks(abs: nil, pdf: nil),
            assets: ArxivFeedAssets(small: nil, large: nil)
        ),
        ArxivFeedPaper(
            id: "b",
            arxivID: "b",
            arxivIDVersioned: nil,
            title: ArxivLocalizedText(en: "B", zh: ""),
            abstract: ArxivLocalizedText(en: "B", zh: ""),
            summary: ArxivLocalizedText(en: "", zh: ""),
            authors: [],
            categories: ["cs.CL"],
            primaryCategory: "cs.CL",
            listCategories: ["cs.CL"],
            tags: ["survey"],
            comment: "",
            published: "2026-04-29T00:00:00Z",
            updated: nil,
            listDate: "2026-04-29",
            thumbnailVersion: nil,
            embedding: [0, 1],
            links: ArxivFeedLinks(abs: nil, pdf: nil),
            assets: ArxivFeedAssets(small: nil, large: nil)
        ),
        ArxivFeedPaper(
            id: "c",
            arxivID: "c",
            arxivIDVersioned: nil,
            title: ArxivLocalizedText(en: "C", zh: ""),
            abstract: ArxivLocalizedText(en: "C", zh: ""),
            summary: ArxivLocalizedText(en: "", zh: ""),
            authors: [],
            categories: ["cs.CL"],
            primaryCategory: "cs.CL",
            listCategories: ["cs.CL"],
            tags: [],
            comment: "",
            published: "2026-04-29T00:00:00Z",
            updated: nil,
            listDate: "2026-04-29",
            thumbnailVersion: nil,
            embedding: [0.9, 0.1],
            links: ArxivFeedLinks(abs: nil, pdf: nil),
            assets: ArxivFeedAssets(small: nil, large: nil)
        )
    ]
    let ranked = SimilarityRanker.rank(
        papers: papers,
        whitelistTags: ["agent"],
        blacklistTags: ["survey"],
        interestVectors: [[1, 0]]
    )
    try check(ranked.map(\.id) == ["a", "c", "b"], "similarity ranker should order white, neutral, black groups")
    try check(ranked[0].filterGroup == "white", "similarity ranker should mark whitelist group")
    try check(ranked[2].filterGroup == "black", "similarity ranker should mark blacklist group")
    try check((ranked[0].similarity ?? 0) > (ranked[1].similarity ?? 0), "similarity ranker should attach cosine scores")
    try check(SimilarityRanker.meanVector([[1, 0], [0, 1]]) == [0.5, 0.5], "similarity ranker should compute collection mean vectors")
    try check(SimilarityRanker.cosine([1, 0], [0, 1]) == 0, "similarity ranker should return zero for orthogonal vectors")
}

func seedFixtureLibrary(at root: URL) throws {
    let fileManager = FileManager.default
    let storeURL = root.appendingPathComponent("store.sqlite")
    if fileManager.fileExists(atPath: storeURL.path) {
        throw CheckFailure(description: "refusing to overwrite existing fixture store at \(storeURL.path)")
    }

    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try PaperRepository(databasePath: storeURL.path)
    try repository.migrate()

    let now = Date(timeIntervalSince1970: 1_777_220_000)
    let paperA = try seedFixturePaper(
        id: "fixture-paper-a",
        title: "Representation Autoencoders for Controllable Diffusion",
        authors: ["Alice Chen", "Bo Liu"],
        year: 2026,
        lines: [
            "Representation autoencoders preserve semantic coordinates.",
            "The decoder controls latent trajectories during diffusion.",
            "This selected mechanism is useful for source-grounded answers."
        ],
        root: root,
        repository: repository,
        importedAt: now
    )
    let paperB = try seedFixturePaper(
        id: "fixture-paper-b",
        title: "Latent Control Benchmarks for Generative Models",
        authors: ["Carla Park"],
        year: 2025,
        lines: [
            "Latent control benchmarks compare paired edit trajectories.",
            "Evaluation should inspect source-aligned changes.",
            "Cross-paper sessions keep comparison context explicit."
        ],
        root: root,
        repository: repository,
        importedAt: now
    )

    let parentCategory = Category(id: "cat-methods", parentID: nil, name: "Methods", sortOrder: 1)
    let childCategory = Category(id: "cat-methods-latent", parentID: parentCategory.id, name: "Latent Control", sortOrder: 2)
    let tagReading = PaperTag(id: "tag-reading", name: "reading")
    let tagSourceGrounded = PaperTag(id: "tag-source-grounded", name: "source-grounded")
    try repository.upsertCategory(parentCategory)
    try repository.upsertCategory(childCategory)
    try repository.upsertTag(tagReading)
    try repository.upsertTag(tagSourceGrounded)
    for paper in [paperA, paperB] {
        try repository.assignPaper(paper.id, toCategory: childCategory.id)
        try repository.assignPaper(paper.id, toTag: tagReading.id)
        try repository.assignPaper(paper.id, toTag: tagSourceGrounded.id)
    }

    let session = PaperSession(
        id: "fixture-session-compare",
        title: "Compare mechanisms",
        paperIDs: [paperA.id, paperB.id],
        codexSessionID: nil,
        workspacePath: root.appendingPathComponent("sessions/fixture-session-compare", isDirectory: true).path,
        createdAt: now,
        updatedAt: now
    )
    try repository.upsertSession(session)
    let paperASpans = try repository.fetchSpans(paperID: paperA.id)
    let paperBSpans = try repository.fetchSpans(paperID: paperB.id)
    guard let paperASpan = paperASpans.first, let paperBSpan = paperBSpans.first else {
        throw CheckFailure(description: "fixture PDFs did not produce spans")
    }
    try repository.appendMessage(ChatMessage(
        id: "fixture-message-user",
        sessionID: session.id,
        role: .user,
        content: "Compare the mechanism claims in these two papers.",
        createdAt: now
    ))
    try repository.appendMessage(ChatMessage(
        id: "fixture-message-codex",
        sessionID: session.id,
        role: .codex,
        content: "Paper A frames control through representation coordinates [[cite:\(paperASpan.id)]], while Paper B frames it as paired trajectory evaluation [[cite:\(paperBSpan.id)]].",
        createdAt: now.addingTimeInterval(1)
    ))

    let pagesByPaperID = [
        paperA.id: try repository.fetchPages(paperID: paperA.id),
        paperB.id: try repository.fetchPages(paperID: paperB.id)
    ]
    let spansByPaperID = [
        paperA.id: paperASpans,
        paperB.id: paperBSpans
    ]
    try SessionWorkspaceManager().writeWorkspace(
        session: session,
        papers: [paperA, paperB],
        pagesByPaperID: pagesByPaperID,
        spansByPaperID: spansByPaperID,
        anchorsByPaperID: [paperA.id: [], paperB.id: []]
    )
}

func seedFixturePaper(
    id: String,
    title: String,
    authors: [String],
    year: Int,
    lines: [String],
    root: URL,
    repository: PaperRepository,
    importedAt: Date
) throws -> Paper {
    let paperDir = root.appendingPathComponent("papers/\(id)", isDirectory: true)
    try FileManager.default.createDirectory(at: paperDir, withIntermediateDirectories: true)
    let pdfURL = paperDir.appendingPathComponent("original.pdf")
    try writeFixturePDF(to: pdfURL, lines: lines)
    let pdfData = try Data(contentsOf: pdfURL)
    let fileHash = SHA256.hash(data: pdfData).map { String(format: "%02x", $0) }.joined()

    let paper = Paper(
        id: id,
        filePath: pdfURL.path,
        fileHash: fileHash,
        title: title,
        authors: authors,
        year: year,
        sourceURL: nil,
        importedAt: importedAt,
        updatedAt: importedAt
    )
    try repository.upsertPaper(paper)

    let index = try PDFIndexExtractor().extract(paperID: id, pdfURL: pdfURL)
    for page in index.pages {
        try repository.upsertPage(page)
    }
    for span in index.spans {
        try repository.upsertSpan(span)
    }

    return paper
}

func writeFixturePDF(to url: URL, lines: [String]) throws {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw CheckFailure(description: "could not create PDF context")
    }
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 18),
        .foregroundColor: NSColor.black
    ]
    for (index, line) in lines.enumerated() {
        let attributed = NSAttributedString(string: line, attributes: attributes)
        attributed.draw(in: CGRect(x: 72, y: 690 - (index * 34), width: 460, height: 28))
    }
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    try data.write(to: url, options: [.atomic])
}

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "seed-fixture" {
    do {
        guard arguments.count == 2 else {
            throw CheckFailure(description: "usage: PaperCodexCoreChecks seed-fixture <support-root>")
        }
        let root = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
        try seedFixtureLibrary(at: root)
        print(root.path)
        exit(0)
    } catch {
        fputs("check failed: \(error)\n", stderr)
        exit(1)
    }
}

let selectedChecks = Set(arguments)

do {
    if selectedChecks.isEmpty || selectedChecks.contains("models") {
        try runModelsChecks()
        print("models: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("local-store-v2-models") {
        try runLocalStoreV2ModelChecks()
        print("local-store-v2-models: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("reader-tabs") {
        try runReaderTabStateChecks()
        print("reader-tabs: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("reader-positions") {
        try runReaderPositionRepositoryChecks()
        print("reader-positions: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("ui-layout-source") {
        try runUILayoutSourceChecks()
        print("ui-layout-source: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("repository") {
        try runRepositoryChecks()
        print("repository: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("local-store-v2-migration") {
        try runLocalStoreV2MigrationChecks()
        print("local-store-v2-migration: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("library-data-store") {
        try runLibraryDataStoreChecks()
        print("library-data-store: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("arxiv-cache-data-store") {
        try runArxivCacheDataStoreChecks()
        print("arxiv-cache-data-store: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("sync-data-store") {
        try runSyncDataStoreChecks()
        print("sync-data-store: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("sqlite-helpers") {
        try runSQLiteHelperChecks()
        print("sqlite-helpers: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("citations") {
        try runCitationChecks()
        print("citations: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("user-source") {
        try runUserSourceAttachmentChecks()
        print("user-source: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("anchors") {
        try runAnchorResolverChecks()
        print("anchors: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("prompt") {
        try runPromptChecks()
        print("prompt: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("workspace") {
        try runWorkspaceChecks()
        print("workspace: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("pdf") {
        try runPDFChecks()
        print("pdf: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("codex") {
        try runCodexCLIChecks()
        print("codex: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("generated-images") {
        try runGeneratedImageChecks()
        print("generated-images: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("image-requests") {
        try runImageRequestChecks()
        print("image-requests: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("codex-recovery") {
        try runCodexRecoveryChecks()
        print("codex-recovery: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("paths") {
        try runPathChecks()
        print("paths: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("bundle") {
        try runBundleChecks()
        print("bundle: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("fixture") {
        try runFixtureLibraryChecks()
        print("fixture: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("watch") {
        try runWatchedFolderChecks()
        print("watch: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("arxiv-feed") {
        try runArxivFeedChecks()
        print("arxiv-feed: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("local-arxiv-client") {
        try runLocalArxivClientChecks()
        print("local-arxiv-client: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("local-discover-engine") {
        try runLocalDiscoverEngineChecks()
        print("local-discover-engine: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("local-discover-preferences") {
        try runLocalDiscoverPreferenceChecks()
        print("local-discover-preferences: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("similarity-ranker") {
        try runSimilarityRankerChecks()
        print("similarity-ranker: pass")
    }
} catch {
    fputs("check failed: \(error)\n", stderr)
    exit(1)
}
