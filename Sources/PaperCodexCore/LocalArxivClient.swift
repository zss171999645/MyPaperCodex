import Foundation

public struct LocalArxivListPage: Equatable, Sendable {
    public var date: String
    public var ids: [String]

    public init(date: String, ids: [String]) {
        self.date = date
        self.ids = ids
    }
}

public struct LocalArxivClientConfiguration: Equatable, Sendable {
    public var categories: [String]
    public var listShow: Int
    public var apiPageSize: Int
    public var userAgent: String

    public init(
        categories: [String],
        listShow: Int = 2_000,
        apiPageSize: Int = 500,
        userAgent: String = "PaperCodex/0.1 (+https://arxiv.org)"
    ) {
        self.categories = LocalArxivClientConfiguration.normalized(categories)
        self.listShow = listShow
        self.apiPageSize = min(max(apiPageSize, 1), 2_000)
        self.userAgent = userAgent
    }

    public static let `default` = LocalArxivClientConfiguration(categories: LocalArxivClient.defaultCategories)

    fileprivate static func normalized(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }
}

public enum ArxivAPISort: String, CaseIterable, Codable, Sendable {
    case relevance
    case lastUpdatedDate
    case submittedDate
}

public enum ArxivAPISortOrder: String, CaseIterable, Codable, Sendable {
    case ascending
    case descending
}

public enum LocalArxivClientError: Error, CustomStringConvertible, Equatable {
    case emptyCategories
    case invalidURL(String)
    case badStatus(Int, String)
    case listDateUnavailable(String)
    case listPageMissingDate
    case invalidListDate(String)
    case atomParseFailed(String)
    case missingPDFURL(String)
    case downloadedFileIsNotPDF(String)
    case networkFailure(url: String, reason: String)
    case invalidYearRange(String)

    public var description: String {
        switch self {
        case .emptyCategories:
            "At least one arXiv category is required."
        case let .invalidURL(value):
            "Invalid arXiv URL: \(value)"
        case let .badStatus(status, url):
            "arXiv returned HTTP \(status) for \(url)."
        case let .listDateUnavailable(date):
            "arXiv listing did not include date \(date). Use a cached feed for older dates."
        case .listPageMissingDate:
            "arXiv listing page did not include a date heading."
        case let .invalidListDate(value):
            "Could not parse arXiv listing date: \(value)."
        case let .atomParseFailed(message):
            "Could not parse arXiv Atom feed: \(message)."
        case let .missingPDFURL(arxivID):
            "Paper \(arxivID) does not include a PDF URL."
        case let .downloadedFileIsNotPDF(arxivID):
            "Downloaded arXiv file is not a PDF for \(arxivID)."
        case let .networkFailure(url, reason):
            "arXiv network request failed for \(url). \(reason)"
        case let .invalidYearRange(message):
            "Invalid arXiv search year range: \(message)"
        }
    }
}

public final class LocalArxivClient: Sendable {
    public static let defaultCategories = ["cs.AI", "cs.CL", "cs.CV", "cs.LG"]

    private let configuration: LocalArxivClientConfiguration
    private let session: URLSession

    public init(configuration: LocalArxivClientConfiguration = .default, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func fetchLatestFeed() async throws -> ArxivFeedResponse {
        try await fetchFeed(date: nil)
    }

    public func fetchFeed(date preferredDate: String?) async throws -> ArxivFeedResponse {
        guard !configuration.categories.isEmpty else {
            throw LocalArxivClientError.emptyCategories
        }

        var lists: [(category: String, page: LocalArxivListPage)] = []
        for category in configuration.categories {
            let html = try await fetchText(url: try listURL(category: category))
            for page in try Self.parseListPages(html) {
                lists.append((category, page))
            }
        }

        let availableDates = Set(lists.map(\.page.date))
        let date: String
        if let preferredDate {
            guard availableDates.contains(preferredDate) else {
                throw LocalArxivClientError.listDateUnavailable(preferredDate)
            }
            date = preferredDate
        } else {
            date = availableDates.sorted().last ?? lists[0].page.date
        }

        var ids: [String] = []
        var seenIDs: Set<String> = []
        var listCategoriesByID: [String: [String]] = [:]
        for item in lists where item.page.date == date {
            for id in item.page.ids {
                if !seenIDs.contains(id) {
                    seenIDs.insert(id)
                    ids.append(id)
                }
                var categories = listCategoriesByID[id, default: []]
                if !categories.contains(item.category) {
                    categories.append(item.category)
                }
                listCategoriesByID[id] = categories
            }
        }

        let papers = try await fetchMetadata(ids: ids, listDate: date, listCategoriesByID: listCategoriesByID)
        return ArxivFeedResponse(date: date, count: papers.count, papers: papers)
    }

    public func fetchFeed(range: DiscoverDateRange) async throws -> ArxivFeedResponse {
        guard !configuration.categories.isEmpty else {
            throw LocalArxivClientError.emptyCategories
        }

        let query = try Self.submittedDateSearchQuery(range: range, categories: configuration.categories)
        let rangeLabel = range.cacheLabel
        let pageSize = configuration.apiPageSize
        var start = 0
        var totalResults: Int?
        var papers: [ArxivFeedPaper] = []
        var seenIDs: Set<String> = []

        repeat {
            let xml = try await fetchText(url: try Self.apiSearchURL(
                query: query,
                start: start,
                maxResults: pageSize,
                sortBy: .submittedDate,
                sortOrder: .descending
            ))
            if totalResults == nil {
                totalResults = Self.parseOpenSearchTotalResults(xml)
            }
            let pagePapers = try Self.parseAtomFeed(
                xml,
                listDate: rangeLabel,
                listCategoriesByID: [:]
            )
                .map { paper -> ArxivFeedPaper in
                    var datedPaper = paper
                    datedPaper.listDate = Self.isoDateFromAtomTimestamp(paper.published) ?? rangeLabel
                    return datedPaper
                }

            for paper in pagePapers where !seenIDs.contains(paper.id) {
                seenIDs.insert(paper.id)
                papers.append(paper)
            }

            start += pageSize
            guard let totalResults, start < totalResults, !pagePapers.isEmpty else {
                break
            }
            try await Task.sleep(nanoseconds: arXivAPIRequestDelayNanoseconds)
        } while start < 30_000

        guard !papers.isEmpty else {
            return ArxivFeedResponse(date: rangeLabel, count: 0, papers: [])
        }

        return ArxivFeedResponse(date: rangeLabel, count: papers.count, papers: papers)
    }

    public func search(query: String,
        requiredCategories: [String] = [],
        fromYear: Int? = nil,
        throughYear: Int? = nil,
        start: Int = 0,
        maxResults: Int = 100,
        sortBy: ArxivAPISort = .relevance,
        sortOrder: ArxivAPISortOrder = .descending
    ) async throws -> ArxivFeedResponse {
        let normalizedQuery = try Self.composedUserSearchQuery(
            query,
            requiredCategories: requiredCategories,
            fromYear: fromYear,
            throughYear: throughYear
        )
        guard !normalizedQuery.isEmpty else {
            return ArxivFeedResponse(date: "search", count: 0, papers: [])
        }
        let pageSize = min(max(maxResults, 1), configuration.apiPageSize)
        let xml = try await fetchText(url: try Self.apiSearchURL(
            query: normalizedQuery,
            start: start,
            maxResults: pageSize,
            sortBy: sortBy,
            sortOrder: sortOrder
        ))
        let totalResults = Self.parseOpenSearchTotalResults(xml)
        let papers = try Self.parseAtomFeed(
            xml,
            listDate: "search",
            listCategoriesByID: [:]
        )
            .map { paper -> ArxivFeedPaper in
                var datedPaper = paper
                datedPaper.listDate = Self.isoDateFromAtomTimestamp(paper.published) ?? "search"
                return datedPaper
            }
        return ArxivFeedResponse(date: "search", count: totalResults ?? papers.count, papers: papers)
    }

    public func fetchPapers(ids: [String], listDate: String = "library-import") async throws -> [ArxivFeedPaper] {
        let normalizedIDs = uniqueVersionedIDs(ids)
        return try await fetchMetadata(ids: normalizedIDs, listDate: listDate, listCategoriesByID: [:])
    }

    public func fetchPDF(for paper: ArxivFeedPaper) async throws -> Data {
        guard let value = paper.links.pdf, let url = URL(string: value) else {
            throw LocalArxivClientError.missingPDFURL(paper.id)
        }
        let data = try await fetchData(url: url, accept: "application/pdf")
        guard data.starts(with: Data("%PDF-".utf8)) else {
            throw LocalArxivClientError.downloadedFileIsNotPDF(paper.id)
        }
        return data
    }

    public static func parseListPage(_ html: String) throws -> LocalArxivListPage {
        guard let first = try parseListPages(html).first else {
            throw LocalArxivClientError.listPageMissingDate
        }
        return first
    }

    public static func parseListPages(_ html: String) throws -> [LocalArxivListPage] {
        let headingPattern = #"<h3[^>]*>([^<]+)</h3>"#
        let headingMatches = regexMatches(pattern: headingPattern, in: html)
        guard !headingMatches.isEmpty else {
            throw LocalArxivClientError.listPageMissingDate
        }

        var pages: [LocalArxivListPage] = []
        for (index, headingMatch) in headingMatches.enumerated() {
            let heading = headingMatch.groups[0]
                .components(separatedBy: " (showing")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? headingMatch.groups[0]
            guard let parsedDate = listHeadingDateFormatter.date(from: heading) else {
                throw LocalArxivClientError.invalidListDate(heading)
            }

            let sectionStart = headingMatch.range.upperBound
            let sectionEnd = index + 1 < headingMatches.count ? headingMatches[index + 1].range.lowerBound : html.endIndex
            let section = String(html[sectionStart..<sectionEnd])
            let idMatches = regexMatches(pattern: #"href\s*=\s*["']\s*/abs/([^"']+)["']"#, in: section)
            var ids: [String] = []
            var seen: Set<String> = []
            for match in idMatches {
                let id = normalizeArxivID(match.groups[0])
                guard !id.isEmpty, !seen.contains(id) else {
                    continue
                }
                seen.insert(id)
                ids.append(id)
            }

            pages.append(LocalArxivListPage(date: isoDateFormatter.string(from: parsedDate), ids: ids))
        }

        return pages
    }

    public static func submittedDateSearchQuery(range: DiscoverDateRange, categories: [String]) throws -> String {
        let normalizedCategories = LocalArxivClientConfiguration.normalized(categories)
        guard !normalizedCategories.isEmpty else {
            throw LocalArxivClientError.emptyCategories
        }
        let categoryClause = categorySearchClause(for: normalizedCategories)
        let start = range.start.replacingOccurrences(of: "-", with: "")
        let end = range.end.replacingOccurrences(of: "-", with: "")
        return "\(categoryClause) AND submittedDate:[\(start)0000 TO \(end)2359]"
    }

    public static func apiSearchURL(
        query: String,
        start: Int,
        maxResults: Int,
        sortBy: ArxivAPISort = .relevance,
        sortOrder: ArxivAPISortOrder = .descending
    ) throws -> URL {
        guard var components = URLComponents(string: "https://export.arxiv.org/api/query") else {
            throw LocalArxivClientError.invalidURL("https://export.arxiv.org/api/query")
        }
        components.queryItems = [
            URLQueryItem(name: "search_query", value: query),
            URLQueryItem(name: "start", value: "\(max(start, 0))"),
            URLQueryItem(name: "max_results", value: "\(min(max(maxResults, 1), 2_000))"),
            URLQueryItem(name: "sortBy", value: sortBy.rawValue),
            URLQueryItem(name: "sortOrder", value: sortOrder.rawValue)
        ]
        guard let url = components.url else {
            throw LocalArxivClientError.invalidURL(query)
        }
        return url
    }

    public static func normalizedUserSearchQuery(_ raw: String) -> String {
        let trimmed = normalizeWhitespace(raw)
        guard !trimmed.isEmpty else {
            return ""
        }
        if looksLikeArxivQuerySyntax(trimmed) {
            return trimmed
        }
        return "all:\(trimmed)"
    }

    public static func normalizedSearchCategories(_ values: [String]) -> [String] {
        LocalArxivClientConfiguration.normalized(values)
    }

    public static func normalizedSearchYear(_ raw: String) throws -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard trimmed.count == 4,
              let year = Int(trimmed),
              (1...9999).contains(year) else {
            throw LocalArxivClientError.invalidYearRange("Use a four-digit year.")
        }
        return year
    }

    public static func submittedDateYearRangeSearchQuery(
        fromYear: Int?,
        throughYear: Int?
    ) throws -> String? {
        guard fromYear != nil || throughYear != nil else {
            return nil
        }
        let startYear = fromYear ?? 1991
        let endYear = throughYear ?? 9999
        guard (1...9999).contains(startYear), (1...9999).contains(endYear) else {
            throw LocalArxivClientError.invalidYearRange("Years must be between 0001 and 9999.")
        }
        guard startYear <= endYear else {
            throw LocalArxivClientError.invalidYearRange("The start year must not be later than the end year.")
        }
        return String(
            format: "submittedDate:[%04d01010000 TO %04d12312359]",
            startYear,
            endYear
        )
    }

    public static func composedUserSearchQuery(
        _ raw: String,
        requiredCategories: [String],
        fromYear: Int?,
        throughYear: Int?
    ) throws -> String {
        var clauses: [String] = []
        let normalizedQuery = normalizedUserSearchQuery(raw)
        if !normalizedQuery.isEmpty {
            clauses.append("(\(normalizedQuery))")
        }
        let categories = normalizedSearchCategories(requiredCategories)
        if !categories.isEmpty {
            clauses.append(categorySearchClause(for: categories))
        }
        if let yearClause = try submittedDateYearRangeSearchQuery(fromYear: fromYear, throughYear: throughYear) {
            clauses.append(yearClause)
        }
        return clauses.joined(separator: " AND ")
    }

    private static func categorySearchClause(for categories: [String]) -> String {
        if categories.count == 1 {
            return "cat:\(categories[0])"
        }
        return "(\(categories.map { "cat:\($0)" }.joined(separator: " OR ")))"
    }

    public static func parseAtomFeed(
        _ xml: String,
        listDate: String,
        listCategoriesByID: [String: [String]],
        listDatesByID: [String: String] = [:]
    ) throws -> [ArxivFeedPaper] {
        let parser = LocalArxivAtomParser()
        let entries = try parser.parse(xml)
        return entries.compactMap { entry in
            guard let rawVersionedID = entry.versionedID else {
                return nil
            }
            let versionedID = normalizeVersionedArxivID(rawVersionedID)
            let arxivID = normalizeArxivID(versionedID)
            let categories = uniqueValues(entry.categories)
            let primaryCategory = entry.primaryCategory ?? categories.first
            let listCategories = listCategoriesByID[arxivID] ?? primaryCategory.map { [$0] } ?? categories
            let title = normalizeWhitespace(entry.title)
            let abstract = normalizeWhitespace(entry.summary)
            let comment = normalizeWhitespace(entry.comment)
            let github = firstGitHubURL(in: [comment, abstract])
            return ArxivFeedPaper(
                id: arxivID,
                arxivID: arxivID,
                arxivIDVersioned: versionedID,
                title: ArxivLocalizedText(en: title, zh: ""),
                abstract: ArxivLocalizedText(en: abstract, zh: ""),
                summary: ArxivLocalizedText(en: "", zh: ""),
                authors: entry.authors,
                categories: categories,
                primaryCategory: primaryCategory,
                listCategories: listCategories,
                tags: [],
                comment: comment,
                published: entry.published,
                updated: entry.updated,
                listDate: listDatesByID[arxivID] ?? listDate,
                thumbnailVersion: nil,
                embedding: nil,
                links: ArxivFeedLinks(
                    abs: "https://arxiv.org/abs/\(arxivID)",
                    pdf: "https://arxiv.org/pdf/\(arxivID).pdf",
                    github: github,
                    code: github
                ),
                assets: ArxivFeedAssets(small: nil, large: nil)
            )
        }
    }

    public static func parseOpenSearchTotalResults(_ xml: String) -> Int? {
        guard let match = regexMatches(
            pattern: #"<(?:opensearch:)?totalResults[^>]*>\s*(\d+)\s*</(?:opensearch:)?totalResults>"#,
            in: xml
        ).first,
              let value = match.groups.first else {
            return nil
        }
        return Int(value)
    }

    public static func isoDateFromAtomTimestamp(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        return value.split(separator: "T").first.map(String.init)
    }

    public static func normalizeArxivID(_ raw: String) -> String {
        let value = normalizeVersionedArxivID(raw)
        return value.replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
    }

    private static func normalizeVersionedArxivID(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: "arXiv:", with: "", options: [.caseInsensitive])
        if let url = URL(string: value),
           let last = url.pathComponents.last,
           !last.isEmpty {
            value = last
        }
        if let range = value.range(of: "/abs/") {
            value = String(value[range.upperBound...])
        }
        if let range = value.range(of: "/pdf/") {
            value = String(value[range.upperBound...])
        }
        if value.hasSuffix(".pdf") {
            value.removeLast(4)
        }
        return value
    }

    private func fetchMetadata(
        ids: [String],
        listDate: String,
        listCategoriesByID: [String: [String]],
        listDatesByID: [String: String] = [:]
    ) async throws -> [ArxivFeedPaper] {
        guard !ids.isEmpty else {
            return []
        }
        var papersByID: [String: ArxivFeedPaper] = [:]
        let batches = ids.chunked(size: 50)
        for (index, batch) in batches.enumerated() {
            if index > 0 {
                try await Task.sleep(nanoseconds: arXivAPIRequestDelayNanoseconds)
            }
            let url = try atomURL(ids: batch)
            let xml = try await fetchText(url: url)
            for paper in try Self.parseAtomFeed(
                xml,
                listDate: listDate,
                listCategoriesByID: listCategoriesByID,
                listDatesByID: listDatesByID
            ) {
                papersByID[paper.id] = paper
            }
        }
        return ids.compactMap { papersByID[Self.normalizeArxivID($0)] }
    }

    private func listURL(category: String) throws -> URL {
        guard var components = URLComponents(string: "https://arxiv.org/list/\(category)/pastweek") else {
            throw LocalArxivClientError.invalidURL(category)
        }
        components.queryItems = [URLQueryItem(name: "show", value: "\(configuration.listShow)")]
        guard let url = components.url else {
            throw LocalArxivClientError.invalidURL(category)
        }
        return url
    }

    private func atomURL(ids: [String]) throws -> URL {
        guard var components = URLComponents(string: "https://export.arxiv.org/api/query") else {
            throw LocalArxivClientError.invalidURL("https://export.arxiv.org/api/query")
        }
        components.queryItems = [
            URLQueryItem(name: "id_list", value: ids.joined(separator: ",")),
            URLQueryItem(name: "max_results", value: "\(ids.count)")
        ]
        guard let url = components.url else {
            throw LocalArxivClientError.invalidURL(ids.joined(separator: ","))
        }
        return url
    }

    private func fetchText(url: URL) async throws -> String {
        String(decoding: try await fetchData(url: url, accept: "*/*"), as: UTF8.self)
    }

    private func fetchData(url: URL, accept: String) async throws -> Data {
        var lastError: Error?
        for attempt in 0..<3 {
            var request = URLRequest(url: url)
            request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(accept, forHTTPHeaderField: "Accept")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    if (http.statusCode == 429 || (500..<600).contains(http.statusCode)), attempt < 2 {
                        try await Task.sleep(nanoseconds: retryDelayNanoseconds(for: http, attempt: attempt))
                        continue
                    }
                    throw LocalArxivClientError.badStatus(http.statusCode, url.absoluteString)
                }
                return data
            } catch {
                if Task.isCancelled {
                    throw error
                }
                lastError = error
                if Self.isRetriableNetworkError(error) {
                    if attempt < 2 {
                        try await Task.sleep(nanoseconds: retryDelayNanoseconds(for: nil, attempt: attempt))
                        continue
                    }
                    throw LocalArxivClientError.networkFailure(
                        url: url.absoluteString,
                        reason: Self.networkFailureReason(for: error)
                    )
                }
                throw error
            }
        }
        throw lastError ?? LocalArxivClientError.invalidURL(url.absoluteString)
    }

    private func retryDelayNanoseconds(for response: HTTPURLResponse?, attempt: Int) -> UInt64 {
        if let retryAfter = response?.value(forHTTPHeaderField: "Retry-After"),
           let seconds = UInt64(retryAfter.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return seconds * 1_000_000_000
        }
        return UInt64(attempt + 1) * arXivAPIRequestDelayNanoseconds
    }

    public static func isRetriableNetworkError(_ error: Error) -> Bool {
        guard let urlErrorCode = urlErrorCode(for: error) else {
            return false
        }
        switch urlErrorCode {
        case .timedOut,
             .networkConnectionLost,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    private static func networkFailureReason(for error: Error) -> String {
        switch urlErrorCode(for: error) {
        case .timedOut:
            return "The request timed out."
        case .networkConnectionLost:
            return "The network connection was lost."
        case .cannotConnectToHost:
            return "Could not connect to the arXiv host."
        case .cannotFindHost:
            return "Could not find the arXiv host."
        case .dnsLookupFailed:
            return "DNS lookup failed."
        case .secureConnectionFailed:
            return "TLS connection failed."
        default:
            return (error as NSError).localizedDescription
        }
    }

    private static func urlErrorCode(for error: Error) -> URLError.Code? {
        if let urlError = error as? URLError {
            return urlError.code
        }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return nil
        }
        return URLError.Code(rawValue: nsError.code)
    }
}

private let arXivAPIRequestDelayNanoseconds: UInt64 = 3_000_000_000

private func uniqueVersionedIDs(_ ids: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for id in ids {
        let versionedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !versionedID.isEmpty else {
            continue
        }
        let canonicalID = ArxivIDExtractor.canonicalID(from: versionedID).lowercased()
        guard !seen.contains(canonicalID) else {
            continue
        }
        seen.insert(canonicalID)
        result.append(versionedID)
    }
    return result
}

private func looksLikeArxivQuerySyntax(_ value: String) -> Bool {
    if value.range(of: #"\b(ti|au|abs|co|jr|cat|rn|id|all|submittedDate|lastUpdatedDate):"#, options: [.regularExpression, .caseInsensitive]) != nil {
        return true
    }
    if value.range(of: #"\b(AND|OR|ANDNOT)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
        return true
    }
    return value.contains("[") && value.contains(" TO ") && value.contains("]")
}

private struct RegexMatch {
    var range: Range<String.Index>
    var groups: [String]
}

private func regexMatches(pattern: String, in text: String) -> [RegexMatch] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return []
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, range: range).compactMap { result in
        guard let fullRange = Range(result.range, in: text) else {
            return nil
        }
        var groups: [String] = []
        for index in 1..<result.numberOfRanges {
            let nsRange = result.range(at: index)
            guard let groupRange = Range(nsRange, in: text) else {
                groups.append("")
                continue
            }
            groups.append(String(text[groupRange]))
        }
        return RegexMatch(range: fullRange, groups: groups)
    }
}

private let listHeadingDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy"
    return formatter
}()

private let isoDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

private func normalizeWhitespace(_ text: String) -> String {
    text
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

private func uniqueValues(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !seen.contains(trimmed) else {
            continue
        }
        seen.insert(trimmed)
        result.append(trimmed)
    }
    return result
}

private func firstGitHubURL(in values: [String]) -> String? {
    let pattern = #"https?://(?:www\.)?github\.com/[^\s\])>\]"']+"#
    for value in values {
        guard let match = regexMatches(pattern: pattern, in: value).first else {
            continue
        }
        return match.groups.first ?? String(value[match.range])
    }
    return nil
}

private struct LocalArxivAtomEntry {
    var versionedID: String?
    var title: String = ""
    var summary: String = ""
    var authors: [String] = []
    var comment: String = ""
    var primaryCategory: String?
    var categories: [String] = []
    var published: String?
    var updated: String?
}

private final class LocalArxivAtomParser: NSObject, XMLParserDelegate {
    private var entries: [LocalArxivAtomEntry] = []
    private var currentEntry: LocalArxivAtomEntry?
    private var elementStack: [String] = []
    private var textBuffer = ""

    func parse(_ xml: String) throws -> [LocalArxivAtomEntry] {
        entries = []
        currentEntry = nil
        elementStack = []
        textBuffer = ""
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = self
        guard parser.parse() else {
            throw LocalArxivClientError.atomParseFailed(parser.parserError?.localizedDescription ?? "unknown parser error")
        }
        return entries
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        elementStack.append(name)
        textBuffer = ""

        if name == "entry" {
            currentEntry = LocalArxivAtomEntry()
            return
        }
        guard currentEntry != nil else {
            return
        }
        if name == "primary_category",
           let term = attributeDict["term"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !term.isEmpty {
            currentEntry?.primaryCategory = term
        } else if name == "category",
                  let term = attributeDict["term"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !term.isEmpty {
            currentEntry?.categories.append(term)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        defer {
            if !elementStack.isEmpty {
                elementStack.removeLast()
            }
            textBuffer = ""
        }

        guard var entry = currentEntry else {
            return
        }

        let value = normalizeWhitespace(textBuffer)
        switch name {
        case "entry":
            entries.append(entry)
            currentEntry = nil
        case "id":
            entry.versionedID = value
            currentEntry = entry
        case "updated":
            entry.updated = value
            currentEntry = entry
        case "published":
            entry.published = value
            currentEntry = entry
        case "title":
            entry.title = value
            currentEntry = entry
        case "summary":
            entry.summary = value
            currentEntry = entry
        case "comment":
            entry.comment = value
            currentEntry = entry
        case "name":
            if elementStack.dropLast().last == "author", !value.isEmpty {
                entry.authors.append(value)
                currentEntry = entry
            }
        default:
            break
        }
    }

    private func localName(_ elementName: String) -> String {
        elementName.split(separator: ":").last.map(String.init) ?? elementName
    }
}

private extension Array {
    func chunked(size: Int) -> [[Element]] {
        guard size > 0 else {
            return [self]
        }
        var result: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            let nextIndex = Swift.min(index + size, endIndex)
            result.append(Array(self[index..<nextIndex]))
            index = nextIndex
        }
        return result
    }
}
