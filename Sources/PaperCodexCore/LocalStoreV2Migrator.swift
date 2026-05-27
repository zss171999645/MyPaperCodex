import Foundation

public struct LocalStoreV2SourceInfo: Equatable, Sendable {
    public var sourceKind: PaperSourceType
    public var sourceID: String?
    public var version: String?
    public var arxivID: String?
    public var arxivIDVersioned: String?

    public init(
        sourceKind: PaperSourceType,
        sourceID: String?,
        version: String?,
        arxivID: String?,
        arxivIDVersioned: String?
    ) {
        self.sourceKind = sourceKind
        self.sourceID = sourceID
        self.version = version
        self.arxivID = arxivID
        self.arxivIDVersioned = arxivIDVersioned
    }
}

public enum LocalStoreV2Migrator {
    public static func migrate(database: SQLiteDatabase) throws {
        try database.transaction {
            try createTables(database: database)
            try addSyncEntityColumns(database: database)
            try addPaperColumns(database: database)
            try addTagColumns(database: database)
            try addFolderColumns(database: database)
            try backfillFolders(database: database)
            try backfillPaperFiles(database: database)
            try backfillPaperSources(database: database)
        }
    }

    public static func sourceInfo(for sourceURL: String?) -> LocalStoreV2SourceInfo {
        guard let sourceURL,
              !sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return LocalStoreV2SourceInfo(
                sourceKind: .manual,
                sourceID: nil,
                version: nil,
                arxivID: nil,
                arxivIDVersioned: nil
            )
        }
        guard let components = URLComponents(string: sourceURL),
              let host = components.host?.lowercased() else {
            return LocalStoreV2SourceInfo(
                sourceKind: .url,
                sourceID: nil,
                version: nil,
                arxivID: nil,
                arxivIDVersioned: nil
            )
        }
        guard host == "arxiv.org" || host.hasSuffix(".arxiv.org") else {
            return LocalStoreV2SourceInfo(
                sourceKind: .url,
                sourceID: nil,
                version: nil,
                arxivID: nil,
                arxivIDVersioned: nil
            )
        }

        let pathComponents = components.path
            .split(separator: "/")
            .map(String.init)
        guard let sourcePath = pathComponents.first,
              sourcePath == "abs" || sourcePath == "pdf",
              pathComponents.count >= 2 else {
            return LocalStoreV2SourceInfo(
                sourceKind: .arxiv,
                sourceID: nil,
                version: nil,
                arxivID: nil,
                arxivIDVersioned: nil
            )
        }

        var versionedID = pathComponents.dropFirst().joined(separator: "/")
        if versionedID.hasSuffix(".pdf") {
            versionedID.removeLast(4)
        }
        let versionMatch = versionedID.range(of: #"v[0-9]+$"#, options: .regularExpression)
        let version = versionMatch.map { String(versionedID[$0]) }
        let arxivID = versionMatch.map { String(versionedID[..<$0.lowerBound]) } ?? versionedID

        return LocalStoreV2SourceInfo(
            sourceKind: .arxiv,
            sourceID: arxivID.isEmpty ? nil : arxivID,
            version: version,
            arxivID: arxivID.isEmpty ? nil : arxivID,
            arxivIDVersioned: versionedID.isEmpty ? nil : versionedID
        )
    }

    public static func canonicalKey(fileHash: String, sourceInfo: LocalStoreV2SourceInfo) -> String {
        if let arxivID = sourceInfo.arxivID {
            return "arxiv:\(arxivID)"
        }
        return fileHash
    }

    private static func createTables(database: SQLiteDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS local_accounts (
          id TEXT PRIMARY KEY,
          remote_user_id TEXT,
          display_name TEXT NOT NULL,
          email TEXT,
          sync_enabled INTEGER NOT NULL DEFAULT 0,
          last_login_at TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS devices (
          id TEXT PRIMARY KEY,
          remote_device_id TEXT,
          name TEXT NOT NULL,
          public_key TEXT,
          created_at TEXT NOT NULL,
          revoked_at TEXT
        );

        CREATE TABLE IF NOT EXISTS paper_files (
          id TEXT PRIMARY KEY,
          paper_id TEXT NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
          storage_state TEXT NOT NULL,
          local_path TEXT,
          content_hash TEXT NOT NULL,
          byte_count INTEGER,
          mime_type TEXT NOT NULL,
          remote_file_id TEXT,
          encryption_state TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS paper_sources (
          id TEXT PRIMARY KEY,
          paper_id TEXT NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
          source_type TEXT NOT NULL,
          source_id TEXT,
          url TEXT,
          version TEXT,
          metadata_json TEXT,
          created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS folders (
          id TEXT PRIMARY KEY,
          parent_id TEXT REFERENCES folders(id) ON DELETE CASCADE,
          name TEXT NOT NULL,
          sort_order INTEGER NOT NULL,
          is_pinned INTEGER NOT NULL DEFAULT 0,
          deleted_at TEXT,
          sync_revision INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS paper_folders (
          paper_id TEXT NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
          folder_id TEXT NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
          created_at TEXT NOT NULL DEFAULT '',
          deleted_at TEXT,
          PRIMARY KEY (paper_id, folder_id)
        );

        CREATE TABLE IF NOT EXISTS paper_notes (
          id TEXT PRIMARY KEY,
          paper_id TEXT NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
          anchor_id TEXT REFERENCES anchors(id) ON DELETE SET NULL,
          title TEXT NOT NULL,
          body_markdown TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted_at TEXT,
          sync_revision INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS pdf_annotations (
          id TEXT PRIMARY KEY,
          paper_id TEXT NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
          anchor_id TEXT REFERENCES anchors(id) ON DELETE SET NULL,
          page INTEGER NOT NULL,
          kind TEXT NOT NULL,
          color TEXT,
          text TEXT,
          bbox_list_json TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted_at TEXT,
          sync_revision INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS arxiv_feed_dates (
          date TEXT PRIMARY KEY,
          source TEXT NOT NULL,
          feed_version TEXT,
          filter_snapshot_json TEXT,
          cached_at TEXT NOT NULL,
          expires_at TEXT
        );

        CREATE TABLE IF NOT EXISTS arxiv_feed_items (
          date TEXT NOT NULL,
          arxiv_id TEXT NOT NULL,
          paper_json TEXT NOT NULL,
          sort_key REAL,
          similarity REAL,
          is_favorite INTEGER,
          cached_at TEXT NOT NULL,
          PRIMARY KEY (date, arxiv_id)
        );

        CREATE TABLE IF NOT EXISTS arxiv_assets (
          asset_key TEXT PRIMARY KEY,
          arxiv_id TEXT NOT NULL,
          date TEXT NOT NULL,
          kind TEXT NOT NULL,
          local_path TEXT,
          url TEXT NOT NULL,
          content_hash TEXT,
          byte_count INTEGER,
          cached_at TEXT NOT NULL,
          last_accessed_at TEXT
        );

        CREATE TABLE IF NOT EXISTS arxiv_pdf_cache (
          arxiv_id TEXT PRIMARY KEY,
          date TEXT NOT NULL,
          local_path TEXT NOT NULL,
          content_hash TEXT,
          byte_count INTEGER,
          cached_at TEXT NOT NULL,
          last_accessed_at TEXT,
          promoted_paper_id TEXT REFERENCES papers(id) ON DELETE SET NULL
        );

        CREATE TABLE IF NOT EXISTS sync_entities (
          entity_type TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          local_revision INTEGER NOT NULL DEFAULT 0,
          remote_revision INTEGER,
          dirty INTEGER NOT NULL DEFAULT 0,
          deleted INTEGER NOT NULL DEFAULT 0,
          last_synced_at TEXT,
          local_updated_at TEXT,
          PRIMARY KEY (entity_type, entity_id)
        );

        CREATE TABLE IF NOT EXISTS sync_outbox (
          id TEXT PRIMARY KEY,
          entity_type TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          operation TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          base_remote_revision INTEGER,
          created_at TEXT NOT NULL,
          attempt_count INTEGER NOT NULL DEFAULT 0,
          last_error TEXT
        );

        CREATE TABLE IF NOT EXISTS sync_cursors (
          scope TEXT PRIMARY KEY,
          cursor TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        """)
    }

    private static func addSyncEntityColumns(database: SQLiteDatabase) throws {
        let columns = try database.tableColumns("sync_entities")
        if !columns.contains("local_updated_at") {
            try database.execute("ALTER TABLE sync_entities ADD COLUMN local_updated_at TEXT;")
        }
    }

    private static func addPaperColumns(database: SQLiteDatabase) throws {
        let columns = try database.tableColumns("papers")
        let additions: [(String, String)] = [
            ("canonical_key", "TEXT"),
            ("abstract", "TEXT"),
            ("source_kind", "TEXT"),
            ("arxiv_id", "TEXT"),
            ("arxiv_id_versioned", "TEXT"),
            ("doi", "TEXT"),
            ("is_starred", "INTEGER NOT NULL DEFAULT 0"),
            ("deleted_at", "TEXT"),
            ("sync_revision", "INTEGER NOT NULL DEFAULT 0")
        ]
        for (name, definition) in additions where !columns.contains(name) {
            try database.execute("ALTER TABLE papers ADD COLUMN \(name) \(definition);")
        }
        let papers = try database.query("SELECT id, file_hash, source_url FROM papers;") { row in
            (
                id: try row.text(0),
                fileHash: try row.text(1),
                sourceURL: row.optionalText(2)
            )
        }
        for paper in papers {
            let sourceInfo = sourceInfo(for: paper.sourceURL)
            try database.run("""
            UPDATE papers
            SET canonical_key = ?,
                source_kind = ?,
                arxiv_id = ?,
                arxiv_id_versioned = ?,
                sync_revision = COALESCE(sync_revision, 0)
            WHERE id = ?;
            """, bindings: [
                .text(canonicalKey(fileHash: paper.fileHash, sourceInfo: sourceInfo)),
                .text(sourceInfo.sourceKind.rawValue),
                sourceInfo.arxivID.map(SQLiteValue.text) ?? .null,
                sourceInfo.arxivIDVersioned.map(SQLiteValue.text) ?? .null,
                .text(paper.id)
            ])
        }
    }

    private static func addTagColumns(database: SQLiteDatabase) throws {
        let columns = try database.tableColumns("tags")
        let additions: [(String, String)] = [
            ("parent_id", "TEXT REFERENCES tags(id) ON DELETE CASCADE"),
            ("color", "TEXT"),
            ("sort_order", "INTEGER NOT NULL DEFAULT 0"),
            ("deleted_at", "TEXT"),
            ("sync_revision", "INTEGER NOT NULL DEFAULT 0")
        ]
        for (name, definition) in additions where !columns.contains(name) {
            try database.execute("ALTER TABLE tags ADD COLUMN \(name) \(definition);")
        }
    }

    private static func addFolderColumns(database: SQLiteDatabase) throws {
        let columns = try database.tableColumns("folders")
        if !columns.contains("is_pinned") {
            try database.execute("ALTER TABLE folders ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0;")
        }
    }

    private static func backfillFolders(database: SQLiteDatabase) throws {
        try database.run("""
        INSERT INTO folders (id, parent_id, name, sort_order, is_pinned, deleted_at, sync_revision)
        SELECT id, parent_id, name, sort_order, COALESCE(is_pinned, 0), NULL, 0 FROM categories
        WHERE true
        ON CONFLICT(id) DO UPDATE SET
          parent_id = excluded.parent_id,
          name = excluded.name,
          sort_order = excluded.sort_order,
          is_pinned = excluded.is_pinned,
          deleted_at = NULL;
        """)
        try database.run("""
        INSERT INTO paper_folders (paper_id, folder_id, created_at, deleted_at)
        SELECT paper_categories.paper_id, paper_categories.category_id, papers.imported_at, NULL
        FROM paper_categories
        JOIN papers ON papers.id = paper_categories.paper_id
        WHERE true
        ON CONFLICT(paper_id, folder_id) DO UPDATE SET
          created_at = CASE
            WHEN paper_folders.created_at = '' THEN excluded.created_at
            ELSE paper_folders.created_at
          END,
          deleted_at = NULL;
        """)
    }

    private static func backfillPaperFiles(database: SQLiteDatabase) throws {
        try database.run("""
        INSERT INTO paper_files (
          id, paper_id, storage_state, local_path, content_hash, byte_count, mime_type,
          remote_file_id, encryption_state, created_at, updated_at
        )
        SELECT
          'file:' || id || ':original',
          id,
          CASE WHEN is_saved = 1 THEN 'saved_local' ELSE 'cache_preview' END,
          file_path,
          file_hash,
          NULL,
          'application/pdf',
          NULL,
          'none',
          imported_at,
          updated_at
        FROM papers
        WHERE true
        ON CONFLICT(id) DO UPDATE SET
          storage_state = excluded.storage_state,
          local_path = excluded.local_path,
          content_hash = excluded.content_hash,
          mime_type = excluded.mime_type,
          updated_at = excluded.updated_at;
        """)
    }

    private static func backfillPaperSources(database: SQLiteDatabase) throws {
        let papers = try database.query("SELECT id, source_url, imported_at FROM papers WHERE source_url IS NOT NULL;") { row in
            (
                id: try row.text(0),
                sourceURL: row.optionalText(1),
                importedAt: try row.text(2)
            )
        }
        for paper in papers {
            let sourceInfo = sourceInfo(for: paper.sourceURL)
            try database.run("""
            INSERT INTO paper_sources (id, paper_id, source_type, source_id, url, version, metadata_json, created_at)
            VALUES (?, ?, ?, ?, ?, ?, NULL, ?)
            ON CONFLICT(id) DO UPDATE SET
              source_type = excluded.source_type,
              source_id = excluded.source_id,
              url = excluded.url,
              version = excluded.version;
            """, bindings: [
                .text("source:\(paper.id):primary"),
                .text(paper.id),
                .text(sourceInfo.sourceKind.rawValue),
                sourceInfo.sourceID.map(SQLiteValue.text) ?? .null,
                paper.sourceURL.map(SQLiteValue.text) ?? .null,
                sourceInfo.version.map(SQLiteValue.text) ?? .null,
                .text(paper.importedAt)
            ])
        }
    }
}
