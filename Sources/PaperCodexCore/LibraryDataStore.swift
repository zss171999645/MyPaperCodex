import Foundation

public final class LibraryDataStore {
    private let database: SQLiteDatabase
    private let dates = ISO8601DateFormatter()

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func upsertFolder(_ folder: LibraryFolder) throws {
        try database.run("""
        INSERT INTO folders (id, parent_id, name, sort_order, deleted_at, sync_revision)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          parent_id = excluded.parent_id,
          name = excluded.name,
          sort_order = excluded.sort_order,
          deleted_at = excluded.deleted_at,
          sync_revision = excluded.sync_revision;
        """, bindings: [
            .text(folder.id),
            folder.parentID.map(SQLiteValue.text) ?? .null,
            .text(folder.name),
            .int(folder.sortOrder),
            folder.deletedAt.map { .text(dates.string(from: $0)) } ?? .null,
            .int(folder.syncRevision)
        ])
    }

    public func fetchFolders() throws -> [LibraryFolder] {
        try database.query("""
        SELECT id, parent_id, name, sort_order, deleted_at, sync_revision
        FROM folders ORDER BY sort_order, name, id;
        """) { row in
            LibraryFolder(
                id: try row.text(0),
                parentID: row.optionalText(1),
                name: try row.text(2),
                sortOrder: row.int(3),
                deletedAt: try row.optionalText(4).map { try date(from: $0) },
                syncRevision: row.int(5)
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
        FROM tags ORDER BY sort_order, name, id;
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
        try database.run("""
        INSERT INTO paper_tags (paper_id, tag_id) VALUES (?, ?)
        ON CONFLICT(paper_id, tag_id) DO NOTHING;
        """, bindings: [
            .text(paperID),
            .text(tagID)
        ])
        _ = date
    }

    public func fetchFolderIDs(forPaperID paperID: String) throws -> [String] {
        try database.query("""
        SELECT folder_id FROM paper_folders
        WHERE paper_id = ? AND deleted_at IS NULL
        ORDER BY folder_id;
        """, bindings: [.text(paperID)]) { row in
            try row.text(0)
        }
    }

    public func fetchTagIDs(forPaperID paperID: String) throws -> [String] {
        try database.query("""
        SELECT tag_id FROM paper_tags WHERE paper_id = ? ORDER BY tag_id;
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
}
