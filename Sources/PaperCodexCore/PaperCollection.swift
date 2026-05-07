import Foundation

public enum PaperCollectionColumnValueKind: String, Codable, CaseIterable, Sendable {
    case paperTitle = "paper_title"
    case authors
    case year
    case categories
    case tags
    case sourceURL = "source_url"
    case text
    case longText = "long_text"
    case number
    case date
    case badge
}

public struct PaperCollectionColumn: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var valueKind: PaperCollectionColumnValueKind
    public var width: Double
    public var isLocked: Bool
    public var isHidden: Bool

    public init(
        id: String,
        title: String,
        valueKind: PaperCollectionColumnValueKind,
        width: Double,
        isLocked: Bool = false,
        isHidden: Bool = false
    ) {
        self.id = id
        self.title = title
        self.valueKind = valueKind
        self.width = width
        self.isLocked = isLocked
        self.isHidden = isHidden
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case valueKind
        case width
        case isLocked
        case isHidden
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        valueKind = try container.decode(PaperCollectionColumnValueKind.self, forKey: .valueKind)
        width = try container.decode(Double.self, forKey: .width)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(valueKind, forKey: .valueKind)
        try container.encode(width, forKey: .width)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(isHidden, forKey: .isHidden)
    }
}

public struct PaperCollectionRow: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var paperID: String
    public var values: [String: String]
    public var addedAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        paperID: String,
        values: [String: String],
        addedAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.paperID = paperID
        self.values = values
        self.addedAt = addedAt
        self.updatedAt = updatedAt
    }

    public static func makeID(paperID: String) -> String {
        "row:\(paperID)"
    }
}

public struct PaperCollectionSeedPaper: Codable, Equatable, Identifiable, Sendable {
    public var paperID: String
    public var title: String
    public var authors: [String]
    public var year: Int?
    public var sourceURL: String?
    public var categories: [String]
    public var tags: [String]

    public var id: String { paperID }

    public init(
        paperID: String,
        title: String,
        authors: [String],
        year: Int?,
        sourceURL: String?,
        categories: [String],
        tags: [String]
    ) {
        self.paperID = paperID
        self.title = title
        self.authors = authors
        self.year = year
        self.sourceURL = sourceURL
        self.categories = categories
        self.tags = tags
    }

    public static func seedPapers(
        papers: [Paper],
        categoriesByPaperID: [String: [String]],
        tagsByPaperID: [String: [PaperTag]]
    ) -> [PaperCollectionSeedPaper] {
        papers.map { paper in
            PaperCollectionSeedPaper(
                paperID: paper.id,
                title: paper.title,
                authors: paper.authors,
                year: paper.year,
                sourceURL: paper.sourceURL,
                categories: categoriesByPaperID[paper.id, default: []],
                tags: tagsByPaperID[paper.id, default: []].map(\.name)
            )
        }
    }
}

public struct PaperCollectionDocument: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: String
    public var title: String
    public var description: String
    public var columns: [PaperCollectionColumn]
    public var rows: [PaperCollectionRow]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        schemaVersion: Int = PaperCollectionDocument.currentSchemaVersion,
        id: String,
        title: String,
        description: String,
        columns: [PaperCollectionColumn],
        rows: [PaperCollectionRow],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.description = description
        self.columns = columns
        self.rows = rows
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static var defaultColumns: [PaperCollectionColumn] {
        [
            PaperCollectionColumn(id: "paper_title", title: "Paper", valueKind: .paperTitle, width: 300, isLocked: true),
            PaperCollectionColumn(id: "authors", title: "Authors", valueKind: .authors, width: 220, isLocked: true),
            PaperCollectionColumn(id: "year", title: "Year", valueKind: .year, width: 86, isLocked: true),
            PaperCollectionColumn(id: "categories", title: "Folders", valueKind: .categories, width: 160, isLocked: true),
            PaperCollectionColumn(id: "tags", title: "Tags", valueKind: .tags, width: 180, isLocked: true),
            PaperCollectionColumn(id: "source_url", title: "Source", valueKind: .sourceURL, width: 240, isLocked: true)
        ]
    }

    public static func newDocument(
        title: String,
        description: String,
        papers: [PaperCollectionSeedPaper],
        createdAt: Date = Date()
    ) -> PaperCollectionDocument {
        var document = PaperCollectionDocument(
            id: UUID().uuidString.lowercased(),
            title: title,
            description: description,
            columns: defaultColumns,
            rows: [],
            createdAt: createdAt,
            updatedAt: createdAt
        )
        document.addPapers(papers, updatedAt: createdAt)
        return document
    }

    public mutating func addPapers(_ papers: [PaperCollectionSeedPaper], updatedAt: Date = Date()) {
        let existingPaperIDs = Set(rows.map(\.paperID))
        let customColumnIDs = columns.filter { !$0.isLocked }.map(\.id)
        var nextRows = rows
        for paper in papers where !existingPaperIDs.contains(paper.paperID) {
            var values = metadataValues(for: paper)
            for columnID in customColumnIDs where values[columnID] == nil {
                values[columnID] = ""
            }
            nextRows.append(
                PaperCollectionRow(
                    id: PaperCollectionRow.makeID(paperID: paper.paperID),
                    paperID: paper.paperID,
                    values: values,
                    addedAt: updatedAt,
                    updatedAt: updatedAt
                )
            )
        }
        rows = nextRows.map { row in
            var next = row
            for column in columns where next.values[column.id] == nil {
                next.values[column.id] = ""
            }
            return next
        }
        self.updatedAt = updatedAt
    }

    public mutating func addColumn(
        title: String,
        valueKind: PaperCollectionColumnValueKind = .text,
        width: Double = 160,
        updatedAt: Date = Date()
    ) -> PaperCollectionColumn {
        let column = PaperCollectionColumn(
            id: uniqueColumnID(for: title),
            title: title,
            valueKind: valueKind,
            width: width,
            isLocked: false
        )
        columns.append(column)
        for index in rows.indices {
            rows[index].values[column.id] = ""
            rows[index].updatedAt = updatedAt
        }
        self.updatedAt = updatedAt
        return column
    }

    public mutating func updateCell(rowID: String, columnID: String, value: String, updatedAt: Date = Date()) {
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowID }),
              columns.contains(where: { $0.id == columnID }) else {
            return
        }
        rows[rowIndex].values[columnID] = value
        rows[rowIndex].updatedAt = updatedAt
        self.updatedAt = updatedAt
    }

    public mutating func setColumnHidden(_ columnID: String, hidden: Bool, updatedAt: Date = Date()) {
        guard let columnIndex = columns.firstIndex(where: { $0.id == columnID }) else {
            return
        }
        columns[columnIndex].isHidden = hidden
        self.updatedAt = updatedAt
    }

    public mutating func refreshPaperMetadata(_ papers: [PaperCollectionSeedPaper], updatedAt: Date = Date()) {
        let papersByID = Dictionary(uniqueKeysWithValues: papers.map { ($0.paperID, $0) })
        for index in rows.indices {
            guard let paper = papersByID[rows[index].paperID] else {
                continue
            }
            let metadata = metadataValues(for: paper)
            for column in columns where column.isLocked {
                rows[index].values[column.id] = metadata[column.id, default: ""]
            }
            rows[index].updatedAt = updatedAt
        }
        self.updatedAt = updatedAt
    }

    public static func codexEditingContract(collectionJSONPath: String) -> String {
        """
        # Paper Codex Collection Editing Contract

        Editable source: \(collectionJSONPath)

        This file is the source of truth for the collection table.

        Rules for Codex:
        - Read collection.json before making changes.
        - Do not change schemaVersion, collection id, row ids, paperID values, or locked metadata column ids.
        - You may update rows[].values for analysis, classification, summaries, tags, decisions, and notes requested by the user.
        - You may append new unlocked columns to columns when the user asks for a new comparison axis. Column ids must be lowercase snake_case and unique.
        - Every new column must include id, title, valueKind, width, isLocked, and isHidden. Set isLocked to false for user/Codex columns. Set isHidden to false unless the user explicitly asks to hide it.
        - valueKind must be one of: text, long_text, badge, number, date.
        - For every new column id, add a string value for every row in rows[].values.
        - Every row value must be a string. Use an empty string when the value is unknown.
        - Preserve valid JSON. Do not wrap the file in Markdown fences.
        - If a requested analysis needs paper evidence, inspect the papers/ workspace files before editing cells.
        """
    }

    private func metadataValues(for paper: PaperCollectionSeedPaper) -> [String: String] {
        [
            "paper_title": paper.title,
            "authors": paper.authors.joined(separator: ", "),
            "year": paper.year.map(String.init) ?? "",
            "categories": paper.categories.joined(separator: ", "),
            "tags": paper.tags.joined(separator: ", "),
            "source_url": paper.sourceURL ?? ""
        ]
    }

    private func uniqueColumnID(for title: String) -> String {
        let base = Self.columnID(for: title)
        let existing = Set(columns.map(\.id))
        guard existing.contains(base) else {
            return base
        }
        var index = 2
        while existing.contains("\(base)_\(index)") {
            index += 1
        }
        return "\(base)_\(index)"
    }

    public static func columnID(for title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "_"
        }
        let collapsed = String(scalars)
            .split(separator: "_")
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
        return collapsed.isEmpty ? "column" : collapsed
    }
}

public final class PaperCollectionStore {
    public let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL) {
        self.root = root
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func list() throws -> [PaperCollectionDocument] {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return []
        }
        let directories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let documents = try directories.compactMap { directory -> PaperCollectionDocument? in
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                return nil
            }
            let jsonURL = directory.appendingPathComponent("collection.json")
            guard FileManager.default.fileExists(atPath: jsonURL.path) else {
                return nil
            }
            return try load(from: jsonURL)
        }
        return documents.sorted { left, right in
            if left.updatedAt == right.updatedAt {
                return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
            }
            return left.updatedAt > right.updatedAt
        }
    }

    public func load(id: String) throws -> PaperCollectionDocument {
        try load(from: collectionJSONURL(id: id))
    }

    public func save(_ document: PaperCollectionDocument) throws {
        let directory = collectionDirectoryURL(id: document.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(document)
        try data.write(to: directory.appendingPathComponent("collection.json"), options: [.atomic])
        try PaperCollectionDocument.codexEditingContract(
            collectionJSONPath: directory.appendingPathComponent("collection.json").path
        )
        .write(to: directory.appendingPathComponent("collection_contract.md"), atomically: true, encoding: .utf8)
    }

    public func delete(id: String) throws {
        let directory = collectionDirectoryURL(id: id)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        try FileManager.default.removeItem(at: directory)
    }

    public func collectionDirectoryURL(id: String) -> URL {
        root.appendingPathComponent(Self.pathSafeID(id), isDirectory: true)
    }

    public func collectionJSONURL(id: String) -> URL {
        collectionDirectoryURL(id: id).appendingPathComponent("collection.json")
    }

    private func load(from url: URL) throws -> PaperCollectionDocument {
        let data = try Data(contentsOf: url)
        return try decoder.decode(PaperCollectionDocument.self, from: data)
    }

    private static func pathSafeID(_ id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = id.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let safe = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return safe.isEmpty ? UUID().uuidString.lowercased() : safe
    }
}
