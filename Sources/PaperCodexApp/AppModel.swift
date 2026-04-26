import Foundation
import PaperCodexCore
import SwiftUI

enum AppRoute {
    case library
    case reader
}

struct PDFSelectionInfo: Equatable {
    var text: String
    var page: Int
    var bboxList: [BoundingBox]
}

struct PDFJumpTarget: Equatable {
    var id: String
    var paperID: String
    var page: Int
    var bboxList: [BoundingBox]
    var label: String
}

private struct SessionPaperContext {
    var papers: [Paper]
    var pagesByPaperID: [String: [PageIndex]]
    var spansByPaperID: [String: [Span]]
    var anchorsByPaperID: [String: [PaperCodexCore.Anchor]]

    var spans: [Span] {
        papers.flatMap { spansByPaperID[$0.id] ?? [] }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var route: AppRoute = .library
    @Published var papers: [Paper] = []
    @Published var categories: [PaperCodexCore.Category] = []
    @Published var tags: [PaperTag] = []
    @Published var watchedFolders: [WatchedFolder] = []
    @Published var paperCategoryIDsByID: [String: [String]] = [:]
    @Published var paperTagsByID: [String: [PaperTag]] = [:]
    @Published var selectedLibraryPaper: Paper?
    @Published var selectedPaper: Paper?
    @Published var selectedSession: PaperSession?
    @Published var sessions: [PaperSession] = []
    @Published var messages: [ChatMessage] = []
    @Published var currentSelection: PDFSelectionInfo?
    @Published var pdfJumpTarget: PDFJumpTarget?
    @Published var codexDiagnostic: CodexDiagnostic?
    @Published var errorMessage: String?
    @Published var isSending = false
    @Published var isScanningWatchedFolders = false

    private var repository: PaperRepository?
    private let supportRoot: URL
    private let workspaceManager = SessionWorkspaceManager()
    private var watchedFolderAutoScanTask: Task<Void, Never>?

    init() {
        let root = PaperCodexPaths.supportRoot()
        supportRoot = root
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = try PaperRepository(databasePath: root.appendingPathComponent("store.sqlite").path)
            try store.migrate()
            repository = store
            try reloadLibrary()
            Task {
                scanWatchedFolders()
                await refreshCodexDiagnostic()
            }
            startWatchedFolderAutoScan()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    deinit {
        watchedFolderAutoScanTask?.cancel()
    }

    func reloadLibrary() throws {
        guard let repository else {
            return
        }
        let selectedLibraryPaperID = selectedLibraryPaper?.id
        papers = try repository.fetchPapers()
        categories = try repository.fetchCategories()
        tags = try repository.fetchTags()
        watchedFolders = try repository.fetchWatchedFolders()
        paperCategoryIDsByID = try Dictionary(uniqueKeysWithValues: papers.map { paper in
            (paper.id, try repository.fetchCategoryIDs(forPaperID: paper.id))
        })
        paperTagsByID = try Dictionary(uniqueKeysWithValues: papers.map { paper in
            (paper.id, try repository.fetchTags(forPaperID: paper.id))
        })
        if let selectedLibraryPaperID {
            selectedLibraryPaper = papers.first { $0.id == selectedLibraryPaperID }
        }
    }

    func importPDF(from sourceURL: URL) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let result = try PaperLibraryImporter(repository: repository, supportRoot: supportRoot)
                .importPDF(from: sourceURL)
            try reloadLibrary()
            openPaper(result.paper)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func addWatchedFolder(from sourceURL: URL) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let path = sourceURL.standardizedFileURL.path
            let folder = watchedFolders.first { $0.path == path } ?? WatchedFolder(
                id: makeManualID(prefix: "watch", name: sourceURL.lastPathComponent),
                path: path,
                createdAt: Date(),
                lastScannedAt: nil
            )
            try repository.upsertWatchedFolder(folder)
            try reloadLibrary()
            try scanWatchedFolder(folder)
            try reloadLibrary()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func scanWatchedFolders() {
        do {
            guard !isScanningWatchedFolders else {
                return
            }
            guard !watchedFolders.isEmpty else {
                return
            }
            isScanningWatchedFolders = true
            defer {
                isScanningWatchedFolders = false
            }

            _ = try scanAllWatchedFolders()
            try reloadLibrary()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func removeWatchedFolder(_ folder: WatchedFolder) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            try repository.deleteWatchedFolder(id: folder.id)
            try reloadLibrary()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func selectLibraryPaper(_ paper: Paper) {
        selectedLibraryPaper = paper
    }

    func createCategory(name: String, parentID: String?) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AppModelError.emptyName
            }
            let nextSortOrder = (categories.map(\.sortOrder).max() ?? 0) + 1
            let category = PaperCodexCore.Category(
                id: makeManualID(prefix: "cat", name: trimmed),
                parentID: parentID,
                name: trimmed,
                sortOrder: nextSortOrder
            )
            try repository.upsertCategory(category)
            try reloadLibrary()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func createTag(name: String) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AppModelError.emptyName
            }
            if tags.contains(where: { $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                return
            }
            try repository.upsertTag(PaperTag(id: makeManualID(prefix: "tag", name: trimmed), name: trimmed))
            try reloadLibrary()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func setCategory(_ categoryID: String, assigned: Bool, for paper: Paper) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            if assigned {
                try repository.assignPaper(paper.id, toCategory: categoryID)
            } else {
                try repository.removePaper(paper.id, fromCategory: categoryID)
            }
            try reloadLibrary()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func setTag(_ tagID: String, assigned: Bool, for paper: Paper) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            if assigned {
                try repository.assignPaper(paper.id, toTag: tagID)
            } else {
                try repository.removePaper(paper.id, fromTag: tagID)
            }
            try reloadLibrary()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func openPaper(_ paper: Paper) {
        do {
            selectedLibraryPaper = paper
            selectedPaper = paper
            currentSelection = nil
            pdfJumpTarget = nil
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            sessions = try repository.fetchSessions(paperID: paper.id)
            if let first = sessions.last {
                selectedSession = first
                messages = try repository.fetchMessages(sessionID: first.id)
            } else {
                try createSession()
            }
            route = .reader
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func createSession() throws {
        guard let paper = selectedPaper else {
            throw AppModelError.noSelectedPaper
        }
        guard let repository else {
            throw AppModelError.repositoryUnavailable
        }
        let now = Date()
        let sessionID = UUID().uuidString.lowercased()
        let workspacePath = supportRoot.appendingPathComponent("sessions/\(sessionID)", isDirectory: true).path
        let session = PaperSession(
            id: sessionID,
            title: "\(paper.title) Notes",
            paperIDs: [paper.id],
            codexSessionID: nil,
            workspacePath: workspacePath,
            createdAt: now,
            updatedAt: now
        )
        try repository.upsertSession(session)
        let context = try loadSessionPaperContext(session: session, fallbackPaper: paper, repository: repository)
        try workspaceManager.writeWorkspace(
            session: session,
            papers: context.papers,
            pagesByPaperID: context.pagesByPaperID,
            spansByPaperID: context.spansByPaperID,
            anchorsByPaperID: context.anchorsByPaperID
        )
        sessions = try repository.fetchSessions(paperID: paper.id)
        selectedSession = session
        messages = []
    }

    func newSessionButtonTapped() {
        do {
            try createSession()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func selectSession(_ sessionID: String) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            guard let session = sessions.first(where: { $0.id == sessionID }) else {
                return
            }
            selectedSession = session
            messages = try repository.fetchMessages(sessionID: session.id)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func selectReaderPaper(_ paper: Paper) {
        guard selectedSession?.paperIDs.contains(paper.id) == true else {
            return
        }
        selectedPaper = paper
        currentSelection = nil
        pdfJumpTarget = nil
    }

    func setPaper(_ paper: Paper, includedInCurrentSession included: Bool) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            guard var session = selectedSession else {
                throw AppModelError.noSelectedSession
            }

            var paperIDs = session.paperIDs
            if included {
                if !paperIDs.contains(paper.id) {
                    paperIDs.append(paper.id)
                }
            } else {
                guard paperIDs.count > 1 else {
                    return
                }
                paperIDs.removeAll { $0 == paper.id }
            }

            session.paperIDs = paperIDs
            session.updatedAt = Date()
            try repository.upsertSession(session)

            if selectedPaper.map({ !paperIDs.contains($0.id) }) == true,
               let firstPaperID = paperIDs.first,
               let replacement = try repository.fetchPapers(ids: [firstPaperID]).first {
                selectedPaper = replacement
                currentSelection = nil
                pdfJumpTarget = nil
            }

            let storedSession = try repository.fetchSession(id: session.id) ?? session
            let fallback = selectedPaper ?? paper
            let context = try loadSessionPaperContext(session: storedSession, fallbackPaper: fallback, repository: repository)
            try workspaceManager.writeWorkspace(
                session: storedSession,
                papers: context.papers,
                pagesByPaperID: context.pagesByPaperID,
                spansByPaperID: context.spansByPaperID,
                anchorsByPaperID: context.anchorsByPaperID
            )

            selectedSession = storedSession
            if let selectedPaper {
                sessions = try repository.fetchSessions(paperID: selectedPaper.id)
            }
            messages = try repository.fetchMessages(sessionID: storedSession.id)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func updateSelection(_ selection: PDFSelectionInfo?) {
        currentSelection = selection
    }

    func refreshCodexDiagnostic() async {
        codexDiagnostic = nil
        let diagnostic = await Task.detached(priority: .utility) {
            CodexCLI.diagnose()
        }.value
        codexDiagnostic = diagnostic
    }

    func jumpToCitation(_ citationID: String) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            if let span = try repository.fetchSpan(id: citationID) {
                if selectedPaper?.id != span.paperID, let paper = papers.first(where: { $0.id == span.paperID }) {
                    selectedPaper = paper
                }
                pdfJumpTarget = PDFJumpTarget(
                    id: span.id,
                    paperID: span.paperID,
                    page: span.page,
                    bboxList: [span.bbox],
                    label: span.text
                )
                return
            }
            if let anchor = try repository.fetchAnchor(id: citationID) {
                if selectedPaper?.id != anchor.paperID, let paper = papers.first(where: { $0.id == anchor.paperID }) {
                    selectedPaper = paper
                }
                pdfJumpTarget = PDFJumpTarget(
                    id: anchor.id,
                    paperID: anchor.paperID,
                    page: anchor.page,
                    bboxList: anchor.bboxList,
                    label: anchor.selectedText
                )
                return
            }
            throw AppModelError.sourceNotFound(citationID)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        guard !isSending else {
            return
        }
        isSending = true
        defer {
            isSending = false
        }

        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            guard let paper = selectedPaper else {
                throw AppModelError.noSelectedPaper
            }
            guard var session = selectedSession else {
                throw AppModelError.noSelectedSession
            }

            var context = try loadSessionPaperContext(session: session, fallbackPaper: paper, repository: repository)
            let focusedSpans = context.spansByPaperID[paper.id] ?? []
            var content = trimmed
            var selectedAnchors: [PaperCodexCore.Anchor] = []
            if let selection = currentSelection {
                let anchorID = PaperCodexCore.Anchor.makeID(paperID: paper.id, page: selection.page, suffix: UUID().uuidString.lowercased())
                let anchor = AnchorResolver().resolve(
                    paperID: paper.id,
                    page: selection.page,
                    selectedText: selection.text,
                    bboxList: selection.bboxList,
                    spans: focusedSpans,
                    anchorID: anchorID,
                    sessionID: session.id,
                    createdAt: Date()
                )
                let nearbySpans = anchor.matchedSpanIDs.isEmpty ? "none" : anchor.matchedSpanIDs.joined(separator: ", ")
                let beforeContext = anchor.beforeContext.isEmpty ? "none" : anchor.beforeContext
                let afterContext = anchor.afterContext.isEmpty ? "none" : anchor.afterContext
                content += """

                [selected source]
                anchor_id: \(anchor.id)
                paper_id: \(anchor.paperID)
                page: \(anchor.page)
                text: "\(anchor.selectedText)"
                nearby_spans: \(nearbySpans)
                before: "\(beforeContext)"
                after: "\(afterContext)"
                """
                try repository.upsertAnchor(anchor)
                selectedAnchors = [anchor]
                context.anchorsByPaperID[paper.id] = try repository.fetchAnchors(paperID: paper.id)
                currentSelection = nil
            }

            let message = ChatMessage(
                id: UUID().uuidString.lowercased(),
                sessionID: session.id,
                role: .user,
                content: content,
                createdAt: Date()
            )
            try repository.appendMessage(message)
            session.updatedAt = Date()
            try repository.upsertSession(session)
            selectedSession = session
            sessions = try repository.fetchSessions(paperID: paper.id)
            messages = try repository.fetchMessages(sessionID: session.id)

            try workspaceManager.writeWorkspace(
                session: session,
                papers: context.papers,
                pagesByPaperID: context.pagesByPaperID,
                spansByPaperID: context.spansByPaperID,
                anchorsByPaperID: context.anchorsByPaperID
            )

            let prompt = PromptBuilder().buildPrompt(
                request: PromptRequest(
                    userMessage: content,
                    workspacePath: session.workspacePath,
                    papers: context.papers,
                    selectedAnchors: selectedAnchors,
                    relevantSpans: relevantSpans(from: context.spans, selectedAnchors: selectedAnchors)
                )
            )
            let codexReply = try await runCodex(prompt: prompt, session: session)
            var updatedSession = session
            if let threadID = codexReply.threadID {
                updatedSession.codexSessionID = threadID
            }
            updatedSession.updatedAt = Date()
            try repository.upsertSession(updatedSession)

            let codexMessage = ChatMessage(
                id: UUID().uuidString.lowercased(),
                sessionID: session.id,
                role: .codex,
                content: codexReply.lastMessage.isEmpty ? codexReply.stdout : codexReply.lastMessage,
                createdAt: Date()
            )
            try repository.appendMessage(codexMessage)
            selectedSession = updatedSession
            sessions = try repository.fetchSessions(paperID: paper.id)
            messages = try repository.fetchMessages(sessionID: session.id)
        } catch {
            await appendCodexFailureMessage(String(describing: error))
        }
    }

    func goToLibrary() {
        route = .library
        selectedPaper = nil
        selectedSession = nil
        sessions = []
        messages = []
        currentSelection = nil
        pdfJumpTarget = nil
    }

    private func loadSessionPaperContext(
        session: PaperSession,
        fallbackPaper: Paper,
        repository: PaperRepository
    ) throws -> SessionPaperContext {
        let paperIDs = uniqueIDs(session.paperIDs + [fallbackPaper.id])
        let fetchedPapers = try repository.fetchPapers(ids: paperIDs)
        let papers = fetchedPapers.isEmpty ? [fallbackPaper] : fetchedPapers
        var pagesByPaperID: [String: [PageIndex]] = [:]
        var spansByPaperID: [String: [Span]] = [:]
        var anchorsByPaperID: [String: [PaperCodexCore.Anchor]] = [:]
        for paper in papers {
            pagesByPaperID[paper.id] = try repository.fetchPages(paperID: paper.id)
            spansByPaperID[paper.id] = try repository.fetchSpans(paperID: paper.id)
            anchorsByPaperID[paper.id] = try repository.fetchAnchors(paperID: paper.id)
        }
        return SessionPaperContext(
            papers: papers,
            pagesByPaperID: pagesByPaperID,
            spansByPaperID: spansByPaperID,
            anchorsByPaperID: anchorsByPaperID
        )
    }

    private func relevantSpans(from spans: [Span], selectedAnchors: [PaperCodexCore.Anchor]) -> [Span] {
        let matchedSpanIDs = selectedAnchors.flatMap(\.matchedSpanIDs)
        let matchedSet = Set(matchedSpanIDs)
        let matchedSpans = matchedSpanIDs.compactMap { id in
            spans.first { $0.id == id }
        }
        let fallbackSpans = spans.filter { !matchedSet.contains($0.id) }
        return Array((matchedSpans + fallbackSpans).prefix(8))
    }

    private func uniqueIDs(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for id in ids where !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        return result
    }

    private func makeManualID(prefix: String, name: String) -> String {
        let slug = makeSlug(from: name)
        return "\(prefix)-\(slug.isEmpty ? "item" : slug)-\(UUID().uuidString.prefix(8).lowercased())"
    }

    private func makeSlug(from text: String) -> String {
        text
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { partial, character in
                if character == "-", partial.last == "-" {
                    return
                }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func scanWatchedFolder(_ folder: WatchedFolder) throws {
        guard let repository else {
            throw AppModelError.repositoryUnavailable
        }
        _ = try WatchedFolderScanner(repository: repository, supportRoot: supportRoot)
            .scan(folder: folder)
    }

    private func scanAllWatchedFolders() throws -> [WatchedFolderScanResult] {
        guard let repository else {
            throw AppModelError.repositoryUnavailable
        }
        return try WatchedFolderScanner(repository: repository, supportRoot: supportRoot)
            .scanAllWatchedFolders()
    }

    private func startWatchedFolderAutoScan() {
        watchedFolderAutoScanTask?.cancel()
        watchedFolderAutoScanTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else {
                    return
                }
                self?.scanWatchedFoldersIfNeeded()
            }
        }
    }

    private func scanWatchedFoldersIfNeeded() {
        guard !watchedFolders.isEmpty else {
            return
        }
        scanWatchedFolders()
    }

    private func runCodex(prompt: String, session: PaperSession) async throws -> (stdout: String, lastMessage: String, threadID: String?) {
        let executable = try CodexCLI.findCodexExecutable()
        let cli = CodexCLI(executablePath: executable)
        let outputURL = URL(fileURLWithPath: session.workspacePath)
            .appendingPathComponent("turns", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString.lowercased())-codex.txt")
        let arguments: [String]
        if let codexSessionID = session.codexSessionID {
            arguments = cli.resumeArguments(
                sessionID: codexSessionID,
                prompt: prompt,
                outputLastMessagePath: outputURL.path
            )
        } else {
            arguments = cli.startArguments(
                prompt: prompt,
                workspacePath: session.workspacePath,
                outputLastMessagePath: outputURL.path
            )
        }

        let stdout = try await Task.detached(priority: .userInitiated) {
            try cli.run(arguments: arguments)
        }.value
        let lastMessage = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        return (stdout: stdout, lastMessage: lastMessage, threadID: CodexCLI.parseThreadID(from: stdout))
    }

    private func appendCodexFailureMessage(_ failure: String) async {
        guard let repository, let session = selectedSession else {
            errorMessage = failure
            return
        }
        do {
            let message = ChatMessage(
                id: UUID().uuidString.lowercased(),
                sessionID: session.id,
                role: .codex,
                content: "Codex failed: \(failure)",
                createdAt: Date()
            )
            try repository.appendMessage(message)
            messages = try repository.fetchMessages(sessionID: session.id)
        } catch {
            errorMessage = "\(failure)\n\nAlso failed to store error message: \(error)"
        }
    }
}

enum AppModelError: Error, CustomStringConvertible {
    case repositoryUnavailable
    case noSelectedPaper
    case noSelectedSession
    case emptyName
    case sourceNotFound(String)

    var description: String {
        switch self {
        case .repositoryUnavailable:
            "Local repository is not available."
        case .noSelectedPaper:
            "No paper is selected."
        case .noSelectedSession:
            "No Codex session is selected."
        case .emptyName:
            "Name cannot be empty."
        case let .sourceNotFound(id):
            "No source was found for citation \(id)."
        }
    }
}
