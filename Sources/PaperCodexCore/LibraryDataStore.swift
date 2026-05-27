import Foundation

public final class LibraryDataStore {
    private let database: SQLiteDatabase
    private let dates = ISO8601DateFormatter()

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func upsertFolder(_ folder: LibraryFolder) throws {
        try database.run("""
        INSERT INTO folders (id, parent_id, name, sort_order, is_pinned, deleted_at, sync_revision)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          parent_id = excluded.parent_id,
          name = excluded.name,
          sort_order = excluded.sort_order,
          is_pinned = excluded.is_pinned,
          deleted_at = excluded.deleted_at,
          sync_revision = excluded.sync_revision;
        """, bindings: [
            .text(folder.id),
            folder.parentID.map(SQLiteValue.text) ?? .null,
            .text(folder.name),
            .int(folder.sortOrder),
            .int(folder.isPinned ? 1 : 0),
            folder.deletedAt.map { .text(dates.string(from: $0)) } ?? .null,
            .int(folder.syncRevision)
        ])
    }

    public func fetchFolders() throws -> [LibraryFolder] {
        try database.query("""
        SELECT id, parent_id, name, sort_order, is_pinned, deleted_at, sync_revision
        FROM folders
        WHERE deleted_at IS NULL
        ORDER BY is_pinned DESC, sort_order, name, id;
        """) { row in
            LibraryFolder(
                id: try row.text(0),
                parentID: row.optionalText(1),
                name: try row.text(2),
                sortOrder: row.int(3),
                isPinned: row.int(4) != 0,
                deletedAt: try row.optionalText(5).map { try date(from: $0) },
                syncRevision: row.int(6)
            )
        }
    }

    public func upsertTag(_ tag: HierarchicalPaperTag) throws {
        try database.run("""
        INSERT INTO tags (id, name, parent_id, color, sort_order, deleted_at, sync_revision)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          name = excluded.name,
          parent_id = excluded.parent_id,
          color = excluded.color,
          sort_order = excluded.sort_order,
          deleted_at = excluded.deleted_at,
          sync_revision = excluded.sync_revision;
        """, bindings: [
            .text(tag.id),
            .text(tag.name),
            tag.parentID.map(SQLiteValue.text) ?? .null,
            tag.color.map(SQLiteValue.text) ?? .null,
            .int(tag.sortOrder),
            tag.deletedAt.map { .text(dates.string(from: $0)) } ?? .null,
            .int(tag.syncRevision)
        ])
    }

    public func fetchTags() throws -> [HierarchicalPaperTag] {
        try database.query("""
        SELECT id, parent_id, name, color, sort_order, deleted_at, sync_revision
        FROM tags
        WHERE deleted_at IS NULL
        ORDER BY sort_order, name, id;
        """) { row in
            HierarchicalPaperTag(
                id: try row.text(0),
                parentID: row.optionalText(1),
                name: try row.text(2),
                color: row.optionalText(3),
                sortOrder: row.int(4),
                deletedAt: try row.optionalText(5).map { try date(from: $0) },
                syncRevision: row.int(6)
            )
        }
    }

    public func assignPaper(_ paperID: String, toFolder folderID: String, at date: Date) throws {
        try database.run("""
        INSERT INTO paper_folders (paper_id, folder_id, created_at, deleted_at)
        VALUES (?, ?, ?, NULL)
        ON CONFLICT(paper_id, folder_id) DO UPDATE SET deleted_at = NULL;
        """, bindings: [
            .text(paperID),
            .text(folderID),
            .text(dates.string(from: date))
        ])
    }

    public func assignPaper(_ paperID: String, toTag tagID: String, at date: Date) throws {
        try ensureTagMembershipStorage()
        try database.transaction {
            try database.run("""
            INSERT INTO paper_tags (paper_id, tag_id) VALUES (?, ?)
            ON CONFLICT(paper_id, tag_id) DO NOTHING;
            """, bindings: [
                .text(paperID),
                .text(tagID)
            ])
            try database.run("""
            INSERT INTO paper_tag_memberships (paper_id, tag_id, created_at, deleted_at)
            VALUES (?, ?, ?, NULL)
            ON CONFLICT(paper_id, tag_id) DO UPDATE SET
              created_at = CASE
                WHEN paper_tag_memberships.created_at = '' THEN excluded.created_at
                ELSE paper_tag_memberships.created_at
              END,
              deleted_at = NULL;
            """, bindings: [
                .text(paperID),
                .text(tagID),
                .text(dates.string(from: date))
            ])
        }
    }

    public func fetchFolderIDs(forPaperID paperID: String) throws -> [String] {
        try database.query("""
        SELECT paper_folders.folder_id
        FROM paper_folders
        JOIN folders ON folders.id = paper_folders.folder_id
        WHERE paper_folders.paper_id = ?
          AND paper_folders.deleted_at IS NULL
          AND folders.deleted_at IS NULL
        ORDER BY paper_folders.folder_id;
        """, bindings: [.text(paperID)]) { row in
            try row.text(0)
        }
    }

    public func fetchTagIDs(forPaperID paperID: String) throws -> [String] {
        try ensureTagMembershipStorage()
        return try database.query("""
        SELECT paper_tag_memberships.tag_id
        FROM paper_tag_memberships
        JOIN paper_tags ON paper_tags.paper_id = paper_tag_memberships.paper_id
          AND paper_tags.tag_id = paper_tag_memberships.tag_id
        JOIN tags ON tags.id = paper_tag_memberships.tag_id
        WHERE paper_tag_memberships.paper_id = ?
          AND paper_tag_memberships.deleted_at IS NULL
          AND tags.deleted_at IS NULL
        ORDER BY paper_tag_memberships.tag_id;
        """, bindings: [.text(paperID)]) { row in
            try row.text(0)
        }
    }

    public func upsertNote(_ note: PaperNote) throws {
        try database.run("""
        INSERT INTO paper_notes (id, paper_id, anchor_id, title, body_markdown, created_at, updated_at, deleted_at, sync_revision)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          anchor_id = excluded.anchor_id,
          title = excluded.title,
          body_markdown = excluded.body_markdown,
          updated_at = excluded.updated_at,
          deleted_at = excluded.deleted_at,
          sync_revision = excluded.sync_revision;
        """, bindings: [
            .text(note.id),
            .text(note.paperID),
            note.anchorID.map(SQLiteValue.text) ?? .null,
            .text(note.title),
            .text(note.bodyMarkdown),
            .text(dates.string(from: note.createdAt)),
            .text(dates.string(from: note.updatedAt)),
            note.deletedAt.map { .text(dates.string(from: $0)) } ?? .null,
            .int(note.syncRevision)
        ])
    }

    public func fetchNotes(paperID: String) throws -> [PaperNote] {
        try database.query("""
        SELECT id, paper_id, anchor_id, title, body_markdown, created_at, updated_at, deleted_at, sync_revision
        FROM paper_notes
        WHERE paper_id = ? AND deleted_at IS NULL
        ORDER BY updated_at, id;
        """, bindings: [.text(paperID)]) { row in
            PaperNote(
                id: try row.text(0),
                paperID: try row.text(1),
                anchorID: row.optionalText(2),
                title: try row.text(3),
                bodyMarkdown: try row.text(4),
                createdAt: try date(from: try row.text(5)),
                updatedAt: try date(from: try row.text(6)),
                deletedAt: try row.optionalText(7).map { try date(from: $0) },
                syncRevision: row.int(8)
            )
        }
    }

    private func date(from string: String) throws -> Date {
        guard let date = dates.date(from: string) else {
            throw PaperRepositoryError.decodingFailed("Invalid ISO8601 date: \(string)")
        }
        return date
    }

    private func ensureTagMembershipStorage() throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS paper_tag_memberships (
          paper_id TEXT NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
          tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
          created_at TEXT NOT NULL,
          deleted_at TEXT,
          PRIMARY KEY (paper_id, tag_id)
        );
        """)
        try database.run("""
        INSERT OR IGNORE INTO paper_tag_memberships (paper_id, tag_id, created_at, deleted_at)
        SELECT paper_tags.paper_id, paper_tags.tag_id, papers.imported_at, NULL
        FROM paper_tags
        JOIN papers ON papers.id = paper_tags.paper_id;
        """)
    }
}
