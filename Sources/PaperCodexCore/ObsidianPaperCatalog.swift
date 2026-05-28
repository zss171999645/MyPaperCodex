import CryptoKit
import Foundation

public struct ObsidianPaperRecord: Equatable, Sendable {
    public var noteURL: URL
    public var relativeNotePath: String
    public var paper: Paper
    public var pdfURL: URL?
    public var thumbnailURL: URL?
    public var thumbnailPath: String?
    public var arxiv: String?
    public var shortTitle: String?
    public var aliases: [String]
    public var firstAuthor: String?
    public var venue: String?
    public var discussionStatus: String?
    public var primaryDirection: String?
    public var directions: [String]
    public var primaryTask: String?
    public var tasks: [String]
    public var keywords: [String]
    public var methods: [String]
    public var datasets: [String]
    public var metrics: [String]
    public var relatedPapers: [String]
    public var relationTypes: [String]
    public var worldModelRole: String?
    public var summary: String?
    public var openQuestions: [String]
    public var projectURL: URL?
    public var codeURL: URL?
    public var doi: String?

    public init(
        noteURL: URL,
        relativeNotePath: String,
        paper: Paper,
        pdfURL: URL?,
        thumbnailURL: URL?,
        thumbnailPath: String?,
        arxiv: String?,
        shortTitle: String?,
        aliases: [String],
        firstAuthor: String?,
        venue: String?,
        discussionStatus: String?,
        primaryDirection: String?,
        directions: [String],
        primaryTask: String?,
        tasks: [String],
        keywords: [String],
        methods: [String],
        datasets: [String],
        metrics: [String],
        relatedPapers: [String],
        relationTypes: [String],
        worldModelRole: String?,
        summary: String?,
        openQuestions: [String],
        projectURL: URL?,
        codeURL: URL?,
        doi: String?
    ) {
        self.noteURL = noteURL
        self.relativeNotePath = relativeNotePath
        self.paper = paper
        self.pdfURL = pdfURL
        self.thumbnailURL = thumbnailURL
        self.thumbnailPath = thumbnailPath
        self.arxiv = arxiv
        self.shortTitle = shortTitle
        self.aliases = aliases
        self.firstAuthor = firstAuthor
        self.venue = venue
        self.discussionStatus = discussionStatus
        self.primaryDirection = primaryDirection
        self.directions = directions
        self.primaryTask = primaryTask
        self.tasks = tasks
        self.keywords = keywords
        self.methods = methods
        self.datasets = datasets
        self.metrics = metrics
        self.relatedPapers = relatedPapers
        self.relationTypes = relationTypes
        self.worldModelRole = worldModelRole
        self.summary = summary
        self.openQuestions = openQuestions
        self.projectURL = projectURL
        self.codeURL = codeURL
        self.doi = doi
    }
}

public enum ObsidianDiscussionStatus: String, CaseIterable, Sendable {
    case reference = "参考论文"
    case queued = "待讨论"
    case discussing = "讨论中"
    case read = "已读"
    case firstPassComplete = "初读完成"
    case converged = "已收敛"
    case revisit = "待回访"
}

public enum ObsidianPaperCatalogError: Error, Equatable {
    case invalidDiscussionStatus(String)
    case missingFrontmatter(URL)
}

public struct ObsidianPaperCatalog: Sendable {
    public init() {}

    public func load(
        vaultRoot: URL,
        supportRoot: URL,
        fileManager: FileManager = .default
    ) throws -> [ObsidianPaperRecord] {
        let papersRoot = vaultRoot
            .appendingPathComponent("03-literature", isDirectory: true)
            .appendingPathComponent("papers", isDirectory: true)
            .standardizedFileURL
        guard let enumerator = fileManager.enumerator(
            at: papersRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var records: [ObsidianPaperRecord] = []
        for case let noteURL as URL in enumerator {
            guard noteURL.pathExtension.lowercased() == "md" else {
                continue
            }
            let values = try? noteURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else {
                continue
            }
            let text = try String(contentsOf: noteURL, encoding: .utf8)
            guard let properties = Self.frontmatterProperties(in: text),
                  properties.string("type") == "literature-note" else {
                continue
            }
            records.append(record(
                noteURL: noteURL.standardizedFileURL,
                relativeNotePath: Self.relativePath(noteURL: noteURL, vaultRoot: vaultRoot),
                properties: properties,
                supportRoot: supportRoot,
                vaultRoot: vaultRoot
            ))
        }
        return records.sorted {
            if $0.paper.year != $1.paper.year {
                return ($0.paper.year ?? 0) < ($1.paper.year ?? 0)
            }
            return $0.paper.title.localizedStandardCompare($1.paper.title) == .orderedAscending
        }
    }

    public func updateDiscussionStatus(noteURL: URL, status: String) throws {
        guard ObsidianDiscussionStatus.allCases.contains(where: { $0.rawValue == status }) else {
            throw ObsidianPaperCatalogError.invalidDiscussionStatus(status)
        }

        let text = try String(contentsOf: noteURL, encoding: .utf8)
        var lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let closingIndex = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---" }) else {
            throw ObsidianPaperCatalogError.missingFrontmatter(noteURL)
        }

        let frontmatterRange = 1..<closingIndex
        if let existingIndex = lines[frontmatterRange].firstIndex(where: { Self.frontmatterKey(in: $0) == "discussion_status" }) {
            lines[existingIndex] = "discussion_status: \(status)"
        } else if let statusIndex = lines[frontmatterRange].firstIndex(where: { Self.frontmatterKey(in: $0) == "status" }) {
            lines.insert("discussion_status: \(status)", at: lines.index(after: statusIndex))
        } else {
            lines.insert("discussion_status: \(status)", at: closingIndex)
        }

        try lines.joined(separator: "\n").write(to: noteURL, atomically: true, encoding: .utf8)
    }

    private func record(
        noteURL: URL,
        relativeNotePath: String,
        properties: ObsidianFrontmatterProperties,
        supportRoot: URL,
        vaultRoot: URL
    ) -> ObsidianPaperRecord {
        let arxiv = properties.string("arxiv")
        let shortTitle = properties.string("short_title")
        let title = properties.string("paper_title")
            ?? shortTitle
            ?? noteURL.deletingPathExtension().lastPathComponent
        let id = Self.paperID(arxiv: arxiv, title: title, relativeNotePath: relativeNotePath)
        let pdfURL = properties.url("pdf_url")
        let thumbnailPath = properties.rawString("paper_thumbnail") ?? properties.rawString("thumbnail")
        let thumbnailURL = thumbnailPath.flatMap { Self.vaultAssetURL(path: $0, vaultRoot: vaultRoot) }
        let cachedPDFURL = supportRoot
            .appendingPathComponent("obsidian-pdf-cache", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("original.pdf")
            .standardizedFileURL
        let now = Date()
        let paper = Paper(
            id: id,
            filePath: cachedPDFURL.path,
            fileHash: "obsidian-note:\(relativeNotePath)",
            title: title,
            authors: properties.array("authors"),
            year: properties.int("year"),
            sourceURL: properties.string("arxiv_url") ?? properties.string("pdf_url"),
            isSaved: true,
            importedAt: now,
            updatedAt: now
        )
        return ObsidianPaperRecord(
            noteURL: noteURL,
            relativeNotePath: relativeNotePath,
            paper: paper,
            pdfURL: pdfURL,
            thumbnailURL: thumbnailURL,
            thumbnailPath: thumbnailPath,
            arxiv: arxiv,
            shortTitle: shortTitle,
            aliases: properties.array("aliases"),
            firstAuthor: properties.string("first_author"),
            venue: properties.string("venue"),
            discussionStatus: properties.string("discussion_status"),
            primaryDirection: properties.string("primary_direction"),
            directions: properties.array("directions"),
            primaryTask: properties.string("primary_task"),
            tasks: properties.array("tasks"),
            keywords: properties.array("keywords"),
            methods: properties.array("methods"),
            datasets: properties.array("datasets"),
            metrics: properties.array("metrics"),
            relatedPapers: properties.array("related_papers"),
            relationTypes: properties.array("relation_types"),
            worldModelRole: properties.string("world_model_role"),
            summary: properties.string("summary"),
            openQuestions: properties.array("open_questions"),
            projectURL: properties.url("project_url"),
            codeURL: properties.url("code_url"),
            doi: properties.string("doi")
        )
    }

    private static func paperID(arxiv: String?, title: String, relativeNotePath: String) -> String {
        if let arxiv = arxiv?.trimmingCharacters(in: .whitespacesAndNewlines), !arxiv.isEmpty {
            return "obsidian-arxiv-\(slug(arxiv))"
        }
        let digest = SHA256.hash(data: Data(relativeNotePath.utf8))
            .prefix(5)
            .map { String(format: "%02x", $0) }
            .joined()
        let titleSlug = slug(title)
        return "obsidian-\(titleSlug.isEmpty ? "paper" : titleSlug)-\(digest)"
    }

    private static func slug(_ text: String) -> String {
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

    private static func relativePath(noteURL: URL, vaultRoot: URL) -> String {
        let notePath = noteURL.standardizedFileURL.path
        let vaultPath = vaultRoot.standardizedFileURL.path
        guard notePath.hasPrefix(vaultPath + "/") else {
            return noteURL.lastPathComponent
        }
        return String(notePath.dropFirst(vaultPath.count + 1))
    }

    private static func frontmatterKey(in line: String) -> String? {
        guard !line.hasPrefix(" "), let separator = line.firstIndex(of: ":") else {
            return nil
        }
        return String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func vaultAssetURL(path: String, vaultRoot: URL) -> URL? {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("[["), value.hasSuffix("]]") {
            value = String(value.dropFirst(2).dropLast(2))
            if let aliasSeparator = value.lastIndex(of: "|") {
                value = String(value[..<aliasSeparator])
            }
        }
        if value.hasPrefix("file://") {
            return URL(string: value)
        }
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        let vaultName = vaultRoot.lastPathComponent
        if value.hasPrefix(vaultName + "/") {
            value = String(value.dropFirst(vaultName.count + 1))
        } else if value.hasPrefix("世界模型/") {
            value = String(value.dropFirst("世界模型/".count))
        }
        return vaultRoot.appendingPathComponent(value).standardizedFileURL
    }

    private static func frontmatterProperties(in text: String) -> ObsidianFrontmatterProperties? {
        var lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return nil
        }
        lines.removeFirst()
        var frontmatterLines: [String] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                return ObsidianFrontmatterProperties(lines: frontmatterLines)
            }
            frontmatterLines.append(line)
        }
        return nil
    }
}

private enum ObsidianFrontmatterValue: Equatable {
    case string(String)
    case array([String])
}

private struct ObsidianFrontmatterProperties {
    private var values: [String: ObsidianFrontmatterValue] = [:]

    init(lines: [String]) {
        var currentArrayKey: String?
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }
            if rawLine.hasPrefix("  - "), let key = currentArrayKey {
                var array = self.array(key)
                array.append(Self.cleanScalar(String(rawLine.dropFirst(4))))
                values[key] = .array(array)
                continue
            }
            guard !rawLine.hasPrefix(" "), let separator = rawLine.firstIndex(of: ":") else {
                continue
            }
            let key = String(rawLine[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = String(rawLine[rawLine.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                continue
            }
            if rawValue.isEmpty {
                values[key] = .array([])
                currentArrayKey = key
            } else {
                values[key] = .string(Self.cleanScalar(rawValue))
                currentArrayKey = nil
            }
        }
    }

    func string(_ key: String) -> String? {
        switch values[key] {
        case let .string(value):
            let normalized = Self.normalizedWikiLink(value).trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty || normalized == "null" ? nil : normalized
        case let .array(values):
            return values.first.map(Self.normalizedWikiLink)
        case nil:
            return nil
        }
    }

    func rawString(_ key: String) -> String? {
        switch values[key] {
        case let .string(value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed == "null" ? nil : trimmed
        case let .array(values):
            return values.first
        case nil:
            return nil
        }
    }

    func array(_ key: String) -> [String] {
        switch values[key] {
        case let .array(values):
            return values.map(Self.normalizedWikiLink).filter { !$0.isEmpty }
        case let .string(value):
            let normalized = Self.normalizedWikiLink(value)
            return normalized.isEmpty ? [] : [normalized]
        case nil:
            return []
        }
    }

    func int(_ key: String) -> Int? {
        string(key).flatMap(Int.init)
    }

    func url(_ key: String) -> URL? {
        string(key).flatMap(URL.init(string:))
    }

    private static func cleanScalar(_ value: String) -> String {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if (cleaned.hasPrefix("\"") && cleaned.hasSuffix("\""))
            || (cleaned.hasPrefix("'") && cleaned.hasSuffix("'")) {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedWikiLink(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.hasPrefix("[["), result.hasSuffix("]]") else {
            return result
        }
        result = String(result.dropFirst(2).dropLast(2))
        if let aliasSeparator = result.lastIndex(of: "|") {
            return String(result[result.index(after: aliasSeparator)...])
        }
        return result.split(separator: "/").last.map(String.init) ?? result
    }
}
