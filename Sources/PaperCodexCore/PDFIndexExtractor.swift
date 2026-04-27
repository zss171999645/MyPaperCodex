import Foundation
import PDFKit

public struct PDFIndexResult: Equatable, Sendable {
    public var pages: [PageIndex]
    public var spans: [Span]

    public init(pages: [PageIndex], spans: [Span]) {
        self.pages = pages
        self.spans = spans
    }
}

public enum PDFIndexExtractorError: Error, CustomStringConvertible, Equatable {
    case cannotOpenPDF(String)
    case noTextLayer(String)

    public var description: String {
        switch self {
        case let .cannotOpenPDF(path):
            "Could not open PDF at \(path)"
        case let .noTextLayer(path):
            "PDF has no usable text layer: \(path)"
        }
    }
}

public struct PDFIndexExtractor: Sendable {
    public init() {}

    public func extract(paperID: String, pdfURL: URL) throws -> PDFIndexResult {
        guard let document = PDFDocument(url: pdfURL) else {
            throw PDFIndexExtractorError.cannotOpenPDF(pdfURL.path)
        }

        var pages: [PageIndex] = []
        var spans: [Span] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                continue
            }
            let pageNumber = pageIndex + 1
            let pageText = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if pageText.isEmpty {
                continue
            }

            pages.append(PageIndex(paperID: paperID, page: pageNumber, text: pageText, confidence: 1.0))
            let textLines = indexedLines(in: pageText)
            let blocks = mergeLinesIntoBlocks(textLines)

            for (blockIndex, block) in blocks.enumerated() {
                let bbox = bounds(for: page, range: NSRange(location: block.charRange.location, length: block.charRange.length))
                spans.append(Span(
                    id: Span.makeID(paperID: paperID, page: pageNumber, blockIndex: blockIndex + 1),
                    paperID: paperID,
                    page: pageNumber,
                    bbox: bbox,
                    text: block.text,
                    charRange: block.charRange,
                    sectionHint: nil,
                    confidence: bbox.width > 0 && bbox.height > 0 ? 0.95 : 0.65
                ))
            }
        }

        if pages.isEmpty {
            throw PDFIndexExtractorError.noTextLayer(pdfURL.path)
        }
        return PDFIndexResult(pages: pages, spans: spans)
    }

    private struct IndexedLine {
        var text: String
        var range: NSRange
    }

    private struct TextBlock {
        var text: String
        var charRange: TextRange
    }

    private func indexedLines(in pageText: String) -> [IndexedLine] {
        let nsText = pageText as NSString
        let rawLines = pageText.components(separatedBy: .newlines)
        var searchStart = 0
        var lines: [IndexedLine] = []

        for rawLine in rawLines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }
            let searchRange = NSRange(location: searchStart, length: max(0, nsText.length - searchStart))
            let foundRange = nsText.range(of: line, options: [], range: searchRange)
            let range = foundRange.location == NSNotFound
                ? NSRange(location: searchStart, length: line.count)
                : foundRange
            if foundRange.location != NSNotFound {
                searchStart = foundRange.location + foundRange.length
            }
            lines.append(IndexedLine(text: line, range: range))
        }

        return lines
    }

    private func mergeLinesIntoBlocks(_ lines: [IndexedLine]) -> [TextBlock] {
        var blocks: [TextBlock] = []
        var current: [IndexedLine] = []

        func flush() {
            guard let first = current.first, let last = current.last else {
                return
            }
            let location = first.range.location
            let length = max(0, last.range.location + last.range.length - location)
            blocks.append(TextBlock(
                text: joinedText(for: current),
                charRange: TextRange(location: location, length: length)
            ))
            current.removeAll()
        }

        for line in lines {
            if let previous = current.last, shouldStartNewBlock(previous: previous.text, next: line.text) {
                flush()
            }
            current.append(line)
            if isStandaloneLine(line.text) {
                flush()
            }
        }
        flush()
        return blocks
    }

    private func shouldStartNewBlock(previous: String, next: String) -> Bool {
        if isStandaloneLine(previous) || isStandaloneLine(next) {
            return true
        }
        if looksLikeSectionHeading(next) {
            return true
        }
        if endsSentence(previous), startsWithUppercaseLetter(next) {
            return true
        }
        return false
    }

    private func joinedText(for lines: [IndexedLine]) -> String {
        var result = ""
        for line in lines {
            if result.isEmpty {
                result = line.text
            } else if result.hasSuffix("-") {
                result.removeLast()
                result += line.text
            } else {
                result += " " + line.text
            }
        }
        return result
    }

    private func isStandaloneLine(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("article http")
            || lower.hasPrefix("received:")
            || lower.hasPrefix("accepted:")
            || lower.hasPrefix("published online:")
            || lower == "check for updates"
            || lower == "references"
            || lower == "acknowledgements"
            || lower == "methods"
            || lower == "data availability"
            || lower == "code availability"
    }

    private func looksLikeSectionHeading(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 80, !trimmed.contains(".") else {
            return false
        }
        let lower = trimmed.lowercased()
        let known = [
            "abstract",
            "introduction",
            "results",
            "discussion",
            "methods",
            "conclusion",
            "data availability",
            "code availability",
            "references"
        ]
        return known.contains(lower)
    }

    private func endsSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else {
            return false
        }
        return ".?!".contains(last)
    }

    private func startsWithUppercaseLetter(_ text: String) -> Bool {
        guard let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return false
        }
        return first.isUppercase
    }

    private func bounds(for page: PDFPage, range: NSRange) -> BoundingBox {
        if let selection = page.selection(for: range) {
            let rect = selection.bounds(for: page)
            if rect.width > 0 && rect.height > 0 {
                return BoundingBox(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
            }
        }

        let fallback = page.bounds(for: .mediaBox)
        return BoundingBox(x: fallback.origin.x, y: fallback.origin.y, width: fallback.width, height: fallback.height)
    }
}
