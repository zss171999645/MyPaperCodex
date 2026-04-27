import Foundation

public enum SpanCompactor {
    public static func compact(_ spans: [Span]) -> [Span] {
        let orderedSpans = spans.sorted { left, right in
            if left.paperID != right.paperID {
                return left.paperID < right.paperID
            }
            if left.page != right.page {
                return left.page < right.page
            }
            if left.charRange.location != right.charRange.location {
                return left.charRange.location < right.charRange.location
            }
            return left.id < right.id
        }
        var result: [Span] = []
        var pageSpans: [Span] = []

        func flush() {
            result.append(contentsOf: compactPage(pageSpans))
            pageSpans.removeAll()
        }

        for span in orderedSpans {
            if let previous = pageSpans.last,
               previous.paperID != span.paperID || previous.page != span.page {
                flush()
            }
            pageSpans.append(span)
        }
        flush()
        return result
    }

    private static func compactPage(_ spans: [Span]) -> [Span] {
        var result: [Span] = []
        var current: [Span] = []

        func flush() {
            guard let first = current.first, let last = current.last else {
                return
            }
            let location = first.charRange.location
            let length = max(0, last.charRange.location + last.charRange.length - location)
            result.append(Span(
                id: first.id,
                paperID: first.paperID,
                page: first.page,
                bbox: union(current.map(\.bbox)),
                text: joinedText(for: current),
                charRange: TextRange(location: location, length: length),
                sectionHint: current.compactMap(\.sectionHint).first,
                confidence: current.map(\.confidence).min() ?? first.confidence
            ))
            current.removeAll()
        }

        for span in spans {
            if let previous = current.last, shouldStartNewBlock(previous: previous.text, next: span.text) {
                flush()
            }
            current.append(span)
            if isStandaloneLine(span.text) {
                flush()
            }
        }
        flush()
        return result
    }

    private static func shouldStartNewBlock(previous: String, next: String) -> Bool {
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

    private static func joinedText(for spans: [Span]) -> String {
        var result = ""
        for span in spans {
            if result.isEmpty {
                result = span.text
            } else if result.hasSuffix("-") {
                result.removeLast()
                result += span.text
            } else {
                result += " " + span.text
            }
        }
        return result
    }

    private static func union(_ boxes: [BoundingBox]) -> BoundingBox {
        guard let first = boxes.first else {
            return BoundingBox(x: 0, y: 0, width: 0, height: 0)
        }
        var minX = first.x
        var minY = first.y
        var maxX = first.x + first.width
        var maxY = first.y + first.height
        for box in boxes.dropFirst() {
            minX = min(minX, box.x)
            minY = min(minY, box.y)
            maxX = max(maxX, box.x + box.width)
            maxY = max(maxY, box.y + box.height)
        }
        return BoundingBox(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    private static func isStandaloneLine(_ text: String) -> Bool {
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

    private static func looksLikeSectionHeading(_ text: String) -> Bool {
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

    private static func endsSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else {
            return false
        }
        return ".?!".contains(last)
    }

    private static func startsWithUppercaseLetter(_ text: String) -> Bool {
        guard let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return false
        }
        return first.isUppercase
    }
}
