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
}

func runCitationChecks() throws {
    let parsed = CitationParser.parse("Answer [[cite:paper:paper-a:p5:b17]] and [[cite:paper:paper-a:p5:asel1]].")
    try check(parsed.citations.map(\.id) == ["paper:paper-a:p5:b17", "paper:paper-a:p5:asel1"], "citation parser should preserve citation IDs")
    try check(parsed.displayText == "Answer [1] and [2].", "citation parser should replace markers with display indices")

    let malformed = CitationParser.parse("Broken [[cite:not-a-paper]] marker.")
    try check(malformed.citations.isEmpty, "malformed markers should not become citations")
    try check(malformed.brokenMarkers == ["[[cite:not-a-paper]]"], "malformed markers should be reported")
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
        text: "The selected mechanism controls latent trajectories.",
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
    try check(prompt.contains("anchor_id: paper:paper-a:p5:asel1"), "prompt should include selected anchor ID")
    try check(prompt.contains("span_id: paper:paper-a:p5:b17"), "prompt should include relevant span ID")
    try check(prompt.contains("workspace: /tmp/session-a"), "prompt should include workspace guidance")
    try check(prompt.contains("[[cite:paper:{paper_id}:p{page}:b{block_index}]]"), "prompt should include citation contract")
}

func runWorkspaceChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-workspace-\(UUID().uuidString)", isDirectory: true)
    let now = Date(timeIntervalSince1970: 1_777_220_000)
    let paper = Paper(
        id: "paper-a",
        filePath: "/tmp/paper.pdf",
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
        workspacePath: tempRoot.path,
        createdAt: now,
        updatedAt: now
    )
    let page = PageIndex(paperID: "paper-a", page: 1, text: "Page text", confidence: 0.95)
    let span = Span(
        id: Span.makeID(paperID: "paper-a", page: 1, blockIndex: 1),
        paperID: "paper-a",
        page: 1,
        bbox: BoundingBox(x: 1, y: 2, width: 3, height: 4),
        text: "Page text",
        charRange: TextRange(location: 0, length: 9),
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
        spansByPaperID: ["paper-a": [span]],
        anchorsByPaperID: ["paper-a": [anchor]]
    )

    let paperDir = tempRoot.appendingPathComponent("papers/paper-a", isDirectory: true)
    try check(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("session.json").path), "workspace should contain session.json")
    try check(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("prompt_contract.md").path), "workspace should contain prompt contract")
    try check(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("turns", isDirectory: true).path), "workspace should contain turns directory")
    try check(FileManager.default.fileExists(atPath: paperDir.appendingPathComponent("metadata.json").path), "workspace should contain paper metadata")
    try check(FileManager.default.fileExists(atPath: paperDir.appendingPathComponent("pages.jsonl").path), "workspace should contain pages jsonl")
    try check(FileManager.default.fileExists(atPath: paperDir.appendingPathComponent("spans.jsonl").path), "workspace should contain spans jsonl")
    try check(FileManager.default.fileExists(atPath: paperDir.appendingPathComponent("anchors.jsonl").path), "workspace should contain anchors jsonl")

    let spans = try String(contentsOf: paperDir.appendingPathComponent("spans.jsonl"), encoding: .utf8)
    try check(spans.contains("paper:paper-a:p1:b1"), "spans jsonl should include span ID")
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
}

func runCodexCLIChecks() throws {
    let codexPath = try CodexCLI.findCodexExecutable()
    try check(FileManager.default.isExecutableFile(atPath: codexPath), "codex executable should be runnable")

    let cli = CodexCLI(executablePath: codexPath)
    let start = cli.startArguments(prompt: "hello", workspacePath: "/tmp/session-a")
    try check(start == ["exec", "--json", "-C", "/tmp/session-a", "hello"], "start args should use codex exec with JSON output and workspace")
    let startWithOutput = cli.startArguments(prompt: "hello", workspacePath: "/tmp/session-a", outputLastMessagePath: "/tmp/last.txt")
    try check(startWithOutput == ["exec", "--json", "-C", "/tmp/session-a", "--output-last-message", "/tmp/last.txt", "hello"], "start args should support output-last-message")

    let resume = cli.resumeArguments(sessionID: "session-a", prompt: "continue")
    try check(resume == ["exec", "resume", "--json", "session-a", "continue"], "resume args should use codex exec resume with JSON output")
    let parsedThreadID = CodexCLI.parseThreadID(from: #"{"type":"thread.started","thread_id":"019dcaf6-01d5-7060-bc43-40401e3693c3"}"#)
    try check(parsedThreadID == "019dcaf6-01d5-7060-bc43-40401e3693c3", "Codex thread ID should be parsed from JSONL output")

    let parsedVersion = CodexCLI.parseVersion(from: "codex-cli 0.114.0\n")
    try check(parsedVersion == "0.114.0", "Codex version parser should read codex-cli output")
    let help = "Usage: codex exec [OPTIONS]\n      --json\n  -o, --output-last-message <FILE>\nCommands:\n  resume\n"
    let capabilities = CodexCLI.parseCapabilities(fromExecHelp: help)
    try check(capabilities.supportsJSONOutput, "Codex help parser should detect JSON output support")
    try check(capabilities.supportsOutputLastMessage, "Codex help parser should detect last-message output support")
    try check(capabilities.supportsResume, "Codex help parser should detect resume support")
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
    try check(CodexCLI.configuredModelIssue(configText: #"model = "gpt-5.4""#, cliVersion: "0.114.0") == nil, "other configured models should not be blocked by the gpt-5.5 compatibility rule")
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
    if selectedChecks.isEmpty || selectedChecks.contains("repository") {
        try runRepositoryChecks()
        print("repository: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("citations") {
        try runCitationChecks()
        print("citations: pass")
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
    if selectedChecks.isEmpty || selectedChecks.contains("codex-recovery") {
        try runCodexRecoveryChecks()
        print("codex-recovery: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("paths") {
        try runPathChecks()
        print("paths: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("fixture") {
        try runFixtureLibraryChecks()
        print("fixture: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("watch") {
        try runWatchedFolderChecks()
        print("watch: pass")
    }
} catch {
    fputs("check failed: \(error)\n", stderr)
    exit(1)
}
