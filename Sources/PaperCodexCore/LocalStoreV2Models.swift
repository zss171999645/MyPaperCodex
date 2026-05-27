import Foundation

public enum PaperStorageState: String, Codable, Equatable, Sendable {
    case savedLocal = "saved_local"
    case cachePreview = "cache_preview"
    case feedPDFCache = "feed_pdf_cache"
    case remotePublic = "remote_public"
    case remotePrivateEncrypted = "remote_private_encrypted"
    case missingLocal = "missing_local"
}

public enum PaperFileEncryptionState: String, Codable, Equatable, Sendable {
    case none
    case encrypted
    case pending
}

public enum PaperSourceType: String, Codable, Equatable, Sendable {
    case arxiv
    case doi
    case url
    case manual
}

public struct LocalAccount: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var remoteUserID: String?
    public var displayName: String
    public var email: String?
    public var syncEnabled: Bool
    public var lastLoginAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        remoteUserID: String?,
        displayName: String,
        email: String?,
        syncEnabled: Bool,
        lastLoginAt: Date?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.remoteUserID = remoteUserID
        self.displayName = displayName
        self.email = email
        self.syncEnabled = syncEnabled
        self.lastLoginAt = lastLoginAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PaperDevice: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var remoteDeviceID: String?
    public var name: String
    public var publicKey: String?
    public var createdAt: Date
    public var revokedAt: Date?

    public init(
        id: String,
        remoteDeviceID: String?,
        name: String,
        publicKey: String?,
        createdAt: Date,
        revokedAt: Date?
    ) {
        self.id = id
        self.remoteDeviceID = remoteDeviceID
        self.name = name
        self.publicKey = publicKey
        self.createdAt = createdAt
        self.revokedAt = revokedAt
    }
}

public struct PaperFileRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var paperID: String
    public var storageState: PaperStorageState
    public var localPath: String?
    public var contentHash: String
    public var byteCount: Int64?
    public var mimeType: String
    public var remoteFileID: String?
    public var encryptionState: PaperFileEncryptionState
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        paperID: String,
        storageState: PaperStorageState,
        localPath: String?,
        contentHash: String,
        byteCount: Int64?,
        mimeType: String,
        remoteFileID: String?,
        encryptionState: PaperFileEncryptionState,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.paperID = paperID
        self.storageState = storageState
        self.localPath = localPath
        self.contentHash = contentHash
        self.byteCount = byteCount
        self.mimeType = mimeType
        self.remoteFileID = remoteFileID
        self.encryptionState = encryptionState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PaperSourceRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var paperID: String
    public var sourceType: PaperSourceType
    public var sourceID: String?
    public var url: String?
    public var version: String?
    public var metadataJSON: String?
    public var createdAt: Date

    public init(
        id: String,
        paperID: String,
        sourceType: PaperSourceType,
        sourceID: String?,
        url: String?,
        version: String?,
        metadataJSON: String?,
        createdAt: Date
    ) {
        self.id = id
        self.paperID = paperID
        self.sourceType = sourceType
        self.sourceID = sourceID
        self.url = url
        self.version = version
        self.metadataJSON = metadataJSON
        self.createdAt = createdAt
    }
}

public struct LibraryFolder: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var parentID: String?
    public var name: String
    public var sortOrder: Int
    public var isPinned: Bool
    public var deletedAt: Date?
    public var syncRevision: Int

    public init(id: String, parentID: String?, name: String, sortOrder: Int, isPinned: Bool = false, deletedAt: Date?, syncRevision: Int) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.sortOrder = sortOrder
        self.isPinned = isPinned
        self.deletedAt = deletedAt
        self.syncRevision = syncRevision
    }
}

public struct HierarchicalPaperTag: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var parentID: String?
    public var name: String
    public var color: String?
    public var sortOrder: Int
    public var deletedAt: Date?
    public var syncRevision: Int

    public init(
        id: String,
        parentID: String?,
        name: String,
        color: String?,
        sortOrder: Int,
        deletedAt: Date?,
        syncRevision: Int
    ) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.color = color
        self.sortOrder = sortOrder
        self.deletedAt = deletedAt
        self.syncRevision = syncRevision
    }
}

public struct PaperNote: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var paperID: String
    public var anchorID: String?
    public var title: String
    public var bodyMarkdown: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var syncRevision: Int

    public init(
        id: String,
        paperID: String,
        anchorID: String?,
        title: String,
        bodyMarkdown: String,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        syncRevision: Int
    ) {
        self.id = id
        self.paperID = paperID
        self.anchorID = anchorID
        self.title = title
        self.bodyMarkdown = bodyMarkdown
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.syncRevision = syncRevision
    }
}

public struct PDFAnnotationRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var paperID: String
    public var anchorID: String?
    public var page: Int
    public var kind: String
    public var color: String?
    public var text: String?
    public var bboxList: [BoundingBox]
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var syncRevision: Int

    public init(
        id: String,
        paperID: String,
        anchorID: String?,
        page: Int,
        kind: String,
        color: String?,
        text: String?,
        bboxList: [BoundingBox],
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        syncRevision: Int
    ) {
        self.id = id
        self.paperID = paperID
        self.anchorID = anchorID
        self.page = page
        self.kind = kind
        self.color = color
        self.text = text
        self.bboxList = bboxList
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.syncRevision = syncRevision
    }
}
