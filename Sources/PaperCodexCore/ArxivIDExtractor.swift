import Foundation

public enum ArxivIDExtractor {
    public static func extractVersionedIDs(from text: String) -> [String] {
        let pattern = #"(?i)(?:arxiv:\s*|arxiv\.org/(?:abs|pdf|html)/)?((?:\d{4}\.\d{4,5})|(?:[a-z-]+(?:\.[a-z-]+)?/\d{7}))(v\d+)?(?:\.pdf)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var seenCanonicalIDs: Set<String> = []
        var ids: [String] = []
        for match in regex.matches(in: text, range: nsRange) {
            guard let idRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            let rawID = String(text[idRange])
            let version = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
            let versionedID = "\(rawID)\(version)"
            let canonicalID = canonicalID(from: versionedID)
            let key = canonicalID.lowercased()
            guard !seenCanonicalIDs.contains(key) else {
                continue
            }
            seenCanonicalIDs.insert(key)
            ids.append(versionedID)
        }
        return ids
    }

    public static func extractCanonicalIDs(from text: String) -> [String] {
        extractVersionedIDs(from: text).map(canonicalID(from:))
    }

    public static func firstCanonicalID(in text: String) -> String? {
        extractCanonicalIDs(from: text).first
    }

    public static func canonicalID(from id: String) -> String {
        id
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"(?i)v\d+$"#, with: "", options: .regularExpression)
    }
}
