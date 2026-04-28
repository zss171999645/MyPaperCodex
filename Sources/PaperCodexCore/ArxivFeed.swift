import Foundation

public struct ArxivFeedDateIndex: Codable, Equatable, Sendable {
    public var dates: [String]
    public var latest: String?

    public init(dates: [String], latest: String?) {
        self.dates = dates
        self.latest = latest
    }
}

public struct ArxivFeedResponse: Codable, Equatable, Sendable {
    public var date: String
    public var count: Int
    public var papers: [ArxivFeedPaper]
    public var groups: [ArxivFeedGroup]?
    public var filters: CodeArxivUserFilters?
    public var favorites: [CodeArxivFavorite]?
    public var tagOptions: [String]?
    public var user: CodeArxivUser?

    public init(
        date: String,
        count: Int,
        papers: [ArxivFeedPaper],
        groups: [ArxivFeedGroup]? = nil,
        filters: CodeArxivUserFilters? = nil,
        favorites: [CodeArxivFavorite]? = nil,
        tagOptions: [String]? = nil,
        user: CodeArxivUser? = nil
    ) {
        self.date = date
        self.count = count
        self.papers = papers
        self.groups = groups
        self.filters = filters
        self.favorites = favorites
        self.tagOptions = tagOptions
        self.user = user
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case count
        case papers
        case groups
        case filters
        case favorites
        case tagOptions = "tag_options"
        case user
    }
}

public struct ArxivFeedGroup: Codable, Equatable, Sendable {
    public var key: String
    public var count: Int

    public init(key: String, count: Int) {
        self.key = key
        self.count = count
    }
}

public struct CodeArxivUser: Codable, Equatable, Sendable {
    public var id: Int
    public var username: String
    public var languagePreference: String

    public init(id: Int, username: String, languagePreference: String) {
        self.id = id
        self.username = username
        self.languagePreference = languagePreference
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case languagePreference = "language_preference"
    }
}

public struct CodeArxivTagFilters: Codable, Equatable, Sendable {
    public var whitelist: [String]
    public var blacklist: [String]

    public init(whitelist: [String], blacklist: [String]) {
        self.whitelist = whitelist
        self.blacklist = blacklist
    }
}

public struct CodeArxivUserFilters: Codable, Equatable, Sendable {
    public var categories: [String]
    public var tags: CodeArxivTagFilters
    public var simFavorites: [Int]
    public var lastDate: String?
    public var lastPaperID: String?
    public var lastPosition: Int

    public init(
        categories: [String],
        tags: CodeArxivTagFilters,
        simFavorites: [Int],
        lastDate: String?,
        lastPaperID: String?,
        lastPosition: Int
    ) {
        self.categories = categories
        self.tags = tags
        self.simFavorites = simFavorites
        self.lastDate = lastDate
        self.lastPaperID = lastPaperID
        self.lastPosition = lastPosition
    }

    private enum CodingKeys: String, CodingKey {
        case categories
        case tags
        case simFavorites = "sim_favorites"
        case lastDate = "last_date"
        case lastPaperID = "last_paper_id"
        case lastPosition = "last_position"
    }
}

public struct CodeArxivFavorite: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var paperIDs: [String]
    public var papers: [ArxivFeedPaper]
    public var embedding: [Double]?

    public init(id: Int, name: String, paperIDs: [String], papers: [ArxivFeedPaper], embedding: [Double]?) {
        self.id = id
        self.name = name
        self.paperIDs = paperIDs
        self.papers = papers
        self.embedding = embedding
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case paperIDs = "paper_ids"
        case papers
        case embedding
    }
}

public struct CodeArxivUserState: Codable, Equatable, Sendable {
    public var user: CodeArxivUser
    public var filters: CodeArxivUserFilters
    public var favorites: [CodeArxivFavorite]
    public var tagOptions: [String]

    public init(
        user: CodeArxivUser,
        filters: CodeArxivUserFilters,
        favorites: [CodeArxivFavorite],
        tagOptions: [String]
    ) {
        self.user = user
        self.filters = filters
        self.favorites = favorites
        self.tagOptions = tagOptions
    }

    private enum CodingKeys: String, CodingKey {
        case user
        case filters
        case favorites
        case tagOptions = "tag_options"
    }
}

private struct CodeArxivFilterUpdatePayload: Encodable {
    var categories: [String]
    var tags: CodeArxivTagFilters
    var simFavorites: [Int]
    var languagePreference: String?

    private enum CodingKeys: String, CodingKey {
        case categories
        case tags
        case simFavorites = "sim_favorites"
        case languagePreference = "language_preference"
    }
}

public struct ArxivLocalizedText: Codable, Equatable, Sendable {
    public var en: String
    public var zh: String

    public init(en: String, zh: String) {
        self.en = en
        self.zh = zh
    }

    public func preferred(language: String) -> String {
        if language.lowercased().hasPrefix("zh"), !zh.isEmpty {
            return zh
        }
        if !en.isEmpty {
            return en
        }
        return zh
    }
}

public struct ArxivFeedLinks: Codable, Equatable, Sendable {
    public var abs: String?
    public var pdf: String?

    public init(abs: String?, pdf: String?) {
        self.abs = abs
        self.pdf = pdf
    }
}

public struct ArxivFeedAsset: Codable, Equatable, Sendable {
    public var path: String
    public var url: String

    public init(path: String, url: String) {
        self.path = path
        self.url = url
    }
}

public struct ArxivFeedAssets: Codable, Equatable, Sendable {
    public var small: ArxivFeedAsset?
    public var large: ArxivFeedAsset?

    public init(small: ArxivFeedAsset?, large: ArxivFeedAsset?) {
        self.small = small
        self.large = large
    }
}

public struct ArxivFeedPaper: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var arxivID: String
    public var arxivIDVersioned: String?
    public var title: ArxivLocalizedText
    public var abstract: ArxivLocalizedText
    public var summary: ArxivLocalizedText
    public var authors: [String]
    public var categories: [String]
    public var primaryCategory: String?
    public var listCategories: [String]
    public var tags: [String]
    public var comment: String
    public var published: String?
    public var updated: String?
    public var listDate: String?
    public var thumbnailVersion: Int?
    public var embedding: [Double]?
    public var similarity: Double?
    public var filterGroup: String?
    public var isFavorite: Bool?
    public var links: ArxivFeedLinks
    public var assets: ArxivFeedAssets

    public init(
        id: String,
        arxivID: String,
        arxivIDVersioned: String?,
        title: ArxivLocalizedText,
        abstract: ArxivLocalizedText,
        summary: ArxivLocalizedText,
        authors: [String],
        categories: [String],
        primaryCategory: String?,
        listCategories: [String],
        tags: [String],
        comment: String,
        published: String?,
        updated: String?,
        listDate: String?,
        thumbnailVersion: Int?,
        embedding: [Double]?,
        similarity: Double? = nil,
        filterGroup: String? = nil,
        isFavorite: Bool? = nil,
        links: ArxivFeedLinks,
        assets: ArxivFeedAssets
    ) {
        self.id = id
        self.arxivID = arxivID
        self.arxivIDVersioned = arxivIDVersioned
        self.title = title
        self.abstract = abstract
        self.summary = summary
        self.authors = authors
        self.categories = categories
        self.primaryCategory = primaryCategory
        self.listCategories = listCategories
        self.tags = tags
        self.comment = comment
        self.published = published
        self.updated = updated
        self.listDate = listDate
        self.thumbnailVersion = thumbnailVersion
        self.embedding = embedding
        self.similarity = similarity
        self.filterGroup = filterGroup
        self.isFavorite = isFavorite
        self.links = links
        self.assets = assets
    }

    public func displayTitle(language: String) -> String {
        title.preferred(language: language)
    }

    public func displaySummary(language: String) -> String {
        summary.preferred(language: language)
    }

    public var publishedYear: Int? {
        guard let published, published.count >= 4 else {
            return nil
        }
        return Int(published.prefix(4))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case arxivID = "arxiv_id"
        case arxivIDVersioned = "arxiv_id_versioned"
        case title
        case abstract
        case summary
        case authors
        case categories
        case primaryCategory = "primary_category"
        case listCategories = "list_categories"
        case tags
        case comment
        case published
        case updated
        case listDate = "list_date"
        case thumbnailVersion = "thumbnail_version"
        case embedding
        case similarity
        case filterGroup = "filter_group"
        case isFavorite = "is_favorite"
        case links
        case assets
    }
}

public struct PaperImportMetadata: Equatable, Sendable {
    public var title: String?
    public var authors: [String]
    public var year: Int?
    public var sourceURL: String?

    public init(title: String?, authors: [String], year: Int?, sourceURL: String?) {
        self.title = title
        self.authors = authors
        self.year = year
        self.sourceURL = sourceURL
    }
}

public enum ArxivFeedCacheError: Error, CustomStringConvertible, Equatable {
    case unsafePath(String)

    public var description: String {
        switch self {
        case let .unsafePath(path):
            "Unsafe arXiv feed cache path: \(path)"
        }
    }
}

public final class ArxivFeedCache {
    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    public init(root: URL, fileManager: FileManager = .default) {
        self.root = root.standardizedFileURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    public func saveDates(_ dates: ArxivFeedDateIndex) throws {
        try writeJSON(dates, to: root.appendingPathComponent("dates.json"))
    }

    public func loadDates() throws -> ArxivFeedDateIndex? {
        let url = root.appendingPathComponent("dates.json")
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try decoder.decode(ArxivFeedDateIndex.self, from: Data(contentsOf: url))
    }

    public func saveFeed(_ feed: ArxivFeedResponse) throws {
        try writeJSON(feed, to: feedURL(date: feed.date))
    }

    public func loadFeed(date: String) throws -> ArxivFeedResponse? {
        let url = feedURL(date: date)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try decoder.decode(ArxivFeedResponse.self, from: Data(contentsOf: url))
    }

    @discardableResult
    public func saveAsset(_ data: Data, path: String) throws -> URL {
        let url = try assetURL(path: path)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
        return url
    }

    public func cachedAssetURL(path: String) throws -> URL? {
        let url = try assetURL(path: path)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    public func feedURL(date: String) -> URL {
        root
            .appendingPathComponent("feeds", isDirectory: true)
            .appendingPathComponent("\(date).json")
    }

    public func assetURL(path: String) throws -> URL {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ArxivFeedCacheError.unsafePath(path)
        }
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty,
              !components.contains(".."),
              !path.hasPrefix("/") else {
            throw ArxivFeedCacheError.unsafePath(path)
        }
        return components.reduce(root) { partial, component in
            partial.appendingPathComponent(component)
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }
}

public enum ArxivFeedClientError: Error, CustomStringConvertible, Equatable {
    case missingToken
    case invalidURL(String)
    case badStatus(Int)
    case missingPDFURL(String)

    public var description: String {
        switch self {
        case .missingToken:
            "Missing CodeArXiv API token."
        case let .invalidURL(value):
            "Invalid CodeArXiv URL: \(value)"
        case let .badStatus(status):
            "CodeArXiv API returned HTTP \(status)."
        case let .missingPDFURL(arxivID):
            "Paper \(arxivID) does not include a PDF URL."
        }
    }
}

public final class ArxivFeedClient: Sendable {
    private let baseURL: URL
    private let token: String
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(baseURL: URL, token: String, session: URLSession = .shared) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ArxivFeedClientError.missingToken
        }
        self.baseURL = baseURL
        self.token = trimmed
        self.session = session
    }

    public func fetchDates() async throws -> ArxivFeedDateIndex {
        try await decode(ArxivFeedDateIndex.self, path: "api/v1/dates")
    }

    public func fetchFeed(date: String, username: String? = nil) async throws -> ArxivFeedResponse {
        var queryItems: [URLQueryItem] = []
        if let username,
           !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "username", value: username))
        }
        return try await decode(ArxivFeedResponse.self, path: "api/v1/feed/\(date)", queryItems: queryItems)
    }

    public func fetchPaper(id: String) async throws -> ArxivFeedPaperEnvelope {
        try await decode(ArxivFeedPaperEnvelope.self, path: "api/v1/papers/\(id)")
    }

    public func fetchUserState(username: String, includePapers: Bool = false) async throws -> CodeArxivUserState {
        let queryItems = includePapers ? [URLQueryItem(name: "include_papers", value: "1")] : []
        return try await decode(CodeArxivUserState.self, path: "api/v1/users/\(username)/state", queryItems: queryItems)
    }

    public func updateUserFilters(
        username: String,
        categories: [String],
        whitelistTags: [String],
        blacklistTags: [String],
        simFavoriteIDs: [Int],
        languagePreference: String? = nil
    ) async throws -> CodeArxivUserState {
        let payload = CodeArxivFilterUpdatePayload(
            categories: categories,
            tags: CodeArxivTagFilters(whitelist: whitelistTags, blacklist: blacklistTags),
            simFavorites: simFavoriteIDs,
            languagePreference: languagePreference
        )
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/users/\(username)/filters"))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(payload)
        applyAuth(to: &request)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try decoder.decode(CodeArxivUserState.self, from: data)
    }

    public func fetchAsset(_ asset: ArxivFeedAsset) async throws -> Data {
        let requestURL = try resolveURL(asset.url)
        var request = URLRequest(url: requestURL)
        applyAuth(to: &request)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return data
    }

    public func fetchPDF(for paper: ArxivFeedPaper) async throws -> Data {
        guard let pdf = paper.links.pdf, let url = URL(string: pdf) else {
            throw ArxivFeedClientError.missingPDFURL(paper.id)
        }
        let (data, response) = try await session.data(from: url)
        try validate(response: response)
        return data
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        var url = baseURL.appendingPathComponent(path)
        if !queryItems.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw ArxivFeedClientError.invalidURL(url.absoluteString)
            }
            components.queryItems = queryItems
            guard let queryURL = components.url else {
                throw ArxivFeedClientError.invalidURL(url.absoluteString)
            }
            url = queryURL
        }
        var request = URLRequest(url: url)
        applyAuth(to: &request)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try decoder.decode(type, from: data)
    }

    private func resolveURL(_ value: String) throws -> URL {
        if let absolute = URL(string: value), absolute.scheme != nil {
            return absolute
        }
        guard let relative = URL(string: value, relativeTo: baseURL)?.absoluteURL else {
            throw ArxivFeedClientError.invalidURL(value)
        }
        return relative
    }

    private func applyAuth(to request: inout URLRequest) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ArxivFeedClientError.badStatus(http.statusCode)
        }
    }
}

public struct ArxivFeedPaperEnvelope: Codable, Equatable, Sendable {
    public var date: String
    public var paper: ArxivFeedPaper

    public init(date: String, paper: ArxivFeedPaper) {
        self.date = date
        self.paper = paper
    }
}
