import Foundation

public final class SessionWorkspaceManager {
    private let encoder: JSONEncoder
    private let jsonLineEncoder: JSONEncoder

    public init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        jsonLineEncoder = JSONEncoder()
        jsonLineEncoder.outputFormatting = [.sortedKeys]
        jsonLineEncoder.dateEncodingStrategy = .iso8601
    }

    public func writeWorkspace(
        session: PaperSession,
        papers: [Paper],
        pagesByPaperID: [String: [PageIndex]],
        spansByPaperID: [String: [Span]],
        anchorsByPaperID: [String: [Anchor]]
    ) throws {
        let root = URL(fileURLWithPath: session.workspacePath, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("turns", isDirectory: true), withIntermediateDirectories: true)
        try writeJSON(session, to: root.appendingPathComponent("session.json"))
        try Self.promptContract.write(
            to: root.appendingPathComponent("prompt_contract.md"),
            atomically: true,
            encoding: .utf8
        )

        let papersRoot = root.appendingPathComponent("papers", isDirectory: true)
        try FileManager.default.createDirectory(at: papersRoot, withIntermediateDirectories: true)

        for paper in papers {
            let paperRoot = papersRoot.appendingPathComponent(paper.id, isDirectory: true)
            try FileManager.default.createDirectory(at: paperRoot, withIntermediateDirectories: true)
            let originalPDFURL = paperRoot.appendingPathComponent("original.pdf")
            let pages = pagesByPaperID[paper.id] ?? []
            let spans = sortedSpans(spansByPaperID[paper.id] ?? [])
            try writeJSON(paper, to: paperRoot.appendingPathComponent("metadata.json"))
            try copyOriginalPDF(from: URL(fileURLWithPath: paper.filePath), to: originalPDFURL)
            try writeFullText(
                paper: paper,
                originalPDFURL: originalPDFURL,
                pages: pages,
                spans: spans,
                to: paperRoot.appendingPathComponent("full_text.txt")
            )
            try writeJSONLines(pages, to: paperRoot.appendingPathComponent("pages.jsonl"))
            try writeJSONLines(spans, to: paperRoot.appendingPathComponent("spans.jsonl"))
            try writeJSONLines(anchorsByPaperID[paper.id] ?? [], to: paperRoot.appendingPathComponent("anchors.jsonl"))
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    private func writeJSONLines<T: Encodable>(_ values: [T], to url: URL) throws {
        let lines = try values.map { value in
            String(decoding: try jsonLineEncoder.encode(value), as: UTF8.self)
        }.joined(separator: "\n")
        let body = lines.isEmpty ? "" : lines + "\n"
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    private func copyOriginalPDF(from source: URL, to destination: URL) throws {
        let sourceURL = source.standardizedFileURL
        let destinationURL = destination.standardizedFileURL
        if sourceURL == destinationURL {
            return
        }
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private func writeFullText(
        paper: Paper,
        originalPDFURL: URL,
        pages: [PageIndex],
        spans: [Span],
        to url: URL
    ) throws {
        var lines: [String] = [
            "# \(paper.title)",
            "paper_id: \(paper.id)",
            "source_file_path: \(paper.filePath)",
            "original_pdf: \(originalPDFURL.path)",
            "",
            "Use the citation marker at the start of each extracted span when citing source text.",
            ""
        ]

        let spansByPage = Dictionary(grouping: spans, by: \.page)
        for page in pages.sorted(by: { $0.page < $1.page }) {
            lines.append("## Page \(page.page)")
            let pageSpans = spansByPage[page.page] ?? []
            if pageSpans.isEmpty {
                lines.append(page.text)
            } else {
                for span in pageSpans {
                    lines.append("\(citationMarker(for: span)) \(span.text)")
                }
            }
            lines.append("")
        }

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func sortedSpans(_ spans: [Span]) -> [Span] {
        spans.sorted { left, right in
            if left.page != right.page {
                return left.page < right.page
            }
            if left.charRange.location != right.charRange.location {
                return left.charRange.location < right.charRange.location
            }
            return (blockIndex(from: left.id) ?? Int.max, left.id) < (blockIndex(from: right.id) ?? Int.max, right.id)
        }
    }

    private func citationMarker(for span: Span) -> String {
        if let blockIndex = blockIndex(from: span.id) {
            return "[[cite:paper:\(span.paperID):p\(span.page):b\(blockIndex)]]"
        }
        return "[[cite:\(span.id)]]"
    }

    private func blockIndex(from spanID: String) -> Int? {
        guard let blockRange = spanID.range(of: ":b", options: .backwards) else {
            return nil
        }
        return Int(spanID[blockRange.upperBound...])
    }

    public static let promptContract = """
    # Paper Codex Prompt Contract

    The original PDF is the primary source. Use the full local index files as navigation aids.

    Each paper workspace contains:

    - original.pdf: local copy of the source PDF
    - full_text.txt: full extracted text with citation markers
    - pages.jsonl: all extracted page text, one page per line
    - spans.jsonl: all extracted text spans with bounding boxes, one span per line
    - anchors.jsonl: user-created selections

    Use citation IDs exactly:

    - [[cite:paper:{paper_id}:p{page}:b{block_index}]]
    - [[cite:paper:{paper_id}:p{page}:a{anchor_suffix}]]

    If evidence is insufficient, say so clearly. Do not invent source positions.
    """
}
