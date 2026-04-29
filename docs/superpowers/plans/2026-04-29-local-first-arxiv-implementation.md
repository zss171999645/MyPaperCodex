# Local-First arXiv Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the CodeArXiv-server-backed Discover workflow with direct arXiv fetching, local preferences, local cache fallback, and local-only embedding/enrichment configuration.

**Architecture:** Paper Codex keeps the current SwiftUI Discover/Library/Reader surfaces but moves feed ownership into `PaperCodexCore`. A new local arXiv client parses real arXiv list pages and Atom API responses into the existing `ArxivFeedPaper` model; the app model applies local filters, cache state, and optional similarity ranking before rendering. Settings becomes a local configuration page instead of a CodeArXiv connection page.

**Tech Stack:** Swift 6.2, SwiftUI, URLSession, XMLParser/Foundation XML, SQLite-backed local repository, `PaperCodexCoreChecks`, existing PDFKit import/indexing, existing Codex CLI integration.

---

## File Structure

- Create `Sources/PaperCodexCore/LocalArxivClient.swift`: direct arXiv list-page parsing, Atom API parsing, URL construction, PDF fetching, and `ArxivFeedPaper` mapping.
- Create `Sources/PaperCodexCore/LocalDiscoverPreferences.swift`: local category/filter/embedding/enrichment preference models and persistence helpers that do not store secrets in feed payloads.
- Create `Sources/PaperCodexCore/SimilarityRanker.swift`: CodeArXiv-style vector parsing, mean vector, cosine similarity, whitelist/neutral/blacklist grouping, and deterministic ranking.
- Modify `Sources/PaperCodexCore/ArxivFeed.swift`: remove the assumption that `ArxivFeedClient` means CodeArXiv-only, keep cache models, and add helpers for local arXiv dates/assets where needed.
- Modify `Sources/PaperCodexCoreChecks/main.swift`: add real-fixture checks for list parsing, Atom parsing, similarity ranking, local preferences, and local feed mapping.
- Modify `Sources/PaperCodexApp/AppModel.swift`: replace `makeArxivFeedClient()` usage with local arXiv client methods; remove CodeArXiv user-state refresh/update from the active runtime; add local discover preference setters; preserve cache fallback and open/save behavior.
- Modify `Sources/PaperCodexApp/SettingsView.swift`: remove CodeArXiv base URL/token/username/favorite sync; add sections for arXiv categories, local ranking filters, Codex enrichment toggles, and embedding provider settings.
- Modify `Sources/PaperCodexApp/DiscoverView.swift`: keep the current card grid, date menu, progress strip, and save/open flow; update toolbar text and disabled states for direct arXiv and local-only cache.
- Optionally modify `Sources/PaperCodexCore/PaperRepository.swift` only if local generated summary/user notes fields are added in this batch; otherwise leave repository schema untouched and keep enrichment settings ready for the next batch.

## Task 1: Core Direct arXiv Client

**Files:**
- Create: `Sources/PaperCodexCore/LocalArxivClient.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] **Step 1: Write failing parser checks**

Add `runLocalArxivClientChecks()` to `Sources/PaperCodexCoreChecks/main.swift` using embedded real-shaped HTML and Atom XML fixtures:

```swift
func runLocalArxivClientChecks() throws {
    let listHTML = """
    <html><body>
    <h3>Wed, 29 Apr 2026 (showing first 3 of 3 entries)</h3>
    <dl>
      <dt><a name="item1">[1]</a><a href="/abs/2604.18803">arXiv:2604.18803</a></dt>
      <dt><a name="item2">[2]</a><a href="/abs/2604.18804v2">arXiv:2604.18804v2</a></dt>
      <dt><a name="item3">[3]</a><a href="/abs/2604.18803v2">arXiv:2604.18803v2</a></dt>
    </dl>
    <h3>Tue, 28 Apr 2026 (showing first 1 of 1 entries)</h3>
    </body></html>
    """
    let parsedList = try LocalArxivClient.parseListPage(listHTML)
    try check(parsedList.date == "2026-04-29", "local arXiv list parser should parse newest date heading")
    try check(parsedList.ids == ["2604.18803", "2604.18804"], "local arXiv list parser should dedupe versioned IDs")

    let atomXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:arxiv="http://arxiv.org/schemas/atom">
      <entry>
        <id>http://arxiv.org/abs/2604.18803v1</id>
        <updated>2026-04-29T12:00:00Z</updated>
        <published>2026-04-29T08:00:00Z</published>
        <title>  A Local Paper Reader  </title>
        <summary>  We present a local-first paper reader.  </summary>
        <author><name>Alice Example</name></author>
        <author><name>Bob Example</name></author>
        <arxiv:comment>Code: https://github.com/example/paper-reader</arxiv:comment>
        <arxiv:primary_category term="cs.CL" />
        <category term="cs.CL" />
        <category term="cs.AI" />
      </entry>
    </feed>
    """
    let parsedPapers = try LocalArxivClient.parseAtomFeed(atomXML, listDate: "2026-04-29", listCategoriesByID: ["2604.18803": ["cs.CL"]])
    try check(parsedPapers.count == 1, "local arXiv Atom parser should parse one entry")
    let paper = parsedPapers[0]
    try check(paper.id == "2604.18803", "local arXiv Atom parser should normalize arXiv ID")
    try check(paper.arxivIDVersioned == "2604.18803v1", "local arXiv Atom parser should keep versioned ID")
    try check(paper.title.en == "A Local Paper Reader", "local arXiv Atom parser should normalize title whitespace")
    try check(paper.links.abs == "https://arxiv.org/abs/2604.18803", "local arXiv mapper should provide canonical abs link")
    try check(paper.links.pdf == "https://arxiv.org/pdf/2604.18803.pdf", "local arXiv mapper should provide canonical PDF link")
    try check(paper.links.github == "https://github.com/example/paper-reader", "local arXiv mapper should extract GitHub links from comments")
    try check(paper.listCategories == ["cs.CL"], "local arXiv mapper should preserve list categories")
}
```

Call it from `main.swift` after the existing arXiv cache checks.

- [ ] **Step 2: Run the failing check**

Run:

```bash
swift run PaperCodexCoreChecks
```

Expected: compile failure because `LocalArxivClient` does not exist.

- [ ] **Step 3: Implement `LocalArxivClient`**

Create `Sources/PaperCodexCore/LocalArxivClient.swift` with:

```swift
public struct LocalArxivListPage: Equatable, Sendable {
    public var date: String
    public var ids: [String]
}

public struct LocalArxivClientConfiguration: Sendable {
    public var categories: [String]
    public var listShow: Int
    public var userAgent: String
}

public final class LocalArxivClient: NSObject, XMLParserDelegate, Sendable {
    public static let defaultCategories = ["cs.AI", "cs.CL", "cs.CV", "cs.LG"]

    public init(configuration: LocalArxivClientConfiguration = .default, session: URLSession = .shared)

    public func fetchLatestFeed() async throws -> ArxivFeedResponse
    public func fetchFeed(date preferredDate: String?) async throws -> ArxivFeedResponse
    public func fetchPDF(for paper: ArxivFeedPaper) async throws -> Data

    public static func parseListPage(_ html: String) throws -> LocalArxivListPage
    public static func parseAtomFeed(_ xml: String, listDate: String, listCategoriesByID: [String: [String]]) throws -> [ArxivFeedPaper]
    public static func normalizeArxivID(_ raw: String) -> String
}
```

Implementation details:

- Use the CodeArXiv `run_daily.py` pattern: `https://arxiv.org/list/{category}/pastweek?show={show}` for IDs and `https://export.arxiv.org/api/query?id_list=...&max_results=...` for metadata.
- Parse only the first `<h3>` section in the list page for each category.
- Convert heading dates with `DateFormatter` using `Locale(identifier: "en_US_POSIX")` and format `yyyy-MM-dd`.
- Deduplicate normalized IDs while preserving order.
- Build canonical links: `https://arxiv.org/abs/{id}` and `https://arxiv.org/pdf/{id}.pdf`.
- Keep `summary.en` empty for now so generated summaries remain separate from raw abstract. Use `abstract.en` for the Atom summary.
- Extract GitHub URLs from comments and abstracts using the same broad pattern as CodeArXiv.
- Validate PDF downloads with `%PDF-`.

- [ ] **Step 4: Run the passing check**

Run:

```bash
swift run PaperCodexCoreChecks
```

Expected: all checks pass, including `runLocalArxivClientChecks()`.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/PaperCodexCore/LocalArxivClient.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: add direct arxiv feed client"
```

## Task 2: Local Discover Preferences And Ranking

**Files:**
- Create: `Sources/PaperCodexCore/LocalDiscoverPreferences.swift`
- Create: `Sources/PaperCodexCore/SimilarityRanker.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] **Step 1: Write failing preference/ranking checks**

Add `runLocalDiscoverPreferenceChecks()` and `runSimilarityRankerChecks()`:

```swift
func runLocalDiscoverPreferenceChecks() throws {
    let preferences = LocalDiscoverPreferences(
        categories: ["cs.CV", "cs.CL", "cs.CV"],
        whitelistTags: ["agent", "code", "agent"],
        blacklistTags: ["survey"],
        similaritySourceTagIDs: ["tag-agent"],
        enrichment: LocalEnrichmentPreferences(autoEnrichOnOpen: true, autoEnrichOnSave: true),
        embedding: EmbeddingProviderSettings(enabled: true, baseURL: "https://dashscope.aliyuncs.com", model: "text-embedding-v4")
    )
    try check(preferences.normalized.categories == ["cs.CV", "cs.CL"], "local discover preferences should dedupe categories")
    try check(preferences.normalized.whitelistTags == ["agent", "code"], "local discover preferences should dedupe whitelist tags")
    try check(preferences.normalized.embedding.model == "text-embedding-v4", "embedding settings should preserve model")
}

func runSimilarityRankerChecks() throws {
    let papers = [
        ArxivFeedPaper(id: "a", arxivID: "a", arxivIDVersioned: nil, title: ArxivLocalizedText(en: "A", zh: ""), abstract: ArxivLocalizedText(en: "A", zh: ""), summary: ArxivLocalizedText(en: "", zh: ""), authors: [], categories: ["cs.CL"], primaryCategory: "cs.CL", listCategories: ["cs.CL"], tags: ["agent"], comment: "", published: "2026-04-29T00:00:00Z", updated: nil, listDate: "2026-04-29", thumbnailVersion: nil, embedding: [1, 0], links: ArxivFeedLinks(abs: nil, pdf: nil), assets: ArxivFeedAssets(small: nil, large: nil)),
        ArxivFeedPaper(id: "b", arxivID: "b", arxivIDVersioned: nil, title: ArxivLocalizedText(en: "B", zh: ""), abstract: ArxivLocalizedText(en: "B", zh: ""), summary: ArxivLocalizedText(en: "", zh: ""), authors: [], categories: ["cs.CL"], primaryCategory: "cs.CL", listCategories: ["cs.CL"], tags: ["survey"], comment: "", published: "2026-04-29T00:00:00Z", updated: nil, listDate: "2026-04-29", thumbnailVersion: nil, embedding: [0, 1], links: ArxivFeedLinks(abs: nil, pdf: nil), assets: ArxivFeedAssets(small: nil, large: nil)),
        ArxivFeedPaper(id: "c", arxivID: "c", arxivIDVersioned: nil, title: ArxivLocalizedText(en: "C", zh: ""), abstract: ArxivLocalizedText(en: "C", zh: ""), summary: ArxivLocalizedText(en: "", zh: ""), authors: [], categories: ["cs.CL"], primaryCategory: "cs.CL", listCategories: ["cs.CL"], tags: [], comment: "", published: "2026-04-29T00:00:00Z", updated: nil, listDate: "2026-04-29", thumbnailVersion: nil, embedding: [0.9, 0.1], links: ArxivFeedLinks(abs: nil, pdf: nil), assets: ArxivFeedAssets(small: nil, large: nil))
    ]
    let ranked = SimilarityRanker.rank(papers: papers, whitelistTags: ["agent"], blacklistTags: ["survey"], interestVectors: [[1, 0]])
    try check(ranked.map(\.id) == ["a", "c", "b"], "similarity ranker should order white, neutral, black groups")
    try check(ranked[0].filterGroup == "white", "similarity ranker should mark whitelist group")
    try check(ranked[2].filterGroup == "black", "similarity ranker should mark blacklist group")
    try check((ranked[0].similarity ?? 0) > (ranked[1].similarity ?? 0), "similarity ranker should attach cosine scores")
}
```

- [ ] **Step 2: Run the failing check**

Run:

```bash
swift run PaperCodexCoreChecks
```

Expected: compile failure because local preference and ranker types do not exist.

- [ ] **Step 3: Implement preferences and ranker**

Create focused types:

```swift
public struct LocalDiscoverPreferences: Codable, Equatable, Sendable {
    public var categories: [String]
    public var whitelistTags: [String]
    public var blacklistTags: [String]
    public var similaritySourceTagIDs: [String]
    public var enrichment: LocalEnrichmentPreferences
    public var embedding: EmbeddingProviderSettings
    public var normalized: LocalDiscoverPreferences { get }
}

public struct LocalEnrichmentPreferences: Codable, Equatable, Sendable {
    public var autoEnrichOnOpen: Bool
    public var autoEnrichOnSave: Bool
}

public struct EmbeddingProviderSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var baseURL: String
    public var model: String
}
```

Create `SimilarityRanker` with:

```swift
public enum SimilarityRanker {
    public static func cosine(_ left: [Double], _ right: [Double]) -> Double
    public static func meanVector(_ vectors: [[Double]]) -> [Double]?
    public static func rank(papers: [ArxivFeedPaper], whitelistTags: [String], blacklistTags: [String], interestVectors: [[Double]]) -> [ArxivFeedPaper]
}
```

Use CodeArXiv semantics: blacklist wins over whitelist, empty tags are neutral, invalid vectors score `nil`, and fallback ordering stays deterministic by original order.

- [ ] **Step 4: Run the passing check**

Run:

```bash
swift run PaperCodexCoreChecks
```

Expected: all checks pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/PaperCodexCore/LocalDiscoverPreferences.swift Sources/PaperCodexCore/SimilarityRanker.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: add local discover preferences"
```

## Task 3: AppModel Direct arXiv Runtime

**Files:**
- Modify: `Sources/PaperCodexApp/AppModel.swift`
- Modify: `Sources/PaperCodexApp/DiscoverView.swift`

- [ ] **Step 1: Replace CodeArXiv client usage in feed loading**

Change `refreshArxivDatesAndFeed()`, `refreshArxivDates()`, `loadArxivFeed(date:)`, `preloadArxivAssets(includeLarge:)`, `ensureArxivAssetCached(_:)`, and `importArxivPaper(_:isSaved:)` to use `LocalArxivClient`.

Behavior:

- `refreshArxivDatesAndFeed()` calls `LocalArxivClient.fetchLatestFeed()`, saves the feed to `ArxivFeedCache`, stores a one-item date index if no local history exists, and renders immediately.
- `refreshArxivDates()` refreshes the latest arXiv date from live arXiv and merges it with cached dates.
- `loadArxivFeed(date:)` loads cache first for non-latest dates; if the requested date is latest or not cached, it fetches live and falls back to cache on failure.
- `importArxivPaper` downloads PDFs through `LocalArxivClient.fetchPDF(for:)`, not the old token client.
- `codeArxivUserState` stays nil during normal local operation.

- [ ] **Step 2: Remove active CodeArXiv preference mutation**

Make `refreshCodeArxivUserState()`, `updateCodeArxivPreferences(...)`, and `syncCodeArxivFavorites()` no-op or private-retired methods only if callers remain during the transition. The Settings UI should no longer call them after Task 4.

- [ ] **Step 3: Preserve current UI progress states**

Keep:

- `isLoadingArxivFeed`
- `isRefreshingArxivDates`
- `isPreloadingArxivAssets`
- `arxivCacheProgress`
- per-paper download progress dictionaries

Update labels from "CodeArXiv" language to "arXiv".

- [ ] **Step 4: Run verification**

Run:

```bash
swift build
swift run PaperCodexCoreChecks
```

Expected: build and checks pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/PaperCodexApp/AppModel.swift Sources/PaperCodexApp/DiscoverView.swift
git commit -m "feat: load discover feed directly from arxiv"
```

## Task 4: Settings Local-Only UI

**Files:**
- Modify: `Sources/PaperCodexApp/SettingsView.swift`
- Modify: `Sources/PaperCodexApp/AppModel.swift`

- [ ] **Step 1: Remove CodeArXiv connection section**

Delete visible controls for:

- CodeArXiv base URL
- CodeArXiv username
- API token
- Save & Connect
- CodeArXiv preferences
- favorite sync

- [ ] **Step 2: Add local arXiv settings**

Add Settings sections:

- `arXiv Feed`: category text field, refresh button, selected categories summary.
- `Local Ranking`: whitelist tags, blacklist tags, and similarity source identifiers bound to local preferences. The first implementation stores the identifiers and uses available local embeddings when present.
- `Codex Enrichment`: toggles for auto-enrich on open and auto-enrich on save.
- `Embedding Provider`: enable toggle, base URL, API key secure field, model text field, save button.

Store non-secret fields in `UserDefaults`. Store API key through a local secure store if one exists; if not, keep the field in memory for this batch and write a follow-up test before persisting secrets. Do not commit any real key.

- [ ] **Step 3: Wire AppModel setters**

Add:

```swift
func setLocalArxivCategories(_ categories: [String])
func setLocalTagFilters(whitelist: [String], blacklist: [String])
func setLocalEnrichmentPreferences(autoOpen: Bool, autoSave: Bool)
func setEmbeddingProviderSettings(enabled: Bool, baseURL: String, apiKey: String, model: String)
```

Each setter normalizes input, persists safe fields, and updates published state.

- [ ] **Step 4: Run verification**

Run:

```bash
swift build
swift run PaperCodexCoreChecks
```

Expected: build and checks pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/PaperCodexApp/SettingsView.swift Sources/PaperCodexApp/AppModel.swift
git commit -m "feat: make settings local first"
```

## Task 5: Runtime UI Smoke

**Files:**
- Modify only if smoke testing exposes a bug.

- [ ] **Step 1: Build app bundle**

Run:

```bash
swift build
scripts/build-app-bundle.sh
```

Expected: app bundle builds under the configured local Applications path.

- [ ] **Step 2: Launch app**

Run:

```bash
open ~/Applications/PaperCodex.app
```

Expected: Paper Codex launches.

- [ ] **Step 3: Test with Computer Use**

Use Computer Use to inspect:

- Discover loads without CodeArXiv token.
- Refresh fetches real arXiv metadata.
- Date/cache progress is visible.
- Settings contains local arXiv, local ranking, Codex enrichment, embedding provider, quick prompts, storage, and cache sections.
- No CodeArXiv base URL/token/favorite sync controls remain.
- Open shows per-paper download progress and lands in Reader.

- [ ] **Step 4: Commit fixes if needed**

If UI smoke exposes a bug, commit the exact files touched by that fix with:

```bash
git add Sources/PaperCodexApp/AppModel.swift Sources/PaperCodexApp/DiscoverView.swift Sources/PaperCodexApp/SettingsView.swift Sources/PaperCodexCore/LocalArxivClient.swift Sources/PaperCodexCore/LocalDiscoverPreferences.swift Sources/PaperCodexCore/SimilarityRanker.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "fix: stabilize local arxiv UI"
```

## Self-Review

- Spec coverage: direct arXiv fetch is covered by Tasks 1 and 3; local data ownership and cache behavior by Tasks 3 and 4; embedding settings by Tasks 2 and 4; CodeArXiv runtime removal by Tasks 3 and 4; CodeArXiv algorithm reference by Tasks 1 and 2; UI verification by Task 5.
- Scope control: this plan does not implement full generated-summary persistence or PDF-text enrichment. It adds the local setting surface and keeps Codex enrichment as a follow-on implementation behind the local-only boundary because the current repository does not yet expose generated summary fields.
- Ambiguity scan: no open-ended implementation steps are used.
- Type consistency: all newly named types are introduced before AppModel/UI references.
