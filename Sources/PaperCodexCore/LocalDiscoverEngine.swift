import CryptoKit
import Foundation

public enum LocalDiscoverEngineError: Error, CustomStringConvertible, Equatable {
    case invalidDate(String)
    case invertedDateRange(start: String, end: String)
    case unsafeCacheKey(String)

    public var description: String {
        switch self {
        case let .invalidDate(value):
            "Invalid discover date: \(value). Expected yyyy-MM-dd."
        case let .invertedDateRange(start, end):
            "Discover date range start \(start) is after end \(end)."
        case let .unsafeCacheKey(value):
            "Unsafe discover cache key: \(value)"
        }
    }
}

public struct DiscoverDateRange: Codable, Equatable, Sendable {
    public var start: String
    public var end: String

    public init(start: String, end: String) throws {
        guard let startDate = Self.dateFormatter.date(from: start) else {
            throw LocalDiscoverEngineError.invalidDate(start)
        }
        guard let endDate = Self.dateFormatter.date(from: end) else {
            throw LocalDiscoverEngineError.invalidDate(end)
        }
        guard startDate <= endDate else {
            throw LocalDiscoverEngineError.invertedDateRange(start: start, end: end)
        }
        self.start = start
        self.end = end
    }

    public var dates: [String] {
        guard let startDate = Self.dateFormatter.date(from: start),
              let endDate = Self.dateFormatter.date(from: end) else {
            return []
        }
        var result: [String] = []
        var cursor = startDate
        while cursor <= endDate {
            result.append(Self.dateFormatter.string(from: cursor))
            guard let next = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return result
    }

    public func contains(_ date: String) -> Bool {
        dates.contains(date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

public struct DiscoverQuery: Codable, Equatable, Sendable {
    public var keyword: String
    public var dateRange: DiscoverDateRange
    public var categories: [String]
    public var similaritySourceIDs: [String]
    public var rankingVersion: String

    public init(
        keyword: String,
        dateRange: DiscoverDateRange,
        categories: [String],
        similaritySourceIDs: [String],
        rankingVersion: String
    ) {
        self.keyword = keyword
        self.dateRange = dateRange
        self.categories = categories
        self.similaritySourceIDs = similaritySourceIDs
        self.rankingVersion = rankingVersion
    }

    public var normalized: DiscoverQuery {
        DiscoverQuery(
            keyword: normalizeKeyword(keyword),
            dateRange: dateRange,
            categories: normalizedSorted(categories),
            similaritySourceIDs: normalizedSorted(similaritySourceIDs),
            rankingVersion: rankingVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    public var cacheKey: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(normalized)) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct DiscoverQueryResult: Codable, Equatable, Sendable {
    public var query: DiscoverQuery
    public var arxivIDs: [String]
    public var generatedAt: Date

    public init(query: DiscoverQuery, arxivIDs: [String], generatedAt: Date) {
        self.query = query
        self.arxivIDs = arxivIDs
        self.generatedAt = generatedAt
    }
}

public struct DiscoverPaperEnrichment: Codable, Equatable, Sendable {
    public static let currentProcessorVersion = "local-discover-enrichment-v1"
    public static let currentPromptVersion = "discover-metadata-zh-v1"

    public var arxivID: String
    public var processorVersion: String
    public var promptVersion: String
    public var modelIdentity: String
    public var titleZH: String
    public var summaryZH: String
    public var contribution: String
    public var tags: [String]
    public var links: [String: String]
    public var generatedAt: Date
    public var error: String?

    public init(
        arxivID: String,
        processorVersion: String,
        promptVersion: String,
        modelIdentity: String,
        titleZH: String,
        summaryZH: String,
        contribution: String,
        tags: [String],
        links: [String: String],
        generatedAt: Date,
        error: String?
    ) {
        self.arxivID = arxivID
        self.processorVersion = processorVersion
        self.promptVersion = promptVersion
        self.modelIdentity = modelIdentity
        self.titleZH = titleZH
        self.summaryZH = summaryZH
        self.contribution = contribution
        self.tags = tags
        self.links = links
        self.generatedAt = generatedAt
        self.error = error
    }

    public var isCurrent: Bool {
        processorVersion == Self.currentProcessorVersion && promptVersion == Self.currentPromptVersion
    }
}

public final class LocalDiscoverCache {
    private let root: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL, fileManager: FileManager = .default) {
        self.root = root.standardizedFileURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func saveQueryResult(_ result: DiscoverQueryResult) throws {
        try writeJSON(result, to: queryResultURL(cacheKey: result.query.cacheKey))
    }

    public func loadQueryResult(cacheKey: String) throws -> DiscoverQueryResult? {
        let url = try queryResultURL(cacheKey: cacheKey)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try decoder.decode(DiscoverQueryResult.self, from: Data(contentsOf: url))
    }

    public func saveEnrichment(_ enrichment: DiscoverPaperEnrichment) throws {
        try writeJSON(enrichment, to: enrichmentURL(arxivID: enrichment.arxivID))
    }

    public func loadEnrichment(arxivID: String) throws -> DiscoverPaperEnrichment? {
        let url = enrichmentURL(arxivID: arxivID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try decoder.decode(DiscoverPaperEnrichment.self, from: Data(contentsOf: url))
    }

    private func queryResultURL(cacheKey: String) throws -> URL {
        guard cacheKey.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
            throw LocalDiscoverEngineError.unsafeCacheKey(cacheKey)
        }
        return root
            .appendingPathComponent("queries", isDirectory: true)
            .appendingPathComponent("\(cacheKey).json")
    }

    private func enrichmentURL(arxivID: String) -> URL {
        root
            .appendingPathComponent("enrichments", isDirectory: true)
            .appendingPathComponent("\(safeFilename(arxivID)).json")
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }
}

private func normalizeKeyword(_ value: String) -> String {
    value
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .lowercased()
}

private func normalizedSorted(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            continue
        }
        let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !seen.contains(key) else {
            continue
        }
        seen.insert(key)
        result.append(trimmed)
    }
    return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
}

private func safeFilename(_ value: String) -> String {
    let mapped = value.map { character in
        character.isLetter || character.isNumber || character == "." || character == "-" ? character : "-"
    }
    let filename = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return filename.isEmpty ? "item" : filename
}
