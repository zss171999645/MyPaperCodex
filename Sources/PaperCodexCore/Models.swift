import Foundation

public struct BoundingBox: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct TextRange: Codable, Equatable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

public struct Paper: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var filePath: String
    public var fileHash: String
    public var title: String
    public var authors: [String]
    public var year: Int?
    public var sourceURL: String?
    public var isSaved: Bool
    public var importedAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        filePath: String,
        fileHash: String,
        title: String,
        authors: [String],
        year: Int?,
        sourceURL: String?,
        isSaved: Bool = true,
        importedAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.filePath = filePath
        self.fileHash = fileHash
        self.title = title
        self.authors = authors
        self.year = year
        self.sourceURL = sourceURL
        self.isSaved = isSaved
        self.importedAt = importedAt
        self.updatedAt = updatedAt
    }
}

public struct Category: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var parentID: String?
    public var name: String
    public var sortOrder: Int

    public init(id: String, parentID: String?, name: String, sortOrder: Int) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.sortOrder = sortOrder
    }
}

public struct PaperTag: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct QuickPrompt: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var content: String

    public init(id: String, title: String, content: String) {
        self.id = id
        self.title = title
        self.content = content
    }
}

public struct WatchedFolder: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var path: String
    public var createdAt: Date
    public var lastScannedAt: Date?

    public init(id: String, path: String, createdAt: Date, lastScannedAt: Date?) {
        self.id = id
        self.path = path
        self.createdAt = createdAt
        self.lastScannedAt = lastScannedAt
    }
}

public struct Span: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var paperID: String
    public var page: Int
    public var bbox: BoundingBox
    public var text: String
    public var charRange: TextRange
    public var sectionHint: String?
    public var confidence: Double

    public init(
        id: String,
        paperID: String,
        page: Int,
        bbox: BoundingBox,
        text: String,
        charRange: TextRange,
        sectionHint: String?,
        confidence: Double
    ) {
        self.id = id
        self.paperID = paperID
        self.page = page
        self.bbox = bbox
        self.text = text
        self.charRange = charRange
        self.sectionHint = sectionHint
        self.confidence = confidence
    }

    public static func makeID(paperID: String, page: Int, blockIndex: Int) -> String {
        "paper:\(paperID):p\(page):b\(blockIndex)"
    }
}

public struct Anchor: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var paperID: String
    public var page: Int
    public var selectedText: String
    public var bboxList: [BoundingBox]
    public var matchedSpanIDs: [String]
    public var beforeContext: String
    public var afterContext: String
    public var createdSessionID: String
    public var createdAt: Date
    public var confidence: Double

    public init(
        id: String,
        paperID: String,
        page: Int,
        selectedText: String,
        bboxList: [BoundingBox],
        matchedSpanIDs: [String],
        beforeContext: String,
        afterContext: String,
        createdSessionID: String,
        createdAt: Date,
        confidence: Double
    ) {
        self.id = id
        self.paperID = paperID
        self.page = page
        self.selectedText = selectedText
        self.bboxList = bboxList
        self.matchedSpanIDs = matchedSpanIDs
        self.beforeContext = beforeContext
        self.afterContext = afterContext
        self.createdSessionID = createdSessionID
        self.createdAt = createdAt
        self.confidence = confidence
    }

    public static func makeID(paperID: String, page: Int, suffix: String) -> String {
        "paper:\(paperID):p\(page):a\(suffix)"
    }
}

public struct PaperSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var paperIDs: [String]
    public var codexSessionID: String?
    public var workspacePath: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        title: String,
        paperIDs: [String],
        codexSessionID: String?,
        workspacePath: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.paperIDs = paperIDs
        self.codexSessionID = codexSessionID
        self.workspacePath = workspacePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum ChatRole: String, Codable, Equatable, Sendable {
    case user
    case codex
    case system
}

public struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var sessionID: String
    public var role: ChatRole
    public var content: String
    public var createdAt: Date

    public init(id: String, sessionID: String, role: ChatRole, content: String, createdAt: Date) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public struct PageIndex: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(paperID):p\(page)" }
    public var paperID: String
    public var page: Int
    public var text: String
    public var confidence: Double

    public init(paperID: String, page: Int, text: String, confidence: Double) {
        self.paperID = paperID
        self.page = page
        self.text = text
        self.confidence = confidence
    }
}
