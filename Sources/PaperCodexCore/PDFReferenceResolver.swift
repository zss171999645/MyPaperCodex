import Foundation

public struct PDFReferenceEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var marker: String?
    public var title: String
    public var text: String
    public var page: Int

    public init(id: String, marker: String?, title: String, text: String, page: Int) {
        self.id = id
        self.marker = marker
        self.title = title
        self.text = text
        self.page = page
    }
}

public struct PDFCitationPreview: Codable, Equatable, Sendable {
    public var citationText: String
    public var references: [PDFReferenceEntry]

    public init(citationText: String, references: [PDFReferenceEntry]) {
        self.citationText = citationText
        self.references = references
    }
}

public struct PDFReferenceResolver: Sendable {
    public var references: [PDFReferenceEntry]

    private let normalizedReferenceLines: [String: PDFReferenceEntry]

    public init(pageTexts: [Int: String]) {
        references = Self.parseReferences(pageTexts: pageTexts)
        normalizedReferenceLines = Self.makeReferenceLineIndex(references)
    }

    public func preview(forLine line: String, page: Int) -> PDFCitationPreview? {
        preview(forLine: line, clickedText: nil, page: page)
    }

    public func preview(forLine line: String, clickedText: String?, page: Int) -> PDFCitationPreview? {
        let cleanedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedLine.isEmpty, referenceEntry(containingLine: cleanedLine, page: page) == nil else {
            return nil
        }
        let requiredHitToken: String?
        if let clickedText {
            let token = Self.normalizedHitToken(clickedText)
            guard !token.isEmpty else {
                return nil
            }
            requiredHitToken = token
        } else {
            requiredHitToken = nil
        }
        if let numeric = numericCitations(in: cleanedLine).first(where: { Self.matchesHit(requiredHitToken, in: $0.hitTokens) }) {
            let entries = numeric.markers.compactMap { marker in
                references.first { $0.marker == marker }
            }
            return PDFCitationPreview(citationText: numeric.text, references: entries)
        }
        if let authorYear = authorYearCitations(in: cleanedLine).first(where: { Self.matchesHit(requiredHitToken, in: $0.hitTokens) }) {
            let entries = references.filter { entry in
                let lowerText = entry.text.lowercased()
                return lowerText.contains(authorYear.surname.lowercased())
                    && lowerText.contains(authorYear.year)
            }
            return PDFCitationPreview(citationText: authorYear.text, references: entries)
        }
        return nil
    }

    public func referenceEntry(containingLine line: String, page: Int) -> PDFReferenceEntry? {
        let normalizedLine = Self.normalized(line)
        guard !normalizedLine.isEmpty else {
            return nil
        }
        if let exact = normalizedReferenceLines[normalizedLine], exact.page == page {
            return exact
        }
        return references.first { entry in
            entry.page == page && Self.normalized(entry.text).contains(normalizedLine)
        }
    }

    private func numericCitations(in line: String) -> [(text: String, markers: [String], hitTokens: Set<String>)] {
        let pattern = #"\[((?:\d+\s*(?:[-,]\s*)?)+)\]"#
        return Self.matches(pattern: pattern, in: line).compactMap { match in
            guard let fullRange = Range(match.range(at: 0), in: line),
                  let bodyRange = Range(match.range(at: 1), in: line) else {
                return nil
            }
            let markerText = String(line[fullRange])
            let markers = expandNumericMarkers(String(line[bodyRange]))
            guard !markers.isEmpty else {
                return nil
            }
            return (markerText, markers, Set(markers.map(Self.normalizedHitToken)))
        }
    }

    private func authorYearCitations(in line: String) -> [(text: String, surname: String, year: String, hitTokens: Set<String>)] {
        let patterns = [
            #"\(([A-Z][A-Za-z'’.-]+)(?:\s+et\s+al\.)?(?:\s+(?:and|&)\s+[A-Z][A-Za-z'’.-]+)?,?\s+(\d{4}[a-z]?)\)"#,
            #"\b([A-Z][A-Za-z'’.-]+)(?:\s+et\s+al\.)?\s*\((\d{4}[a-z]?)\)"#
        ]
        var citations: [(text: String, surname: String, year: String, hitTokens: Set<String>)] = []
        var seen: Set<String> = []
        for pattern in patterns {
            for match in Self.matches(pattern: pattern, in: line) {
                guard let fullRange = Range(match.range(at: 0), in: line),
                      let surnameRange = Range(match.range(at: 1), in: line),
                      let yearRange = Range(match.range(at: 2), in: line) else {
                    continue
                }
                let text = String(line[fullRange])
                guard seen.insert(text).inserted else {
                    continue
                }
                let surname = String(line[surnameRange])
                let year = String(line[yearRange])
                citations.append((
                    text: text,
                    surname: surname,
                    year: year,
                    hitTokens: Set([Self.normalizedHitToken(surname), Self.normalizedHitToken(year)])
                ))
            }
        }
        return citations
    }

    private func expandNumericMarkers(_ markerText: String) -> [String] {
        markerText
            .split(separator: ",")
            .flatMap { part -> [String] in
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                let pieces = trimmed.split(separator: "-").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                guard pieces.count == 2,
                      let start = Int(pieces[0]),
                      let end = Int(pieces[1]),
                      start <= end else {
                    return trimmed.isEmpty ? [] : [trimmed]
                }
                return (start...end).map(String.init)
            }
    }

    private static func parseReferences(pageTexts: [Int: String]) -> [PDFReferenceEntry] {
        var entries: [PDFReferenceEntry] = []
        var isInReferences = false
        var currentMarker: String?
        var currentLines: [String] = []
        var currentPage = 1

        func flush() {
            guard !currentLines.isEmpty else {
                return
            }
            let text = currentLines.joined(separator: " ")
            let entry = PDFReferenceEntry(
                id: "ref-\(entries.count + 1)",
                marker: currentMarker,
                title: title(from: text),
                text: text,
                page: currentPage
            )
            entries.append(entry)
            currentMarker = nil
            currentLines = []
        }

        for page in pageTexts.keys.sorted() {
            let lines = pageTexts[page, default: ""]
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for line in lines {
                if isReferenceHeading(line) {
                    flush()
                    isInReferences = true
                    continue
                }
                guard isInReferences else {
                    continue
                }
                if let start = referenceStart(in: line) {
                    flush()
                    currentMarker = start.marker
                    currentLines = [start.text]
                    currentPage = page
                } else if !currentLines.isEmpty {
                    currentLines.append(line)
                }
            }
        }
        flush()
        return entries
    }

    private static func makeReferenceLineIndex(_ entries: [PDFReferenceEntry]) -> [String: PDFReferenceEntry] {
        var index: [String: PDFReferenceEntry] = [:]
        for entry in entries {
            for line in entry.text.components(separatedBy: .newlines) + [entry.text] {
                let key = normalized(line)
                if !key.isEmpty {
                    index[key] = entry
                }
            }
        }
        return index
    }

    private static func referenceStart(in line: String) -> (marker: String?, text: String)? {
        let bracketPattern = #"^\[(\d+)\]\s*(.+)$"#
        if let match = firstMatch(pattern: bracketPattern, in: line),
           let markerRange = Range(match.range(at: 1), in: line),
           let textRange = Range(match.range(at: 2), in: line) {
            return (String(line[markerRange]), "[\(line[markerRange])] \(line[textRange])")
        }
        let numberedPattern = #"^(\d+)[.)]\s+(.+)$"#
        if let match = firstMatch(pattern: numberedPattern, in: line),
           let markerRange = Range(match.range(at: 1), in: line),
           let textRange = Range(match.range(at: 2), in: line) {
            return (String(line[markerRange]), "\(line[markerRange]). \(line[textRange])")
        }
        let authorYearPattern = #"^[A-Z][A-Za-z'’.-]+,\s+[A-Z](?:\.|[a-z]+).*?\b\d{4}[a-z]?\b.*$"#
        if firstMatch(pattern: authorYearPattern, in: line) != nil {
            return (nil, line)
        }
        return nil
    }

    private static func title(from referenceText: String) -> String {
        let withoutMarker = referenceText
            .replacingOccurrences(of: #"^\s*(?:\[\d+\]|\d+[.)])\s*"#, with: "", options: .regularExpression)
        let parts = withoutMarker
            .components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .")) }
            .filter { !$0.isEmpty }
        if let yearIndex = parts.firstIndex(where: { $0.range(of: #"\b\d{4}[a-z]?\b"#, options: .regularExpression) != nil }),
           yearIndex > 0 {
            if parts[yearIndex].range(of: #"^\(?\d{4}[a-z]?\)?$"#, options: .regularExpression) != nil,
               yearIndex + 1 < parts.count {
                return parts[yearIndex + 1]
            }
            return parts[yearIndex - 1]
        }
        return parts.max(by: { $0.count < $1.count }) ?? withoutMarker
    }

    private static func isReferenceHeading(_ line: String) -> Bool {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "references"
            || normalized == "bibliography"
            || normalized == "works cited"
            || normalized == "参考文献"
    }

    private static func normalized(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func normalizedHitToken(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func matchesHit(_ requiredHitToken: String?, in hitTokens: Set<String>) -> Bool {
        guard let requiredHitToken else {
            return true
        }
        return hitTokens.contains(requiredHitToken)
    }

    private static func matches(pattern: String, in text: String) -> [NSTextCheckingResult] {
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range)
    }

    private static func firstMatch(pattern: String, in text: String) -> NSTextCheckingResult? {
        matches(pattern: pattern, in: text).first
    }
}
