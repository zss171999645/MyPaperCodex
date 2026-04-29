import Foundation

public enum PaperRepositoryError: Error, CustomStringConvertible, Equatable {
    case encodingFailed(String)
    case decodingFailed(String)

    public var description: String {
        switch self {
        case let .encodingFailed(message):
            "Could not encode repository value: \(message)"
        case let .decodingFailed(message):
            "Could not decode repository value: \(message)"
        }
    }
}

public final class PaperRepository {
    private let database: SQLiteDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let dates = ISO8601DateFormatter()

    public init(databasePath: String) throws {
        self.database = try SQLiteDatabase(path: databasePath)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func migrate() throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS papers (
          id TEXT PRIMARY KEY,
          file_path TEXT NOT NULL,
          file_hash TEXT NOT NULL UNIQUE,
          title TEXT NOT NULL,
          authors_json TEXT NOT NULL,
          year INTEGER,
          source_url TEXT,
          is_saved INTEGER NOT NULL DEFAULT 1,
          imported_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS categories (
          id TEXT PRIMARY KEY,
          parent_id TEXT REFERENCES categories(id) ON DELETE CASCADE,
          name TEXT NOT NULL,
          sort_order INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS tags (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL UNIQUE
        );

        CREATE TABLE IF NOT EXISTS paper_categories (
          paper_id TEXT NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
          category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
          PRIMARY KEY (paper_id, category_id)
        );

        CREATE TABLE IF NOT EXISTS paper_tags (
          paper_id TEXT NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
          tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
          PRIMARY KEY (paper_id, tag_id)
        );

        CREATE TABLE IF NOT EXISTS watched_folders (
          id TEXT PRIMARY KEY,
          path TEXT NOT NULL UNIQUE,
          created_at TEXT NOT NULL,
          last_scanned_at TEXT
        );

        CREATE TABLE IF NOT EXISTS pages (
          paper_id TEXT NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
          page INTEGER NOT NULL,
          text TEXT NOT NULL,
          confidence REAL NOT NULL,
          PRIMARY KEY (paper_id, page)
        );

        CREATE TABLE IF NOT EXISTS spans (
          id TEXT PRIMARY KEY,
          paper_id TEXT NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
          page INTEGER NOT NULL,
          bbox_json TEXT NOT NULL,
          text TEXT NOT NULL,
          char_range_json TEXT NOT NULL,
          section_hint TEXT,
          confidence REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS anchors (
          id TEXT PRIMARY KEY,
          paper_id TEXT NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
          page INTEGER NOT NULL,
          selected_text TEXT NOT NULL,
          bbox_list_json TEXT NOT NULL,
          matched_span_ids_json TEXT NOT NULL,
          before_context TEXT NOT NULL,
          after_context TEXT NOT NULL,
          created_session_id TEXT NOT NULL,
          created_at TEXT NOT NULL,
          confidence REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS sessions (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          codex_session_id TEXT,
          workspace_path TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS session_papers (
          session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
          paper_id TEXT NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
          sort_order INTEGER NOT NULL,
          PRIMARY KEY (session_id, paper_id)
        );

        CREATE TABLE IF NOT EXISTS chat_messages (
          id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at TEXT NOT NULL
        );
        """)
        let paperColumns = try database.query("PRAGMA table_info(papers);") { row in
            try row.text(1)
        }
        if !paperColumns.contains("is_saved") {
            try database.execute("ALTER TABLE papers ADD COLUMN is_saved INTEGER NOT NULL DEFAULT 1;")
        }
        try LocalStoreV2Migrator.migrate(database: database)
    }

    public func upsertPaper(_ paper: Paper) throws {
        try database.transaction {
            try database.run("""
            INSERT INTO papers (id, file_path, file_hash, title, authors_json, year, source_url, is_saved, imported_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              file_path = excluded.file_path,
              file_hash = excluded.file_hash,
              title = excluded.title,
              authors_json = excluded.authors_json,
              year = excluded.year,
              source_url = excluded.source_url,
              is_saved = excluded.is_saved,
              updated_at = excluded.updated_at;
            """, bindings: [
                .text(paper.id),
                .text(paper.filePath),
                .text(paper.fileHash),
                .text(paper.title),
                .text(try jsonString(paper.authors)),
                paper.year.map(SQLiteValue.int) ?? .null,
                paper.sourceURL.map(SQLiteValue.text) ?? .null,
                .int(paper.isSaved ? 1 : 0),
                .text(dates.string(from: paper.importedAt)),
                .text(dates.string(from: paper.updatedAt))
            ])
            try syncLocalStoreV2Paper(paper)
        }
    }

    public func fetchPapers() throws -> [Paper] {
        try database.query("""
        SELECT id, file_path, file_hash, title, authors_json, year, source_url, is_saved, imported_at, updated_at
        FROM papers WHERE is_saved = 1 ORDER BY title, id;
        """) { row in
            try paper(from: row)
        }
    }

    public func fetchPapers(ids: [String]) throws -> [Paper] {
        guard !ids.isEmpty else {
            return []
        }
        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        let fetched = try database.query("""
        SELECT id, file_path, file_hash, title, authors_json, year, source_url, is_saved, imported_at, updated_at
        FROM papers WHERE id IN (\(placeholders));
        """, bindings: ids.map(SQLiteValue.text)) { row in
            try paper(from: row)
        }
        let byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    public func fetchPaper(fileHash: String) throws -> Paper? {
        try database.query("""
        SELECT id, file_path, file_hash, title, authors_json, year, source_url, is_saved, imported_at, updated_at
        FROM papers WHERE file_hash = ? LIMIT 1;
        """, bindings: [.text(fileHash)]) { row in
            try paper(from: row)
        }.first
    }

    public func deleteUnsavedPapers() throws {
        try database.run("DELETE FROM papers WHERE is_saved = 0;")
        try database.run("""
        DELETE FROM sessions
        WHERE id NOT IN (SELECT DISTINCT session_id FROM session_papers);
        """)
    }

    public func upsertCategory(_ category: Category) throws {
        try database.transaction {
            try database.run("""
            INSERT INTO categories (id, parent_id, name, sort_order)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              parent_id = excluded.parent_id,
              name = excluded.name,
              sort_order = excluded.sort_order;
            """, bindings: [
                .text(category.id),
                category.parentID.map(SQLiteValue.text) ?? .null,
                .text(category.name),
                .int(category.sortOrder)
            ])
            try syncLocalStoreV2Folder(category)
        }
    }

    public func fetchCategories() throws -> [Category] {
        try database.query("SELECT id, parent_id, name, sort_order FROM categories ORDER BY sort_order, name;") { row in
            Category(
                id: try row.text(0),
                parentID: row.optionalText(1),
                name: try row.text(2),
                sortOrder: row.int(3)
            )
        }
    }

    public func upsertTag(_ tag: PaperTag) throws {
        try database.transaction {
            try database.run("""
            INSERT INTO tags (id, name) VALUES (?, ?)
            ON CONFLICT(id) DO UPDATE SET name = excluded.name;
            """, bindings: [.text(tag.id), .text(tag.name)])
            try syncLocalStoreV2Tag(tag)
        }
    }

    public func fetchTags() throws -> [PaperTag] {
        try database.query("SELECT id, name FROM tags ORDER BY name, id;") { row in
            PaperTag(id: try row.text(0), name: try row.text(1))
        }
    }

    public func assignPaper(_ paperID: String, toCategory categoryID: String) throws {
        try database.transaction {
            try database.run("""
            INSERT OR IGNORE INTO paper_categories (paper_id, category_id) VALUES (?, ?);
            """, bindings: [.text(paperID), .text(categoryID)])
            try syncLocalStoreV2PaperFolder(paperID: paperID, folderID: categoryID, deletedAt: nil)
        }
    }

    public func removePaper(_ paperID: String, fromCategory categoryID: String) throws {
        try database.transaction {
            try database.run("""
            DELETE FROM paper_categories WHERE paper_id = ? AND category_id = ?;
            """, bindings: [.text(paperID), .text(categoryID)])
            try syncLocalStoreV2PaperFolder(paperID: paperID, folderID: categoryID, deletedAt: Date())
        }
    }

    public func assignPaper(_ paperID: String, toTag tagID: String) throws {
        try database.run("""
        INSERT OR IGNORE INTO paper_tags (paper_id, tag_id) VALUES (?, ?);
        """, bindings: [.text(paperID), .text(tagID)])
    }

    public func removePaper(_ paperID: String, fromTag tagID: String) throws {
        try database.run("""
        DELETE FROM paper_tags WHERE paper_id = ? AND tag_id = ?;
        """, bindings: [.text(paperID), .text(tagID)])
    }

    public func upsertWatchedFolder(_ folder: WatchedFolder) throws {
        try database.run("""
        INSERT INTO watched_folders (id, path, created_at, last_scanned_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          path = excluded.path,
          last_scanned_at = excluded.last_scanned_at;
        """, bindings: [
            .text(folder.id),
            .text(folder.path),
            .text(dates.string(from: folder.createdAt)),
            folder.lastScannedAt.map { .text(dates.string(from: $0)) } ?? .null
        ])
    }

    public func fetchWatchedFolders() throws -> [WatchedFolder] {
        try database.query("""
        SELECT id, path, created_at, last_scanned_at
        FROM watched_folders ORDER BY path, id;
        """) { row in
            try watchedFolder(from: row)
        }
    }

    public func deleteWatchedFolder(id: String) throws {
        try database.run("DELETE FROM watched_folders WHERE id = ?;", bindings: [.text(id)])
    }

    public func fetchTags(forPaperID paperID: String) throws -> [PaperTag] {
        try database.query("""
        SELECT tags.id, tags.name
        FROM tags
        JOIN paper_tags ON paper_tags.tag_id = tags.id
        WHERE paper_tags.paper_id = ?
        ORDER BY tags.name, tags.id;
        """, bindings: [.text(paperID)]) { row in
            PaperTag(id: try row.text(0), name: try row.text(1))
        }
    }

    public func fetchCategoryIDs(forPaperID paperID: String) throws -> [String] {
        try database.query("""
        SELECT category_id FROM paper_categories WHERE paper_id = ? ORDER BY category_id;
        """, bindings: [.text(paperID)]) { row in
            try row.text(0)
        }
    }

    public func upsertPage(_ page: PageIndex) throws {
        try database.run("""
        INSERT INTO pages (paper_id, page, text, confidence)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(paper_id, page) DO UPDATE SET
          text = excluded.text,
          confidence = excluded.confidence;
        """, bindings: [
            .text(page.paperID),
            .int(page.page),
            .text(page.text),
            .double(page.confidence)
        ])
    }

    public func fetchPages(paperID: String) throws -> [PageIndex] {
        try database.query("""
        SELECT paper_id, page, text, confidence
        FROM pages WHERE paper_id = ? ORDER BY page;
        """, bindings: [.text(paperID)]) { row in
            PageIndex(
                paperID: try row.text(0),
                page: row.int(1),
                text: try row.text(2),
                confidence: row.double(3)
            )
        }
    }

    public func upsertSpan(_ span: Span) throws {
        try database.run("""
        INSERT INTO spans (id, paper_id, page, bbox_json, text, char_range_json, section_hint, confidence)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          page = excluded.page,
          bbox_json = excluded.bbox_json,
          text = excluded.text,
          char_range_json = excluded.char_range_json,
          section_hint = excluded.section_hint,
          confidence = excluded.confidence;
        """, bindings: [
            .text(span.id),
            .text(span.paperID),
            .int(span.page),
            .text(try jsonString(span.bbox)),
            .text(span.text),
            .text(try jsonString(span.charRange)),
            span.sectionHint.map(SQLiteValue.text) ?? .null,
            .double(span.confidence)
        ])
    }

    public func fetchSpans(paperID: String) throws -> [Span] {
        try database.query("""
        SELECT id, paper_id, page, bbox_json, text, char_range_json, section_hint, confidence
        FROM spans WHERE paper_id = ? ORDER BY page, id;
        """, bindings: [.text(paperID)]) { row in
            try span(from: row)
        }
    }

    public func fetchSpan(id: String) throws -> Span? {
        try database.query("""
        SELECT id, paper_id, page, bbox_json, text, char_range_json, section_hint, confidence
        FROM spans WHERE id = ? LIMIT 1;
        """, bindings: [.text(id)]) { row in
            try span(from: row)
        }.first
    }

    public func upsertAnchor(_ anchor: Anchor) throws {
        try database.run("""
        INSERT INTO anchors (id, paper_id, page, selected_text, bbox_list_json, matched_span_ids_json, before_context, after_context, created_session_id, created_at, confidence)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          selected_text = excluded.selected_text,
          bbox_list_json = excluded.bbox_list_json,
          matched_span_ids_json = excluded.matched_span_ids_json,
          before_context = excluded.before_context,
          after_context = excluded.after_context,
          confidence = excluded.confidence;
        """, bindings: [
            .text(anchor.id),
            .text(anchor.paperID),
            .int(anchor.page),
            .text(anchor.selectedText),
            .text(try jsonString(anchor.bboxList)),
            .text(try jsonString(anchor.matchedSpanIDs)),
            .text(anchor.beforeContext),
            .text(anchor.afterContext),
            .text(anchor.createdSessionID),
            .text(dates.string(from: anchor.createdAt)),
            .double(anchor.confidence)
        ])
    }

    public func fetchAnchors(paperID: String) throws -> [Anchor] {
        try database.query("""
        SELECT id, paper_id, page, selected_text, bbox_list_json, matched_span_ids_json, before_context, after_context, created_session_id, created_at, confidence
        FROM anchors WHERE paper_id = ? ORDER BY created_at, id;
        """, bindings: [.text(paperID)]) { row in
            try anchor(from: row)
        }
    }

    public func fetchAnchor(id: String) throws -> Anchor? {
        try database.query("""
        SELECT id, paper_id, page, selected_text, bbox_list_json, matched_span_ids_json, before_context, after_context, created_session_id, created_at, confidence
        FROM anchors WHERE id = ? LIMIT 1;
        """, bindings: [.text(id)]) { row in
            try anchor(from: row)
        }.first
    }

    public func upsertSession(_ session: PaperSession) throws {
        try database.run("""
        INSERT INTO sessions (id, title, codex_session_id, workspace_path, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title,
          codex_session_id = excluded.codex_session_id,
          workspace_path = excluded.workspace_path,
          updated_at = excluded.updated_at;
        """, bindings: [
            .text(session.id),
            .text(session.title),
            session.codexSessionID.map(SQLiteValue.text) ?? .null,
            .text(session.workspacePath),
            .text(dates.string(from: session.createdAt)),
            .text(dates.string(from: session.updatedAt))
        ])
        try database.run("DELETE FROM session_papers WHERE session_id = ?;", bindings: [.text(session.id)])
        for (index, paperID) in session.paperIDs.enumerated() {
            try database.run("""
            INSERT INTO session_papers (session_id, paper_id, sort_order) VALUES (?, ?, ?);
            """, bindings: [.text(session.id), .text(paperID), .int(index)])
        }
    }

    public func fetchSessions(paperID: String) throws -> [PaperSession] {
        let sessions = try database.query("""
        SELECT DISTINCT sessions.id, sessions.title, sessions.codex_session_id, sessions.workspace_path, sessions.created_at, sessions.updated_at
        FROM sessions
        JOIN session_papers ON session_papers.session_id = sessions.id
        WHERE session_papers.paper_id = ?
        ORDER BY sessions.updated_at, sessions.id;
        """, bindings: [.text(paperID)]) { row in
            try session(from: row)
        }
        return try sessions.map { session in
            var updated = session
            updated.paperIDs = try fetchPaperIDs(sessionID: session.id)
            return updated
        }
    }

    public func fetchSession(id: String) throws -> PaperSession? {
        let sessions = try database.query("""
        SELECT id, title, codex_session_id, workspace_path, created_at, updated_at
        FROM sessions WHERE id = ? LIMIT 1;
        """, bindings: [.text(id)]) { row in
            try session(from: row)
        }
        guard var session = sessions.first else {
            return nil
        }
        session.paperIDs = try fetchPaperIDs(sessionID: session.id)
        return session
    }

    public func appendMessage(_ message: ChatMessage) throws {
        try database.run("""
        INSERT INTO chat_messages (id, session_id, role, content, created_at)
        VALUES (?, ?, ?, ?, ?);
        """, bindings: [
            .text(message.id),
            .text(message.sessionID),
            .text(message.role.rawValue),
            .text(message.content),
            .text(dates.string(from: message.createdAt))
        ])
    }

    public func fetchMessages(sessionID: String) throws -> [ChatMessage] {
        try database.query("""
        SELECT id, session_id, role, content, created_at
        FROM chat_messages WHERE session_id = ? ORDER BY created_at, id;
        """, bindings: [.text(sessionID)]) { row in
            ChatMessage(
                id: try row.text(0),
                sessionID: try row.text(1),
                role: ChatRole(rawValue: try row.text(2)) ?? .system,
                content: try row.text(3),
                createdAt: try date(from: try row.text(4))
            )
        }
    }

    private func syncLocalStoreV2Paper(_ paper: Paper) throws {
        let sourceInfo = LocalStoreV2Migrator.sourceInfo(for: paper.sourceURL)
        try database.run("""
        UPDATE papers
        SET canonical_key = ?,
            source_kind = ?,
            arxiv_id = ?,
            arxiv_id_versioned = ?,
            sync_revision = COALESCE(sync_revision, 0)
        WHERE id = ?;
        """, bindings: [
            .text(LocalStoreV2Migrator.canonicalKey(fileHash: paper.fileHash, sourceInfo: sourceInfo)),
            .text(sourceInfo.sourceKind.rawValue),
            sourceInfo.arxivID.map(SQLiteValue.text) ?? .null,
            sourceInfo.arxivIDVersioned.map(SQLiteValue.text) ?? .null,
            .text(paper.id)
        ])
        try database.run("""
        INSERT INTO paper_files (
          id, paper_id, storage_state, local_path, content_hash, byte_count, mime_type,
          remote_file_id, encryption_state, created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, NULL, ?, NULL, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          storage_state = excluded.storage_state,
          local_path = excluded.local_path,
          content_hash = excluded.content_hash,
          mime_type = excluded.mime_type,
          updated_at = excluded.updated_at;
        """, bindings: [
            .text("file:\(paper.id):original"),
            .text(paper.id),
            .text((paper.isSaved ? PaperStorageState.savedLocal : .cachePreview).rawValue),
            .text(paper.filePath),
            .text(paper.fileHash),
            .text("application/pdf"),
            .text(PaperFileEncryptionState.none.rawValue),
            .text(dates.string(from: paper.importedAt)),
            .text(dates.string(from: paper.updatedAt))
        ])

        guard let sourceURL = paper.sourceURL else {
            try database.run("DELETE FROM paper_sources WHERE id = ?;", bindings: [.text("source:\(paper.id):primary")])
            return
        }
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
            .text(sourceURL),
            sourceInfo.version.map(SQLiteValue.text) ?? .null,
            .text(dates.string(from: paper.importedAt))
        ])
    }

    private func syncLocalStoreV2Folder(_ category: Category) throws {
        try database.run("""
        INSERT INTO folders (id, parent_id, name, sort_order, deleted_at, sync_revision)
        VALUES (?, ?, ?, ?, NULL, 0)
        ON CONFLICT(id) DO UPDATE SET
          parent_id = excluded.parent_id,
          name = excluded.name,
          sort_order = excluded.sort_order,
          deleted_at = NULL;
        """, bindings: [
            .text(category.id),
            category.parentID.map(SQLiteValue.text) ?? .null,
            .text(category.name),
            .int(category.sortOrder)
        ])
    }

    private func syncLocalStoreV2Tag(_ tag: PaperTag) throws {
        try database.run("""
        UPDATE tags
        SET deleted_at = NULL,
            sync_revision = COALESCE(sync_revision, 0)
        WHERE id = ?;
        """, bindings: [.text(tag.id)])
    }

    private func syncLocalStoreV2PaperFolder(paperID: String, folderID: String, deletedAt: Date?) throws {
        let now = dates.string(from: Date())
        try database.run("""
        INSERT INTO paper_folders (paper_id, folder_id, created_at, deleted_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(paper_id, folder_id) DO UPDATE SET
          created_at = CASE
            WHEN paper_folders.created_at = '' THEN excluded.created_at
            ELSE paper_folders.created_at
          END,
          deleted_at = excluded.deleted_at;
        """, bindings: [
            .text(paperID),
            .text(folderID),
            .text(now),
            deletedAt.map { .text(dates.string(from: $0)) } ?? .null
        ])
    }

    private func fetchPaperIDs(sessionID: String) throws -> [String] {
        try database.query("""
        SELECT paper_id FROM session_papers WHERE session_id = ? ORDER BY sort_order, paper_id;
        """, bindings: [.text(sessionID)]) { row in
            try row.text(0)
        }
    }

    private func session(from row: SQLiteRow) throws -> PaperSession {
        PaperSession(
            id: try row.text(0),
            title: try row.text(1),
            paperIDs: [],
            codexSessionID: row.optionalText(2),
            workspacePath: try row.text(3),
            createdAt: try date(from: try row.text(4)),
            updatedAt: try date(from: try row.text(5))
        )
    }

    private func paper(from row: SQLiteRow) throws -> Paper {
        Paper(
            id: try row.text(0),
            filePath: try row.text(1),
            fileHash: try row.text(2),
            title: try row.text(3),
            authors: try decode([String].self, from: try row.text(4)),
            year: row.optionalInt(5),
            sourceURL: row.optionalText(6),
            isSaved: row.int(7) != 0,
            importedAt: try date(from: try row.text(8)),
            updatedAt: try date(from: try row.text(9))
        )
    }

    private func span(from row: SQLiteRow) throws -> Span {
        Span(
            id: try row.text(0),
            paperID: try row.text(1),
            page: row.int(2),
            bbox: try decode(BoundingBox.self, from: try row.text(3)),
            text: try row.text(4),
            charRange: try decode(TextRange.self, from: try row.text(5)),
            sectionHint: row.optionalText(6),
            confidence: row.double(7)
        )
    }

    private func anchor(from row: SQLiteRow) throws -> Anchor {
        Anchor(
            id: try row.text(0),
            paperID: try row.text(1),
            page: row.int(2),
            selectedText: try row.text(3),
            bboxList: try decode([BoundingBox].self, from: try row.text(4)),
            matchedSpanIDs: try decode([String].self, from: try row.text(5)),
            beforeContext: try row.text(6),
            afterContext: try row.text(7),
            createdSessionID: try row.text(8),
            createdAt: try date(from: try row.text(9)),
            confidence: row.double(10)
        )
    }

    private func watchedFolder(from row: SQLiteRow) throws -> WatchedFolder {
        WatchedFolder(
            id: try row.text(0),
            path: try row.text(1),
            createdAt: try date(from: try row.text(2)),
            lastScannedAt: try row.optionalText(3).map { try date(from: $0) }
        )
    }

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        do {
            let data = try encoder.encode(value)
            return String(decoding: data, as: UTF8.self)
        } catch {
            throw PaperRepositoryError.encodingFailed(String(describing: error))
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        do {
            return try decoder.decode(type, from: Data(json.utf8))
        } catch {
            throw PaperRepositoryError.decodingFailed(String(describing: error))
        }
    }

    private func date(from string: String) throws -> Date {
        if let date = dates.date(from: string) {
            return date
        }
        throw PaperRepositoryError.decodingFailed("Invalid ISO8601 date: \(string)")
    }
}
