import Foundation
import AppKit
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
    let fetchedCategories = try repository.fetchCategories()
    let fetchedAllTags = try repository.fetchTags()
    let fetchedTags = try repository.fetchTags(forPaperID: "paper-a")
    let fetchedCategoryIDs = try repository.fetchCategoryIDs(forPaperID: "paper-a")
    let fetchedPages = try repository.fetchPages(paperID: "paper-a")
    let fetchedSpans = try repository.fetchSpans(paperID: "paper-a")
    let fetchedAnchors = try repository.fetchAnchors(paperID: "paper-a")
    let fetchedSessions = try repository.fetchSessions(paperID: "paper-a")
    let fetchedMessages = try repository.fetchMessages(sessionID: "session-a")

    try check(fetchedPapers == [paper], "paper should round-trip through SQLite")
    try check(fetchedCategories == [category, childCategory], "categories should preserve hierarchy and sort order")
    try check(fetchedAllTags == [tag, unassignedTag], "all tags should round-trip sorted by name")
    try check(fetchedTags == [tag], "paper tags should round-trip")
    try check(fetchedCategoryIDs == ["cat-vae"], "paper category links should round-trip")
    try check(fetchedPages == [page], "page indexes should round-trip")
    try check(fetchedSpans == [span], "spans should round-trip")
    try check(fetchedAnchors == [anchor], "anchors should round-trip")
    try check(fetchedSessions == [session], "sessions should round-trip")
    try check(fetchedMessages == [message], "messages should round-trip")

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

let selectedChecks = Set(CommandLine.arguments.dropFirst())

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
} catch {
    fputs("check failed: \(error)\n", stderr)
    exit(1)
}
