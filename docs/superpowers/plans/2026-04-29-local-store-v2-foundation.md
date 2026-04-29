# Local Store V2 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the local storage foundation for Paper Codex's offline-first data backend redesign without changing current UI behavior.

**Architecture:** Add Local Store V2 beside the current repository tables, backfill current papers/categories/tags into V2 tables, and expose focused store modules for files, arXiv cache metadata, notes/annotations, and sync bookkeeping. Keep `PaperRepository` compatibility intact so the existing app continues to run while later plans add Keychain credentials, login, remote sync, and UI controls.

**Tech Stack:** Swift 6.2, Foundation, SQLite through `SQLiteDatabase`, existing `PaperCodexCoreChecks`, existing `PaperRepository` migration path.

---

## Scope

This plan implements Phase 1 from `docs/superpowers/specs/2026-04-29-paper-codex-data-backend-redesign.md`: Local Store V2. It does not implement product API login, remote sync transport, Keychain storage, UI settings, or EdgeOne deployment. Those need separate plans after this foundation is merged.

## File Map

- Create `Sources/PaperCodexCore/LocalStoreV2Models.swift`: V2 model structs and enums.
- Create `Sources/PaperCodexCore/LocalStoreV2Migrator.swift`: SQLite schema creation and backfill from current tables.
- Create `Sources/PaperCodexCore/LibraryDataStore.swift`: focused accessors for V2 papers, files, sources, folders, tags, notes, and annotations.
- Create `Sources/PaperCodexCore/ArxivCacheDataStore.swift`: database-backed arXiv feed/cache status accessors.
- Create `Sources/PaperCodexCore/SyncDataStore.swift`: local sync entity, outbox, and cursor accessors.
- Modify `Sources/PaperCodexCore/SQLiteDatabase.swift`: add transactions and table-column introspection.
- Modify `Sources/PaperCodexCore/PaperRepository.swift`: call Local Store V2 migration during existing migration.
- Modify `Sources/PaperCodexCoreChecks/main.swift`: add Local Store V2 checks while preserving existing checks.

---

### Task 1: V2 Models

**Files:**
- Create: `Sources/PaperCodexCore/LocalStoreV2Models.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] **Step 1: Add failing model round-trip checks**

Append this function near `runModelsChecks()` in `Sources/PaperCodexCoreChecks/main.swift`:

```swift
func runLocalStoreV2ModelChecks() throws {
    let now = Date(timeIntervalSince1970: 1_777_300_000)
    let file = PaperFileRecord(
        id: "file-a",
        paperID: "paper-a",
        storageState: .savedLocal,
        localPath: "/tmp/paper-a/original.pdf",
        contentHash: "hash-a",
        byteCount: 42,
        mimeType: "application/pdf",
        remoteFileID: nil,
        encryptionState: .none,
        createdAt: now,
        updatedAt: now
    )
    let source = PaperSourceRecord(
        id: "source-a",
        paperID: "paper-a",
        sourceType: .arxiv,
        sourceID: "2604.18586",
        url: "https://arxiv.org/abs/2604.18586",
        version: "v1",
        metadataJSON: #"{"primary_category":"cs.CV"}"#,
        createdAt: now
    )
    let note = PaperNote(
        id: "note-a",
        paperID: "paper-a",
        anchorID: nil,
        title: "Reading note",
        bodyMarkdown: "Important limitation.",
        createdAt: now,
        updatedAt: now,
        deletedAt: nil,
        syncRevision: 1
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    try check(try decoder.decode(PaperFileRecord.self, from: encoder.encode(file)) == file, "paper file record should JSON round-trip")
    try check(try decoder.decode(PaperSourceRecord.self, from: encoder.encode(source)) == source, "paper source record should JSON round-trip")
    try check(try decoder.decode(PaperNote.self, from: encoder.encode(note)) == note, "paper note should JSON round-trip")
    try check(PaperStorageState.feedPDFCache.rawValue == "feed_pdf_cache", "feed PDF cache state should be stable")
}
```

Call it from `main` next to the other checks:

```swift
try runLocalStoreV2ModelChecks()
```

- [ ] **Step 2: Run check to verify it fails**

Run:

```bash
swift run PaperCodexCoreChecks
```

Expected: compile failure naming missing types such as `PaperFileRecord`, `PaperSourceRecord`, and `PaperNote`.

- [ ] **Step 3: Add V2 model definitions**

Create `Sources/PaperCodexCore/LocalStoreV2Models.swift`:

```swift
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
}

public struct PaperDevice: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var remoteDeviceID: String?
    public var name: String
    public var publicKey: String?
    public var createdAt: Date
    public var revokedAt: Date?
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
}

public struct LibraryFolder: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var parentID: String?
    public var name: String
    public var sortOrder: Int
    public var deletedAt: Date?
    public var syncRevision: Int
}

public struct HierarchicalPaperTag: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var parentID: String?
    public var name: String
    public var color: String?
    public var sortOrder: Int
    public var deletedAt: Date?
    public var syncRevision: Int
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
}
```

- [ ] **Step 4: Run check to verify models pass**

Run:

```bash
swift run PaperCodexCoreChecks
```

Expected: all existing checks pass, including the new model checks.

- [ ] **Step 5: Commit**

```bash
git add Sources/PaperCodexCore/LocalStoreV2Models.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: add local store v2 models"
```

---

### Task 2: SQLite Transaction Helpers

**Files:**
- Modify: `Sources/PaperCodexCore/SQLiteDatabase.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] **Step 1: Add failing SQLite helper checks**

Add this to `Sources/PaperCodexCoreChecks/main.swift` near the repository checks:

```swift
func runSQLiteHelperChecks() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-sqlite-helpers-\(UUID().uuidString).sqlite")
    let database = try SQLiteDatabase(path: databaseURL.path)
    try database.transaction {
        try database.execute("CREATE TABLE sample (id TEXT PRIMARY KEY, value TEXT);")
        try database.run("INSERT INTO sample (id, value) VALUES (?, ?);", bindings: [.text("a"), .text("one")])
    }
    let columns = try database.tableColumns("sample")
    let values = try database.query("SELECT value FROM sample WHERE id = ?;", bindings: [.text("a")]) { row in
        try row.text(0)
    }
    try check(columns == Set(["id", "value"]), "SQLite tableColumns should read table schema")
    try check(values == ["one"], "SQLite transaction should commit successful work")
}
```

Call it from `main`:

```swift
try runSQLiteHelperChecks()
```

- [ ] **Step 2: Run check to verify it fails**

Run:

```bash
swift run PaperCodexCoreChecks
```

Expected: compile failure for missing `transaction` and `tableColumns`.

- [ ] **Step 3: Implement helpers**

Add these methods to `SQLiteDatabase` after `query`:

```swift
public func transaction<T>(_ body: () throws -> T) throws -> T {
    try execute("BEGIN IMMEDIATE TRANSACTION;")
    do {
        let value = try body()
        try execute("COMMIT;")
        return value
    } catch {
        try? execute("ROLLBACK;")
        throw error
    }
}

public func tableColumns(_ tableName: String) throws -> Set<String> {
    let safeName = tableName.filter { character in
        character.isLetter || character.isNumber || character == "_"
    }
    guard safeName == tableName, !safeName.isEmpty else {
        throw SQLiteStoreError.prepareFailed(sql: "PRAGMA table_info", message: "Unsafe table name \(tableName)")
    }
    let columns = try query("PRAGMA table_info(\(safeName));") { row in
        try row.text(1)
    }
    return Set(columns)
}
```

- [ ] **Step 4: Run check to verify helpers pass**

Run:

```bash
swift run PaperCodexCoreChecks
```

Expected: all checks pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PaperCodexCore/SQLiteDatabase.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: add sqlite migration helpers"
```

---

### Task 3: Local Store V2 Migration

**Files:**
- Create: `Sources/PaperCodexCore/LocalStoreV2Migrator.swift`
- Modify: `Sources/PaperCodexCore/PaperRepository.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] **Step 1: Add failing migration checks**

Add this check after `runRepositoryChecks()`:

```swift
func runLocalStoreV2MigrationChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-local-store-v2-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let repository = try PaperRepository(databasePath: tempRoot.appendingPathComponent("store.sqlite").path)
    try repository.migrate()

    let now = Date(timeIntervalSince1970: 1_777_300_000)
    let paper = Paper(
        id: "paper-a",
        filePath: tempRoot.appendingPathComponent("paper-a/original.pdf").path,
        fileHash: "hash-a",
        title: "Paper A",
        authors: ["Alice"],
        year: 2026,
        sourceURL: "https://arxiv.org/abs/2604.18586",
        importedAt: now,
        updatedAt: now
    )
    try repository.upsertPaper(paper)
    try repository.upsertCategory(Category(id: "cat-methods", parentID: nil, name: "Methods", sortOrder: 1))
    try repository.upsertCategory(Category(id: "cat-vae", parentID: "cat-methods", name: "VAE", sortOrder: 2))
    try repository.upsertTag(PaperTag(id: "tag-diffusion", name: "Diffusion"))
    try repository.assignPaper("paper-a", toCategory: "cat-vae")
    try repository.assignPaper("paper-a", toTag: "tag-diffusion")

    try repository.migrate()
    let database = try SQLiteDatabase(path: tempRoot.appendingPathComponent("store.sqlite").path)
    let paperColumns = try database.tableColumns("papers")
    let folders = try database.query("SELECT id, parent_id, name FROM folders ORDER BY sort_order, name;") { row in
        "\(try row.text(0))|\(row.optionalText(1) ?? "")|\(try row.text(2))"
    }
    let fileRows = try database.query("SELECT paper_id, storage_state, local_path, content_hash FROM paper_files;") { row in
        "\(try row.text(0))|\(try row.text(1))|\(try row.text(2))|\(try row.text(3))"
    }
    let sources = try database.query("SELECT paper_id, source_type, source_id, url FROM paper_sources;") { row in
        "\(try row.text(0))|\(try row.text(1))|\(row.optionalText(2) ?? "")|\(row.optionalText(3) ?? "")"
    }

    try check(paperColumns.contains("canonical_key"), "V2 migration should add canonical paper columns")
    try check(folders == ["cat-methods||Methods", "cat-vae|cat-methods|VAE"], "V2 migration should backfill folders from categories")
    try check(fileRows == ["paper-a|saved_local|\(paper.filePath)|hash-a"], "V2 migration should backfill paper file records")
    try check(sources == ["paper-a|arxiv|2604.18586|https://arxiv.org/abs/2604.18586"], "V2 migration should backfill arXiv source records")
}
```

Call it from `main`:

```swift
try runLocalStoreV2MigrationChecks()
```

- [ ] **Step 2: Run check to verify it fails**

Run:

```bash
swift run PaperCodexCoreChecks
```

Expected: failure because `folders`, `paper_files`, and `paper_sources` do not exist.

- [ ] **Step 3: Implement migrator**

Create `Sources/PaperCodexCore/LocalStoreV2Migrator.swift`:

```swift
import Foundation

public enum LocalStoreV2Migrator {
    public static func migrate(database: SQLiteDatabase) throws {
        try database.transaction {
            try createTables(database: database)
            try addPaperColumns(database: database)
            try addTagColumns(database: database)
            try backfillFolders(database: database)
            try backfillPaperFiles(database: database)
            try backfillPaperSources(database: database)
        }
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

    private static func addPaperColumns(database: SQLiteDatabase) throws {
        let columns = try database.tableColumns("papers")
        let additions: [(String, String)] = [
            ("canonical_key", "TEXT"),
            ("abstract", "TEXT"),
            ("source_kind", "TEXT"),
            ("arxiv_id", "TEXT"),
            ("arxiv_id_versioned", "TEXT"),
            ("doi", "TEXT"),
            ("deleted_at", "TEXT"),
            ("sync_revision", "INTEGER NOT NULL DEFAULT 0")
        ]
        for (name, definition) in additions where !columns.contains(name) {
            try database.execute("ALTER TABLE papers ADD COLUMN \(name) \(definition);")
        }
        try database.run("""
        UPDATE papers
        SET canonical_key = COALESCE(canonical_key, file_hash),
            source_kind = CASE
              WHEN source_url LIKE 'https://arxiv.org/%' THEN 'arxiv'
              WHEN source_url IS NOT NULL THEN 'url'
              ELSE COALESCE(source_kind, 'manual')
            END,
            sync_revision = COALESCE(sync_revision, 0)
        WHERE canonical_key IS NULL OR source_kind IS NULL;
        """)
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

    private static func backfillFolders(database: SQLiteDatabase) throws {
        try database.run("""
        INSERT OR IGNORE INTO folders (id, parent_id, name, sort_order, deleted_at, sync_revision)
        SELECT id, parent_id, name, sort_order, NULL, 0 FROM categories;
        """)
        try database.run("""
        INSERT OR IGNORE INTO paper_folders (paper_id, folder_id, created_at, deleted_at)
        SELECT paper_id, category_id, '', NULL FROM paper_categories;
        """)
    }

    private static func backfillPaperFiles(database: SQLiteDatabase) throws {
        try database.run("""
        INSERT OR IGNORE INTO paper_files (
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
        FROM papers;
        """)
    }

    private static func backfillPaperSources(database: SQLiteDatabase) throws {
        try database.run("""
        INSERT OR IGNORE INTO paper_sources (id, paper_id, source_type, source_id, url, version, metadata_json, created_at)
        SELECT
          'source:' || id || ':primary',
          id,
          CASE
            WHEN source_url LIKE 'https://arxiv.org/%' THEN 'arxiv'
            WHEN source_url IS NOT NULL THEN 'url'
            ELSE 'manual'
          END,
          CASE
            WHEN source_url LIKE 'https://arxiv.org/abs/%' THEN replace(source_url, 'https://arxiv.org/abs/', '')
            WHEN source_url LIKE 'https://arxiv.org/pdf/%' THEN replace(replace(source_url, 'https://arxiv.org/pdf/', ''), '.pdf', '')
            ELSE NULL
          END,
          source_url,
          NULL,
          NULL,
          imported_at
        FROM papers
        WHERE source_url IS NOT NULL;
        """)
    }
}
```

- [ ] **Step 4: Wire migrator into existing repository migration**

At the end of `PaperRepository.migrate()` after current `is_saved` column compatibility code, add:

```swift
try LocalStoreV2Migrator.migrate(database: database)
```

- [ ] **Step 5: Run checks**

Run:

```bash
swift run PaperCodexCoreChecks
```

Expected: all checks pass, including migration backfill.

- [ ] **Step 6: Commit**

```bash
git add Sources/PaperCodexCore/LocalStoreV2Migrator.swift Sources/PaperCodexCore/PaperRepository.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: add local store v2 migration"
```

---

### Task 4: Library Data Store Accessors

**Files:**
- Create: `Sources/PaperCodexCore/LibraryDataStore.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] **Step 1: Add failing data-store checks**

Add this function:

```swift
func runLibraryDataStoreChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-library-store-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let repository = try PaperRepository(databasePath: tempRoot.appendingPathComponent("store.sqlite").path)
    try repository.migrate()
    let database = try SQLiteDatabase(path: tempRoot.appendingPathComponent("store.sqlite").path)
    let store = LibraryDataStore(database: database)
    let now = Date(timeIntervalSince1970: 1_777_300_000)

    let folder = LibraryFolder(id: "folder-root", parentID: nil, name: "Root", sortOrder: 0, deletedAt: nil, syncRevision: 1)
    let tag = HierarchicalPaperTag(id: "tag-ai", parentID: nil, name: "AI", color: "#0A84FF", sortOrder: 0, deletedAt: nil, syncRevision: 1)
    let note = PaperNote(id: "note-a", paperID: "paper-a", anchorID: nil, title: "Idea", bodyMarkdown: "Use in intro.", createdAt: now, updatedAt: now, deletedAt: nil, syncRevision: 1)
    try store.upsertFolder(folder)
    try store.upsertTag(tag)
    try repository.upsertPaper(Paper(id: "paper-a", filePath: "/tmp/a.pdf", fileHash: "hash-a", title: "A", authors: [], year: nil, sourceURL: nil, importedAt: now, updatedAt: now))
    try store.assignPaper("paper-a", toFolder: "folder-root", at: now)
    try store.assignPaper("paper-a", toTag: "tag-ai", at: now)
    try store.upsertNote(note)

    try check(try store.fetchFolders() == [folder], "LibraryDataStore should round-trip folders")
    try check(try store.fetchTags() == [tag], "LibraryDataStore should round-trip hierarchical tags")
    try check(try store.fetchFolderIDs(forPaperID: "paper-a") == ["folder-root"], "LibraryDataStore should round-trip folder memberships")
    try check(try store.fetchTagIDs(forPaperID: "paper-a") == ["tag-ai"], "LibraryDataStore should round-trip tag memberships")
    try check(try store.fetchNotes(paperID: "paper-a") == [note], "LibraryDataStore should round-trip paper notes")
}
```

Call it from `main`:

```swift
try runLibraryDataStoreChecks()
```

- [ ] **Step 2: Run check to verify it fails**

Run:

```bash
swift run PaperCodexCoreChecks
```

Expected: compile failure for missing `LibraryDataStore`.

- [ ] **Step 3: Implement LibraryDataStore**

Create `Sources/PaperCodexCore/LibraryDataStore.swift` with focused methods for folders, hierarchical tags, memberships, and notes:

```swift
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
        try database.query("SELECT id, parent_id, name, sort_order, deleted_at, sync_revision FROM folders ORDER BY sort_order, name, id;") { row in
            LibraryFolder(
                id: try row.text(0),
                parentID: row.optionalText(1),
                name: try row.text(2),
                sortOrder: row.int(3),
                deletedAt: try row.optionalText(4).map(date),
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
        try database.query("SELECT id, parent_id, name, color, sort_order, deleted_at, sync_revision FROM tags ORDER BY sort_order, name, id;") { row in
            HierarchicalPaperTag(
                id: try row.text(0),
                parentID: row.optionalText(1),
                name: try row.text(2),
                color: row.optionalText(3),
                sortOrder: row.int(4),
                deletedAt: try row.optionalText(5).map(date),
                syncRevision: row.int(6)
            )
        }
    }

    public func assignPaper(_ paperID: String, toFolder folderID: String, at date: Date) throws {
        try database.run("""
        INSERT INTO paper_folders (paper_id, folder_id, created_at, deleted_at)
        VALUES (?, ?, ?, NULL)
        ON CONFLICT(paper_id, folder_id) DO UPDATE SET deleted_at = NULL;
        """, bindings: [.text(paperID), .text(folderID), .text(dates.string(from: date))])
    }

    public func assignPaper(_ paperID: String, toTag tagID: String, at date: Date) throws {
        try database.run("""
        INSERT INTO paper_tags (paper_id, tag_id) VALUES (?, ?)
        ON CONFLICT(paper_id, tag_id) DO NOTHING;
        """, bindings: [.text(paperID), .text(tagID)])
        _ = date
    }

    public func fetchFolderIDs(forPaperID paperID: String) throws -> [String] {
        try database.query("SELECT folder_id FROM paper_folders WHERE paper_id = ? AND deleted_at IS NULL ORDER BY folder_id;", bindings: [.text(paperID)]) { row in
            try row.text(0)
        }
    }

    public func fetchTagIDs(forPaperID paperID: String) throws -> [String] {
        try database.query("SELECT tag_id FROM paper_tags WHERE paper_id = ? ORDER BY tag_id;", bindings: [.text(paperID)]) { row in
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
        FROM paper_notes WHERE paper_id = ? AND deleted_at IS NULL ORDER BY updated_at, id;
        """, bindings: [.text(paperID)]) { row in
            PaperNote(
                id: try row.text(0),
                paperID: try row.text(1),
                anchorID: row.optionalText(2),
                title: try row.text(3),
                bodyMarkdown: try row.text(4),
                createdAt: try date(from: try row.text(5)),
                updatedAt: try date(from: try row.text(6)),
                deletedAt: try row.optionalText(7).map(date),
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
```

- [ ] **Step 4: Run checks**

Run:

```bash
swift run PaperCodexCoreChecks
```

Expected: all checks pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PaperCodexCore/LibraryDataStore.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: add library data store"
```

---

### Task 5: arXiv Cache Data Store

**Files:**
- Create: `Sources/PaperCodexCore/ArxivCacheDataStore.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] **Step 1: Add failing cache-store checks**

Add:

```swift
func runArxivCacheDataStoreChecks() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-arxiv-cache-store-\(UUID().uuidString).sqlite")
    let repository = try PaperRepository(databasePath: databaseURL.path)
    try repository.migrate()
    let database = try SQLiteDatabase(path: databaseURL.path)
    let store = ArxivCacheDataStore(database: database)
    let now = Date(timeIntervalSince1970: 1_777_300_000)
    try store.upsertFeedDate(date: "2026-04-29", source: "codearxiv", feedVersion: "v1", filterSnapshotJSON: #"{"tags":[]}"#, cachedAt: now, expiresAt: nil)
    try store.upsertPDFCache(arxivID: "2604.18586", date: "2026-04-29", localPath: "/cache/2604.18586.pdf", contentHash: "hash-pdf", byteCount: 123, cachedAt: now, lastAccessedAt: now, promotedPaperID: nil)
    let status = try store.feedCacheStatus(date: "2026-04-29")
    try check(status.metadataCached, "arXiv cache store should report metadata cache")
    try check(status.cachedPDFCount == 1, "arXiv cache store should count cached PDFs")
}
```

Call it from `main`:

```swift
try runArxivCacheDataStoreChecks()
```

- [ ] **Step 2: Run check to verify it fails**

Run:

```bash
swift run PaperCodexCoreChecks
```

Expected: compile failure for missing `ArxivCacheDataStore`.

- [ ] **Step 3: Implement arXiv cache store**

Create `Sources/PaperCodexCore/ArxivCacheDataStore.swift`:

```swift
import Foundation

public struct ArxivFeedCacheStatus: Equatable, Sendable {
    public var date: String
    public var metadataCached: Bool
    public var cachedAssetCount: Int
    public var cachedPDFCount: Int
}

public final class ArxivCacheDataStore {
    private let database: SQLiteDatabase
    private let dates = ISO8601DateFormatter()

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func upsertFeedDate(date: String, source: String, feedVersion: String?, filterSnapshotJSON: String?, cachedAt: Date, expiresAt: Date?) throws {
        try database.run("""
        INSERT INTO arxiv_feed_dates (date, source, feed_version, filter_snapshot_json, cached_at, expires_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(date) DO UPDATE SET
          source = excluded.source,
          feed_version = excluded.feed_version,
          filter_snapshot_json = excluded.filter_snapshot_json,
          cached_at = excluded.cached_at,
          expires_at = excluded.expires_at;
        """, bindings: [
            .text(date),
            .text(source),
            feedVersion.map(SQLiteValue.text) ?? .null,
            filterSnapshotJSON.map(SQLiteValue.text) ?? .null,
            .text(dates.string(from: cachedAt)),
            expiresAt.map { .text(dates.string(from: $0)) } ?? .null
        ])
    }

    public func upsertPDFCache(arxivID: String, date: String, localPath: String, contentHash: String?, byteCount: Int64?, cachedAt: Date, lastAccessedAt: Date?, promotedPaperID: String?) throws {
        try database.run("""
        INSERT INTO arxiv_pdf_cache (arxiv_id, date, local_path, content_hash, byte_count, cached_at, last_accessed_at, promoted_paper_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(arxiv_id) DO UPDATE SET
          date = excluded.date,
          local_path = excluded.local_path,
          content_hash = excluded.content_hash,
          byte_count = excluded.byte_count,
          cached_at = excluded.cached_at,
          last_accessed_at = excluded.last_accessed_at,
          promoted_paper_id = excluded.promoted_paper_id;
        """, bindings: [
            .text(arxivID),
            .text(date),
            .text(localPath),
            contentHash.map(SQLiteValue.text) ?? .null,
            byteCount.map(SQLiteValue.int64) ?? .null,
            .text(dates.string(from: cachedAt)),
            lastAccessedAt.map { .text(dates.string(from: $0)) } ?? .null,
            promotedPaperID.map(SQLiteValue.text) ?? .null
        ])
    }

    public func feedCacheStatus(date: String) throws -> ArxivFeedCacheStatus {
        let metadataCount = try database.query("SELECT COUNT(*) FROM arxiv_feed_dates WHERE date = ?;", bindings: [.text(date)]) { row in row.int(0) }.first ?? 0
        let assetCount = try database.query("SELECT COUNT(*) FROM arxiv_assets WHERE date = ? AND local_path IS NOT NULL;", bindings: [.text(date)]) { row in row.int(0) }.first ?? 0
        let pdfCount = try database.query("SELECT COUNT(*) FROM arxiv_pdf_cache WHERE date = ?;", bindings: [.text(date)]) { row in row.int(0) }.first ?? 0
        return ArxivFeedCacheStatus(date: date, metadataCached: metadataCount > 0, cachedAssetCount: assetCount, cachedPDFCount: pdfCount)
    }
}
```

- [ ] **Step 4: Run checks**

Run:

```bash
swift run PaperCodexCoreChecks
```

Expected: all checks pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PaperCodexCore/ArxivCacheDataStore.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: add arxiv cache data store"
```

---

### Task 6: Sync Store Foundation

**Files:**
- Create: `Sources/PaperCodexCore/SyncDataStore.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] **Step 1: Add failing sync-store checks**

Add:

```swift
func runSyncDataStoreChecks() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-sync-store-\(UUID().uuidString).sqlite")
    let repository = try PaperRepository(databasePath: databaseURL.path)
    try repository.migrate()
    let store = SyncDataStore(database: try SQLiteDatabase(path: databaseURL.path))
    let now = Date(timeIntervalSince1970: 1_777_300_000)
    try store.markDirty(entityType: "paper", entityID: "paper-a", localRevision: 2, deleted: false, at: now)
    try store.enqueue(id: "change-a", entityType: "paper", entityID: "paper-a", operation: "upsert", payloadJSON: #"{"id":"paper-a"}"#, baseRemoteRevision: nil, createdAt: now)
    try store.setCursor(scope: "library", cursor: "cursor-1", updatedAt: now)
    try check(try store.fetchDirtyEntityIDs(entityType: "paper") == ["paper-a"], "SyncDataStore should track dirty entities")
    try check(try store.fetchPendingOutboxIDs() == ["change-a"], "SyncDataStore should track pending outbox changes")
    try check(try store.fetchCursor(scope: "library") == "cursor-1", "SyncDataStore should persist cursors")
}
```

Call it from `main`:

```swift
try runSyncDataStoreChecks()
```

- [ ] **Step 2: Run check to verify it fails**

Run:

```bash
swift run PaperCodexCoreChecks
```

Expected: compile failure for missing `SyncDataStore`.

- [ ] **Step 3: Implement sync store**

Create `Sources/PaperCodexCore/SyncDataStore.swift`:

```swift
import Foundation

public final class SyncDataStore {
    private let database: SQLiteDatabase
    private let dates = ISO8601DateFormatter()

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func markDirty(entityType: String, entityID: String, localRevision: Int, deleted: Bool, at date: Date) throws {
        try database.run("""
        INSERT INTO sync_entities (entity_type, entity_id, local_revision, remote_revision, dirty, deleted, last_synced_at)
        VALUES (?, ?, ?, NULL, 1, ?, NULL)
        ON CONFLICT(entity_type, entity_id) DO UPDATE SET
          local_revision = excluded.local_revision,
          dirty = 1,
          deleted = excluded.deleted;
        """, bindings: [.text(entityType), .text(entityID), .int(localRevision), .int(deleted ? 1 : 0)])
        _ = date
    }

    public func enqueue(id: String, entityType: String, entityID: String, operation: String, payloadJSON: String, baseRemoteRevision: Int?, createdAt: Date) throws {
        try database.run("""
        INSERT INTO sync_outbox (id, entity_type, entity_id, operation, payload_json, base_remote_revision, created_at, attempt_count, last_error)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, NULL)
        ON CONFLICT(id) DO NOTHING;
        """, bindings: [
            .text(id),
            .text(entityType),
            .text(entityID),
            .text(operation),
            .text(payloadJSON),
            baseRemoteRevision.map(SQLiteValue.int) ?? .null,
            .text(dates.string(from: createdAt))
        ])
    }

    public func setCursor(scope: String, cursor: String, updatedAt: Date) throws {
        try database.run("""
        INSERT INTO sync_cursors (scope, cursor, updated_at) VALUES (?, ?, ?)
        ON CONFLICT(scope) DO UPDATE SET cursor = excluded.cursor, updated_at = excluded.updated_at;
        """, bindings: [.text(scope), .text(cursor), .text(dates.string(from: updatedAt))])
    }

    public func fetchDirtyEntityIDs(entityType: String) throws -> [String] {
        try database.query("""
        SELECT entity_id FROM sync_entities WHERE entity_type = ? AND dirty = 1 ORDER BY entity_id;
        """, bindings: [.text(entityType)]) { row in
            try row.text(0)
        }
    }

    public func fetchPendingOutboxIDs() throws -> [String] {
        try database.query("SELECT id FROM sync_outbox ORDER BY created_at, id;") { row in
            try row.text(0)
        }
    }

    public func fetchCursor(scope: String) throws -> String? {
        try database.query("SELECT cursor FROM sync_cursors WHERE scope = ? LIMIT 1;", bindings: [.text(scope)]) { row in
            try row.text(0)
        }.first
    }
}
```

- [ ] **Step 4: Run checks**

Run:

```bash
swift run PaperCodexCoreChecks
```

Expected: all checks pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PaperCodexCore/SyncDataStore.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: add local sync data store"
```

---

### Task 7: App Compatibility Verification

**Files:**
- Modify only if a verification failure identifies a real compatibility bug.

- [ ] **Step 1: Run full core checks**

Run:

```bash
swift run PaperCodexCoreChecks
```

Expected: every check prints `pass`, including repository, arxiv-feed, watch, paths, and new Local Store V2 checks.

- [ ] **Step 2: Build the app**

Run:

```bash
swift build
```

Expected: `Build complete!`.

- [ ] **Step 3: Launch current app bundle with the new binary**

Run:

```bash
osascript -e 'tell application id "local.paper-codex.app" to quit' || true
sleep 1
cp .build/arm64-apple-macosx/debug/PaperCodexApp "$HOME/Applications/PaperCodex.app/Contents/MacOS/PaperCodexApp"
open "$HOME/Applications/PaperCodex.app"
```

Expected: Paper Codex opens and the existing library is still visible. If Computer Use is available, use it to confirm Library, Discover, Settings, and Reader still render. If Computer Use still times out on this app, record the timeout and use process/log evidence only for launch health.

- [ ] **Step 4: Check git diff hygiene**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors and only intended files changed.

- [ ] **Step 5: Commit compatibility fixes if needed**

If Step 1-4 required code changes:

```bash
git add Sources/PaperCodexCore Sources/PaperCodexCoreChecks/main.swift
git commit -m "fix: preserve app behavior on local store v2"
```

If no code changes were needed, skip this commit.

---

## Plan Self-Review

- Spec coverage: this plan covers Local App Store, Local Schema V2, arXiv cache tables, notes/annotations tables, sync state tables, and migration/backfill. It intentionally excludes Product API, login, Keychain, remote sync transport, EdgeOne deployment, and UI cache controls because those are separate subsystems.
- Placeholder scan: this plan contains no incomplete markers or unspecified implementation steps.
- Type consistency: model names used in checks match implementation snippets: `PaperFileRecord`, `PaperSourceRecord`, `LibraryFolder`, `HierarchicalPaperTag`, `PaperNote`, `ArxivCacheDataStore`, and `SyncDataStore`.
