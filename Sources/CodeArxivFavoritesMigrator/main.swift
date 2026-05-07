import Foundation
import Darwin
import PaperCodexCore

private struct Options {
    var statePath: String?
    var supportRoot: String?
    var dryRun = false
    var maxNewImports: Int?

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--state":
                index += 1
                statePath = try Self.value(after: argument, at: index, in: arguments)
            case "--support-root":
                index += 1
                supportRoot = try Self.value(after: argument, at: index, in: arguments)
            case "--dry-run":
                dryRun = true
            case "--max-new-imports":
                index += 1
                let value = try Self.value(after: argument, at: index, in: arguments)
                guard let parsed = Int(value), parsed >= 0 else {
                    throw MigrationError.invalidArgument("--max-new-imports requires a non-negative integer.")
                }
                maxNewImports = parsed
            case "--help", "-h":
                throw MigrationError.helpRequested
            default:
                throw MigrationError.invalidArgument("Unknown argument: \(argument)")
            }
            index += 1
        }
    }

    private static func value(after flag: String, at index: Int, in arguments: [String]) throws -> String {
        guard index < arguments.count else {
            throw MigrationError.invalidArgument("\(flag) requires a value.")
        }
        return arguments[index]
    }
}

private struct CodeArxivUserState: Decodable {
    var user: CodeArxivUser?
    var favorites: [CodeArxivFavorite]
}

private struct CodeArxivUser: Decodable {
    var username: String
}

private struct CodeArxivFavorite: Decodable {
    var id: Int
    var name: String
    var paperIDs: [String]
    var papers: [RemoteArxivPaper]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case paperIDs = "paper_ids"
        case papers
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        paperIDs = try container.decodeIfPresent([String].self, forKey: .paperIDs) ?? []
        papers = try container.decodeIfPresent([RemoteArxivPaper].self, forKey: .papers) ?? []
    }
}

private struct RemoteArxivPaper: Decodable {
    var id: String
    var arxivID: String
    var arxivIDVersioned: String?
    var title: RemoteLocalizedText
    var authors: [String]
    var categories: [String]
    var primaryCategory: String?
    var tags: [String]
    var published: String?
    var links: RemoteArxivLinks

    var canonicalID: String {
        ArxivIDExtractor.canonicalID(from: arxivIDVersioned ?? arxivID.nilIfEmpty ?? id)
    }

    var publishedYear: Int? {
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
        case authors
        case categories
        case primaryCategory = "primary_category"
        case tags
        case published
        case links
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        arxivID = try container.decodeIfPresent(String.self, forKey: .arxivID) ?? id
        arxivIDVersioned = try container.decodeIfPresent(String.self, forKey: .arxivIDVersioned)
        title = try container.decodeIfPresent(RemoteLocalizedText.self, forKey: .title) ?? RemoteLocalizedText(en: id, zh: "")
        authors = try container.decodeIfPresent([String].self, forKey: .authors) ?? []
        categories = try container.decodeIfPresent([String].self, forKey: .categories) ?? []
        primaryCategory = try container.decodeIfPresent(String.self, forKey: .primaryCategory)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        published = try container.decodeIfPresent(String.self, forKey: .published)
        links = try container.decodeIfPresent(RemoteArxivLinks.self, forKey: .links) ?? RemoteArxivLinks()
    }
}

private struct RemoteLocalizedText: Decodable {
    var en: String
    var zh: String

    func preferredEnglish() -> String {
        en.nilIfEmpty ?? zh.nilIfEmpty ?? ""
    }

    init(en: String, zh: String) {
        self.en = en
        self.zh = zh
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        en = try container.decodeIfPresent(String.self, forKey: .en) ?? ""
        zh = try container.decodeIfPresent(String.self, forKey: .zh) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case en
        case zh
    }
}

private struct RemoteArxivLinks: Decodable {
    var abs: String?
    var pdf: String?

    init(abs: String? = nil, pdf: String? = nil) {
        self.abs = abs
        self.pdf = pdf
    }
}

private struct PaperIndex {
    private(set) var papersByArxivID: [String: Paper] = [:]
    private(set) var papers: [Paper] = []

    init(papers: [Paper]) {
        for paper in papers {
            insert(paper)
        }
    }

    mutating func insert(_ paper: Paper) {
        papers.append(paper)
        let candidates = [
            paper.sourceURL,
            paper.id
        ].compactMap { $0 }
        for candidate in candidates {
            for arxivID in ArxivIDExtractor.extractCanonicalIDs(from: candidate) {
                papersByArxivID[arxivID.lowercased()] = paper
            }
        }
    }

    func paper(for remote: RemoteArxivPaper) -> Paper? {
        let canonicalID = remote.canonicalID.lowercased()
        if let paper = papersByArxivID[canonicalID] {
            return paper
        }
        return papers.first { paper in
            paper.sourceURL?.localizedCaseInsensitiveContains(remote.canonicalID) == true ||
                paper.id.localizedCaseInsensitiveContains(makeSlug(from: remote.canonicalID))
        }
    }
}

private struct MigrationStats {
    var categoriesCreated = 0
    var categoriesUpdated = 0
    var importedPapers = 0
    var reusedPapers = 0
    var categoryAssignmentsCreated = 0
    var tagAssignmentsCreated = 0
    var tagsCreated = 0
}

private enum MigrationError: Error, CustomStringConvertible {
    case helpRequested
    case invalidArgument(String)
    case missingStateFile(URL)
    case missingPDFURL(String)
    case badHTTPStatus(Int, URL)
    case downloadedFileIsNotPDF(String, URL)

    var description: String {
        switch self {
        case .helpRequested:
            Self.helpText
        case let .invalidArgument(message):
            "\(message)\n\n\(Self.helpText)"
        case let .missingStateFile(url):
            "CodeArXiv state file does not exist: \(url.path)"
        case let .missingPDFURL(id):
            "No PDF URL could be resolved for arXiv paper \(id)."
        case let .badHTTPStatus(status, url):
            "HTTP \(status) while downloading \(url.absoluteString)."
        case let .downloadedFileIsNotPDF(id, url):
            "Downloaded content for \(id) from \(url.absoluteString) is not a PDF."
        }
    }

    static let helpText = """
    Usage:
      swift run CodeArxivFavoritesMigrator --state <codearxiv-user-state.json> [--support-root <PaperCodex support root>] [--dry-run] [--max-new-imports N]
    """
}

@main
private struct CodeArxivFavoritesMigrator {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("\(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
        let supportRoot = options.supportRoot
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL }
            ?? PaperCodexPaths.supportRoot()
        let stateURL = options.statePath
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL }
            ?? supportRoot
                .appendingPathComponent("migrations", isDirectory: true)
                .appendingPathComponent("codearxiv-caopu-state.json")

        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            throw MigrationError.missingStateFile(stateURL)
        }

        let decoder = JSONDecoder()
        let state = try decoder.decode(CodeArxivUserState.self, from: Data(contentsOf: stateURL))
        let remoteUniquePaperCount = Set(state.favorites.flatMap { $0.papers.map(\.canonicalID) }).count
        log("CodeArXiv user: \(state.user?.username ?? "unknown")")
        log("Favorites: \(state.favorites.count); favorite-paper links: \(state.favorites.reduce(0) { $0 + $1.papers.count }); unique papers: \(remoteUniquePaperCount)")
        log("Support root: \(supportRoot.path)")

        let repository = try PaperRepository(databasePath: supportRoot.appendingPathComponent("store.sqlite").path)
        try repository.migrate()

        var paperIndex = PaperIndex(papers: try repository.fetchPapers())
        var categoriesByID = Dictionary(uniqueKeysWithValues: try repository.fetchCategories().map { ($0.id, $0) })
        var tagsByNormalizedName = Dictionary(uniqueKeysWithValues: try repository.fetchTags().map { ($0.name.normalizedKey, $0) })
        var stats = MigrationStats()

        if options.dryRun {
            let missing = Set(state.favorites.flatMap { favorite in
                favorite.papers.compactMap { paperIndex.paper(for: $0) == nil ? $0.canonicalID : nil }
            })
            log("Dry run: would create/update \(state.favorites.count) categories and import \(missing.count) missing PDFs.")
            return
        }

        let importer = PaperLibraryImporter(repository: repository, supportRoot: supportRoot)
        let downloadRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperCodexCodeArxivFavoritesMigrator", isDirectory: true)
        if FileManager.default.fileExists(atPath: downloadRoot.path) {
            try FileManager.default.removeItem(at: downloadRoot)
        }
        try FileManager.default.createDirectory(at: downloadRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: downloadRoot)
        }

        var nextSortOrder = ((categoriesByID.values.map(\.sortOrder).max()) ?? 0) + 1
        var newImportsRemaining = options.maxNewImports

        for favorite in state.favorites {
            let categoryID = codeArxivCategoryID(for: favorite)
            let sortOrder: Int
            if let existing = categoriesByID[categoryID] {
                sortOrder = existing.sortOrder
                stats.categoriesUpdated += 1
            } else {
                sortOrder = nextSortOrder
                nextSortOrder += 1
                stats.categoriesCreated += 1
            }
            let category = Category(id: categoryID, parentID: nil, name: favorite.name, sortOrder: sortOrder)
            try repository.upsertCategory(category)
            categoriesByID[categoryID] = category

            for remotePaper in favorite.papers {
                let paper: Paper
                if let existing = paperIndex.paper(for: remotePaper) {
                    paper = existing
                    stats.reusedPapers += 1
                } else {
                    if let remaining = newImportsRemaining {
                        guard remaining > 0 else {
                            continue
                        }
                        newImportsRemaining = remaining - 1
                    }
                    log("Importing \(remotePaper.canonicalID): \(remotePaper.title.preferredEnglish())")
                    let pdfURL = try await downloadPDF(remotePaper, into: downloadRoot)
                    let result = try importer.importPDF(
                        from: pdfURL,
                        metadata: PaperImportMetadata(
                            title: remotePaper.title.preferredEnglish().nilIfEmpty,
                            authors: remotePaper.authors,
                            year: remotePaper.publishedYear,
                            sourceURL: remotePaper.links.abs?.nilIfEmpty ?? "https://arxiv.org/abs/\(remotePaper.canonicalID)"
                        ),
                        isSaved: true,
                        storageSubpath: remotePaper.primaryCategory?.nilIfEmpty ?? remotePaper.categories.first ?? "arxiv"
                    )
                    paper = result.paper
                    paperIndex.insert(result.paper)
                    stats.importedPapers += result.didImport ? 1 : 0
                }

                let existingCategoryIDs = Set(try repository.fetchCategoryIDs(forPaperID: paper.id))
                if !existingCategoryIDs.contains(category.id) {
                    stats.categoryAssignmentsCreated += 1
                }
                try repository.assignPaper(paper.id, toCategory: category.id)

                let existingTagIDs = Set(try repository.fetchTags(forPaperID: paper.id).map(\.id))
                for tagName in remotePaper.tags.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !tagName.isEmpty {
                    let tag = try ensureTag(named: tagName, repository: repository, tagsByNormalizedName: &tagsByNormalizedName, stats: &stats)
                    if !existingTagIDs.contains(tag.id) {
                        stats.tagAssignmentsCreated += 1
                    }
                    try repository.assignPaper(paper.id, toTag: tag.id)
                }
            }
        }

        log("Created categories: \(stats.categoriesCreated)")
        log("Updated categories: \(stats.categoriesUpdated)")
        log("Imported papers: \(stats.importedPapers)")
        log("Reused favorite-paper links: \(stats.reusedPapers)")
        log("New category assignments: \(stats.categoryAssignmentsCreated)")
        log("Created tags: \(stats.tagsCreated)")
        log("New tag assignments: \(stats.tagAssignmentsCreated)")
    }
}

private func ensureTag(
    named name: String,
    repository: PaperRepository,
    tagsByNormalizedName: inout [String: PaperTag],
    stats: inout MigrationStats
) throws -> PaperTag {
    let key = name.normalizedKey
    if let existing = tagsByNormalizedName[key] {
        return existing
    }
    let tag = PaperTag(id: "tag-\(makeSlug(from: name))", name: name)
    try repository.upsertTag(tag)
    tagsByNormalizedName[key] = tag
    stats.tagsCreated += 1
    return tag
}

private func downloadPDF(_ paper: RemoteArxivPaper, into downloadRoot: URL) async throws -> URL {
    let url = try pdfURL(for: paper)
    let session = URLSession(configuration: {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 300
        return configuration
    }())
    var lastError: Error?
    for attempt in 1...3 {
        do {
            var request = URLRequest(url: url)
            request.setValue("PaperCodex CodeArxivFavoritesMigrator", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw MigrationError.badHTTPStatus(http.statusCode, url)
            }
            guard data.starts(with: Data("%PDF-".utf8)) else {
                throw MigrationError.downloadedFileIsNotPDF(paper.canonicalID, url)
            }
            let destination = downloadRoot.appendingPathComponent("\(makeSlug(from: paper.canonicalID)).pdf")
            try data.write(to: destination, options: [.atomic])
            return destination
        } catch {
            lastError = error
            guard attempt < 3 else {
                break
            }
            log("Retrying \(paper.canonicalID) after download error: \(error)")
            try await Task.sleep(for: .seconds(attempt * 5))
        }
    }
    throw lastError ?? MigrationError.missingPDFURL(paper.canonicalID)
}

private func pdfURL(for paper: RemoteArxivPaper) throws -> URL {
    if let rawPDF = paper.links.pdf?.nilIfEmpty,
       let url = URL(string: rawPDF),
       url.scheme != nil {
        return url
    }
    if let abs = paper.links.abs?.nilIfEmpty,
       let url = URL(string: abs.replacingOccurrences(of: "/abs/", with: "/pdf/")),
       url.scheme != nil {
        return url
    }
    guard let url = URL(string: "https://arxiv.org/pdf/\(paper.arxivIDVersioned ?? paper.canonicalID).pdf") else {
        throw MigrationError.missingPDFURL(paper.canonicalID)
    }
    return url
}

private func codeArxivCategoryID(for favorite: CodeArxivFavorite) -> String {
    "codearxiv-favorite-\(favorite.id)-\(makeSlug(from: favorite.name))"
}

private func makeSlug(from text: String) -> String {
    text
        .lowercased()
        .map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        .reduce(into: "") { partial, character in
            if character == "-", partial.last == "-" {
                return
            }
            partial.append(character)
        }
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

private func log(_ message: String) {
    print(message)
    fflush(stdout)
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
