import CryptoKit
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
    var bbox: BoundingBox
}

@MainActor
final class AppModel: ObservableObject {
    @Published var route: AppRoute = .library
    @Published var papers: [Paper] = []
    @Published var categories: [PaperCodexCore.Category] = []
    @Published var tags: [PaperTag] = []
    @Published var paperCategoryIDsByID: [String: [String]] = [:]
    @Published var paperTagsByID: [String: [PaperTag]] = [:]
    @Published var selectedLibraryPaper: Paper?
    @Published var selectedPaper: Paper?
    @Published var selectedSession: PaperSession?
    @Published var sessions: [PaperSession] = []
    @Published var messages: [ChatMessage] = []
    @Published var currentSelection: PDFSelectionInfo?
    @Published var errorMessage: String?
    @Published var isSending = false

    private var repository: PaperRepository?
    private let supportRoot: URL
    private let workspaceManager = SessionWorkspaceManager()

    init() {
        let root = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PaperCodex", isDirectory: true)
        supportRoot = root
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = try PaperRepository(databasePath: root.appendingPathComponent("store.sqlite").path)
            try store.migrate()
            repository = store
            try reloadLibrary()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func reloadLibrary() throws {
        guard let repository else {
            return
        }
        let selectedLibraryPaperID = selectedLibraryPaper?.id
        papers = try repository.fetchPapers()
        categories = try repository.fetchCategories()
        tags = try repository.fetchTags()
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

            let data = try Data(contentsOf: sourceURL)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let title = sourceURL.deletingPathExtension().lastPathComponent
            let paperID = makePaperID(title: title, hash: hash)
            let paperDir = supportRoot.appendingPathComponent("papers/\(paperID)", isDirectory: true)
            try FileManager.default.createDirectory(at: paperDir, withIntermediateDirectories: true)
            let destination = paperDir.appendingPathComponent("original.pdf")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try data.write(to: destination, options: [.atomic])

            let now = Date()
            let paper = Paper(
                id: paperID,
                filePath: destination.path,
                fileHash: hash,
                title: title,
                authors: [],
                year: nil,
                sourceURL: nil,
                importedAt: now,
                updatedAt: now
            )
            try repository.upsertPaper(paper)

            let index = try PDFIndexExtractor().extract(paperID: paperID, pdfURL: destination)
            for page in index.pages {
                try repository.upsertPage(page)
            }
            for span in index.spans {
                try repository.upsertSpan(span)
            }

            try reloadLibrary()
            openPaper(paper)
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
        let pages = try repository.fetchPages(paperID: paper.id)
        let spans = try repository.fetchSpans(paperID: paper.id)
        let anchors = try repository.fetchAnchors(paperID: paper.id)
        try workspaceManager.writeWorkspace(
            session: session,
            papers: [paper],
            pagesByPaperID: [paper.id: pages],
            spansByPaperID: [paper.id: spans],
            anchorsByPaperID: [paper.id: anchors]
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

    func updateSelection(_ selection: PDFSelectionInfo?) {
        currentSelection = selection
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

            var content = trimmed
            var selectedAnchors: [PaperCodexCore.Anchor] = []
            if let selection = currentSelection {
                let anchorID = PaperCodexCore.Anchor.makeID(paperID: paper.id, page: selection.page, suffix: UUID().uuidString.lowercased())
                let anchor = PaperCodexCore.Anchor(
                    id: anchorID,
                    paperID: paper.id,
                    page: selection.page,
                    selectedText: selection.text,
                    bboxList: [selection.bbox],
                    matchedSpanIDs: [],
                    beforeContext: "",
                    afterContext: "",
                    createdSessionID: session.id,
                    createdAt: Date(),
                    confidence: 0.75
                )
                try repository.upsertAnchor(anchor)
                selectedAnchors = [anchor]
                content += "\n\n[selected source]\nanchor_id: \(anchor.id)\npage: \(anchor.page)\ntext: \"\(anchor.selectedText)\""
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

            let pages = try repository.fetchPages(paperID: paper.id)
            let spans = try repository.fetchSpans(paperID: paper.id)
            let anchors = try repository.fetchAnchors(paperID: paper.id)
            try workspaceManager.writeWorkspace(
                session: session,
                papers: [paper],
                pagesByPaperID: [paper.id: pages],
                spansByPaperID: [paper.id: spans],
                anchorsByPaperID: [paper.id: anchors]
            )

            let prompt = PromptBuilder().buildPrompt(
                request: PromptRequest(
                    userMessage: content,
                    workspacePath: session.workspacePath,
                    papers: [paper],
                    selectedAnchors: selectedAnchors,
                    relevantSpans: Array(spans.prefix(8))
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
    }

    private func makeManualID(prefix: String, name: String) -> String {
        let slug = makeSlug(from: name)
        return "\(prefix)-\(slug.isEmpty ? "item" : slug)-\(UUID().uuidString.prefix(8).lowercased())"
    }

    private func makePaperID(title: String, hash: String) -> String {
        let slug = makeSlug(from: title)
        return "\(slug.isEmpty ? "paper" : slug)-\(hash.prefix(10))"
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
        }
    }
}
