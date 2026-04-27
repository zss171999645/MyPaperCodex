import Foundation

public struct SourceCitation: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var marker: String
    public var displayIndex: Int
    public var link: String

    public init(id: String, marker: String, displayIndex: Int, link: String? = nil) {
        self.id = id
        self.marker = marker
        self.displayIndex = displayIndex
        self.link = link ?? CitationParser.linkURL(for: id)
    }
}

public struct ParsedCitationText: Codable, Equatable, Sendable {
    public var displayText: String
    public var displayMarkdown: String
    public var citations: [SourceCitation]
    public var brokenMarkers: [String]

    public init(displayText: String, displayMarkdown: String, citations: [SourceCitation], brokenMarkers: [String]) {
        self.displayText = displayText
        self.displayMarkdown = displayMarkdown
        self.citations = citations
        self.brokenMarkers = brokenMarkers
    }
}

public enum CitationParser {
    public static func parse(_ text: String) -> ParsedCitationText {
        var output = ""
        var markdownOutput = ""
        var citations: [SourceCitation] = []
        var brokenMarkers: [String] = []
        var cursor = text.startIndex

        while let start = text[cursor...].range(of: "[[cite:")?.lowerBound {
            output.append(contentsOf: text[cursor..<start])
            markdownOutput.append(contentsOf: text[cursor..<start])
            guard let end = text[start...].range(of: "]]")?.upperBound else {
                let marker = String(text[start...])
                brokenMarkers.append(marker)
                output.append(marker)
                markdownOutput.append(marker)
                cursor = text.endIndex
                break
            }

            let marker = String(text[start..<end])
            let citationIDStart = text.index(start, offsetBy: 7)
            let citationIDEnd = text.index(end, offsetBy: -2)
            let citationID = String(text[citationIDStart..<citationIDEnd])

            if isValidCitationID(citationID) {
                let displayIndex = citations.count + 1
                let citation = SourceCitation(id: citationID, marker: marker, displayIndex: displayIndex)
                citations.append(citation)
                output.append("[\(displayIndex)]")
                markdownOutput.append("[\(displayIndex)](\(citation.link))")
            } else {
                brokenMarkers.append(marker)
                output.append(marker)
                markdownOutput.append(marker)
            }
            cursor = end
        }

        output.append(contentsOf: text[cursor...])
        markdownOutput.append(contentsOf: text[cursor...])
        return ParsedCitationText(displayText: output, displayMarkdown: markdownOutput, citations: citations, brokenMarkers: brokenMarkers)
    }

    public static func linkURL(for citationID: String) -> String {
        "papercodex-cite://open?id=\(percentEncode(citationID))"
    }

    public static func citationID(from url: URL) -> String? {
        guard url.scheme == "papercodex-cite" else {
            return nil
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first { $0.name == "id" }?.value
    }

    private static func isValidCitationID(_ id: String) -> Bool {
        let parts = id.split(separator: ":").map(String.init)
        guard parts.count == 4 else {
            return false
        }
        guard parts[0] == "paper" else {
            return false
        }
        guard parts[2].first == "p", Int(parts[2].dropFirst()) != nil else {
            return false
        }
        return parts[3].first == "b" || parts[3].first == "a"
    }

    private static func percentEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
