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
    }

    public func upsertPaper(_ paper: Paper) throws {
        try database.run("""
        INSERT INTO papers (id, file_path, file_hash, title, authors_json, year, source_url, imported_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          file_path = excluded.file_path,
          file_hash = excluded.file_hash,
          title = excluded.title,
          authors_json = excluded.authors_json,
          year = excluded.year,
          source_url = excluded.source_url,
          updated_at = excluded.updated_at;
        """, bindings: [
            .text(paper.id),
            .text(paper.filePath),
            .text(paper.fileHash),
            .text(paper.title),
            .text(try jsonString(paper.authors)),
            paper.year.map(SQLiteValue.int) ?? .null,
            paper.sourceURL.map(SQLiteValue.text) ?? .null,
            .text(dates.string(from: paper.importedAt)),
            .text(dates.string(from: paper.updatedAt))
        ])
    }

    public func fetchPapers() throws -> [Paper] {
        try database.query("""
        SELECT id, file_path, file_hash, title, authors_json, year, source_url, imported_at, updated_at
        FROM papers ORDER BY title, id;
        """) { row in
            Paper(
                id: try row.text(0),
                filePath: try row.text(1),
                fileHash: try row.text(2),
                title: try row.text(3),
                authors: try decode([String].self, from: try row.text(4)),
                year: row.optionalInt(5),
                sourceURL: row.optionalText(6),
                importedAt: try date(from: try row.text(7)),
                updatedAt: try date(from: try row.text(8))
            )
        }
    }

    public func upsertCategory(_ category: Category) throws {
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
        try database.run("""
        INSERT INTO tags (id, name) VALUES (?, ?)
        ON CONFLICT(id) DO UPDATE SET name = excluded.name;
        """, bindings: [.text(tag.id), .text(tag.name)])
    }

    public func fetchTags() throws -> [PaperTag] {
        try database.query("SELECT id, name FROM tags ORDER BY name, id;") { row in
            PaperTag(id: try row.text(0), name: try row.text(1))
        }
    }

    public func assignPaper(_ paperID: String, toCategory categoryID: String) throws {
        try database.run("""
        INSERT OR IGNORE INTO paper_categories (paper_id, category_id) VALUES (?, ?);
        """, bindings: [.text(paperID), .text(categoryID)])
    }

    public func removePaper(_ paperID: String, fromCategory categoryID: String) throws {
        try database.run("""
        DELETE FROM paper_categories WHERE paper_id = ? AND category_id = ?;
        """, bindings: [.text(paperID), .text(categoryID)])
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
