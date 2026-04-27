import Foundation

public struct PromptRequest: Equatable, Sendable {
    public var userMessage: String
    public var workspacePath: String
    public var papers: [Paper]
    public var selectedAnchors: [Anchor]
    public var relevantSpans: [Span]

    public init(
        userMessage: String,
        workspacePath: String,
        papers: [Paper],
        selectedAnchors: [Anchor],
        relevantSpans: [Span]
    ) {
        self.userMessage = userMessage
        self.workspacePath = workspacePath
        self.papers = papers
        self.selectedAnchors = selectedAnchors
        self.relevantSpans = relevantSpans
    }
}

public struct PromptBuilder: Sendable {
    public init() {}

    public func buildPrompt(request: PromptRequest) -> String {
        var sections: [String] = []
        sections.append("""
        You are Codex working inside a local paper-reading workspace.

        workspace: \(request.workspacePath)

        Rules:
        - Explain and reason normally.
        - The original PDFs and full extracted text/index files are available inside the workspace.
        - Decide what to inspect from the workspace files before answering.
        - Ground claims in the original PDF, full text, anchors, spans, or workspace files.
        - Cite source positions exactly as [[cite:paper:{paper_id}:p{page}:b{block_index}]] or [[cite:paper:{paper_id}:p{page}:a{anchor_suffix}]].
        - If evidence is insufficient, say what is missing.
        - Do not invent paper positions.
        """)

        sections.append("""
        [user message]
        \(request.userMessage)
        """)

        if !request.papers.isEmpty {
            let paperLines = request.papers.map { paper in
                let authors = paper.authors.joined(separator: ", ")
                let year = paper.year.map(String.init) ?? "unknown year"
                let source = paper.sourceURL ?? "no source URL"
                return "- paper_id: \(paper.id)\n  title: \(paper.title)\n  authors: \(authors)\n  year: \(year)\n  source: \(source)\n  file_hash: \(paper.fileHash)"
            }
            sections.append("""
            [papers]
            \(paperLines.joined(separator: "\n"))
            """)

            let workspaceRoot = URL(fileURLWithPath: request.workspacePath, isDirectory: true)
            let paperWorkspaceLines = request.papers.map { paper in
                let paperRoot = workspaceRoot
                    .appendingPathComponent("papers", isDirectory: true)
                    .appendingPathComponent(paper.id, isDirectory: true)
                return """
                [paper workspace]
                paper_id: \(paper.id)
                paper_dir: \(paperRoot.path)
                original_pdf: \(paperRoot.appendingPathComponent("original.pdf").path)
                full_text: \(paperRoot.appendingPathComponent("full_text.txt").path)
                pages_jsonl: \(paperRoot.appendingPathComponent("pages.jsonl").path)
                spans_jsonl: \(paperRoot.appendingPathComponent("spans.jsonl").path)
                anchors_jsonl: \(paperRoot.appendingPathComponent("anchors.jsonl").path)
                metadata_json: \(paperRoot.appendingPathComponent("metadata.json").path)
                """
            }
            sections.append("""
            [workspace files]
            Inspect these files directly. Do not treat the prompt as the full paper text.

            \(paperWorkspaceLines.joined(separator: "\n\n"))
            """)
        }

        if !request.selectedAnchors.isEmpty {
            let anchorBlocks = request.selectedAnchors.map { anchor in
                """
                [selected source]
                anchor_id: \(anchor.id)
                paper_id: \(anchor.paperID)
                page: \(anchor.page)
                text: "\(anchor.selectedText)"
                nearby_spans: \(anchor.matchedSpanIDs.joined(separator: ", "))
                before: "\(anchor.beforeContext)"
                after: "\(anchor.afterContext)"
                confidence: \(anchor.confidence)
                """
            }
            sections.append(anchorBlocks.joined(separator: "\n\n"))
        }

        return sections.joined(separator: "\n\n")
    }
}
