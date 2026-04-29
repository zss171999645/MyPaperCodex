import Foundation

public enum SyncDataStoreError: Error, CustomStringConvertible, Equatable {
    case duplicateOutboxID(id: String)

    public var description: String {
        switch self {
        case let .duplicateOutboxID(id):
            "Conflicting sync outbox change already exists for id \(id)"
        }
    }
}

private struct SyncOutboxIdentity: Equatable {
    var entityType: String
    var entityID: String
    var operation: String
    var payloadJSON: String
    var baseRemoteRevision: Int?
    var createdAt: String
}

public final class SyncDataStore {
    private let database: SQLiteDatabase
    private let dates = ISO8601DateFormatter()

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func markDirty(entityType: String, entityID: String, localRevision: Int, deleted: Bool, at date: Date) throws {
        try ensureSyncEntityStorage()
        let localUpdatedAt = dates.string(from: date)
        try database.run("""
        INSERT INTO sync_entities (
          entity_type, entity_id, local_revision, remote_revision, dirty, deleted, last_synced_at, local_updated_at
        )
        VALUES (?, ?, ?, NULL, 1, ?, NULL, ?)
        ON CONFLICT(entity_type, entity_id) DO UPDATE SET
          local_revision = MAX(sync_entities.local_revision, excluded.local_revision),
          dirty = 1,
          deleted = CASE
            WHEN excluded.local_revision > sync_entities.local_revision THEN excluded.deleted
            WHEN excluded.local_revision = sync_entities.local_revision THEN MAX(sync_entities.deleted, excluded.deleted)
            ELSE sync_entities.deleted
          END,
          local_updated_at = CASE
            WHEN sync_entities.local_updated_at IS NULL THEN excluded.local_updated_at
            WHEN excluded.local_revision > sync_entities.local_revision THEN excluded.local_updated_at
            WHEN excluded.local_revision = sync_entities.local_revision
              AND excluded.deleted >= sync_entities.deleted THEN MAX(sync_entities.local_updated_at, excluded.local_updated_at)
            ELSE sync_entities.local_updated_at
          END;
        """, bindings: [
            .text(entityType),
            .text(entityID),
            .int(localRevision),
            .int(deleted ? 1 : 0),
            .text(localUpdatedAt)
        ])
    }

    public func enqueue(
        id: String,
        entityType: String,
        entityID: String,
        operation: String,
        payloadJSON: String,
        baseRemoteRevision: Int?,
        createdAt: Date
    ) throws {
        let identity = SyncOutboxIdentity(
            entityType: entityType,
            entityID: entityID,
            operation: operation,
            payloadJSON: payloadJSON,
            baseRemoteRevision: baseRemoteRevision,
            createdAt: dates.string(from: createdAt)
        )
        let existingIdentity = try fetchOutboxIdentity(id: id)
        if let existingIdentity {
            guard existingIdentity == identity else {
                throw SyncDataStoreError.duplicateOutboxID(id: id)
            }
            return
        }

        try database.run("""
        INSERT INTO sync_outbox (id, entity_type, entity_id, operation, payload_json, base_remote_revision, created_at, attempt_count, last_error)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, NULL)
        """, bindings: [
            .text(id),
            .text(identity.entityType),
            .text(identity.entityID),
            .text(identity.operation),
            .text(identity.payloadJSON),
            identity.baseRemoteRevision.map(SQLiteValue.int) ?? .null,
            .text(identity.createdAt)
        ])
    }

    public func setCursor(scope: String, cursor: String, updatedAt: Date) throws {
        try database.run("""
        INSERT INTO sync_cursors (scope, cursor, updated_at) VALUES (?, ?, ?)
        ON CONFLICT(scope) DO UPDATE SET
          cursor = excluded.cursor,
          updated_at = excluded.updated_at;
        """, bindings: [
            .text(scope),
            .text(cursor),
            .text(dates.string(from: updatedAt))
        ])
    }

    public func fetchDirtyEntityIDs(entityType: String) throws -> [String] {
        try database.query("""
        SELECT entity_id
        FROM sync_entities
        WHERE entity_type = ? AND dirty = 1
        ORDER BY entity_id;
        """, bindings: [.text(entityType)]) { row in
            try row.text(0)
        }
    }

    public func fetchPendingOutboxIDs() throws -> [String] {
        try database.query("""
        SELECT id
        FROM sync_outbox
        ORDER BY created_at, id;
        """) { row in
            try row.text(0)
        }
    }

    public func fetchCursor(scope: String) throws -> String? {
        try database.query("""
        SELECT cursor
        FROM sync_cursors
        WHERE scope = ?
        LIMIT 1;
        """, bindings: [.text(scope)]) { row in
            try row.text(0)
        }.first
    }

    private func ensureSyncEntityStorage() throws {
        let columns = try database.tableColumns("sync_entities")
        if !columns.contains("local_updated_at") {
            try database.execute("ALTER TABLE sync_entities ADD COLUMN local_updated_at TEXT;")
        }
    }

    private func fetchOutboxIdentity(id: String) throws -> SyncOutboxIdentity? {
        try database.query("""
        SELECT entity_type, entity_id, operation, payload_json, base_remote_revision, created_at
        FROM sync_outbox
        WHERE id = ?
        LIMIT 1;
        """, bindings: [.text(id)]) { row in
            SyncOutboxIdentity(
                entityType: try row.text(0),
                entityID: try row.text(1),
                operation: try row.text(2),
                payloadJSON: try row.text(3),
                baseRemoteRevision: row.optionalInt(4),
                createdAt: try row.text(5)
            )
        }.first
    }
}
