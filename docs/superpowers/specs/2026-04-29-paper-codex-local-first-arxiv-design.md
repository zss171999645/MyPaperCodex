# Paper Codex Local-First arXiv Design

Date: 2026-04-29
Status: approved direction for implementation planning
Supersedes:

- `docs/superpowers/specs/2026-04-28-codearxiv-discover-library-design.md`
- `docs/superpowers/specs/2026-04-29-paper-codex-data-backend-redesign.md`

## Goal

Paper Codex should be a local-first paper reading app. The library, PDFs, tags, summaries, notes, arXiv cache, Codex processing results, thumbnails, embeddings, and reading sessions live on the user's machine.

The app should not require a Paper Codex backend, CodeArXiv server, account, token, or cloud sync for the first product version. arXiv is a direct source that the app can query and cache. CodeArXiv remains an implementation reference for feed collection, tagging prompts, thumbnail generation, tag filtering, and similarity ranking, but it is no longer a runtime dependency.

## Product Boundary

### In Scope

- Local library management for saved PDFs.
- Local disposable cache for opened-but-unsaved arXiv PDFs.
- Direct arXiv feed loading from `arxiv.org` and `export.arxiv.org`.
- Local feed metadata cache by date and category.
- Local thumbnail generation and cache.
- Local Codex-generated summaries, Chinese summaries, and tags.
- Local user tags, folders, notes, and user summaries.
- Optional embedding-based similarity ranking with user-provided embedding provider settings.
- Settings for arXiv categories, cache policy, local storage, quick prompts, Codex enrichment, and embedding provider.

### Out Of Scope For This Version

- User login.
- Online sync.
- Product API.
- Remote CodeArXiv feed server.
- Remote PDF parsing.
- Remote favorites migration as an ongoing feature.
- Payment, subscription, or multi-device account features.

These can be reconsidered later, but they should not shape the current app architecture.

## User Experience

### Library First

The Library remains the main product surface. A saved paper is durable: its PDF is under the library path, its tags/folders/notes/summaries are local database rows, and it can be opened offline.

Discover is an intake surface, not the center of the product. It helps the user browse recent arXiv papers, open a paper into cache, and save useful papers into the library.

### Discover

Discover loads papers directly from arXiv:

1. The app fetches arXiv category listing pages, following the CodeArXiv `run_daily.py` pattern.
2. It parses the newest available date and paper IDs per category.
3. It calls `https://export.arxiv.org/api/query` in batches to fetch title, authors, abstract, primary category, all categories, published/updated timestamps, and comments.
4. It normalizes papers into the existing `ArxivFeedPaper` shape so the current card UI can evolve without a second display model.
5. It applies local category, whitelist, blacklist, and optional similarity sorting before rendering.

If metadata for a date is cached, Discover can render it offline. If online refresh fails and cache exists, the app should show cached content plus a clear stale/error status.

### Open And Save

Open:

- Downloads the arXiv PDF into disposable cache if not already saved.
- Shows visible download progress.
- Opens the existing reader/chat surface.
- Starts optional local enrichment if enabled.

Save:

- Moves or imports the PDF into the durable library path.
- Lets the user choose tags before confirming.
- Preserves cached metadata and generated enrichment.
- Converts the paper from disposable cache state to saved library state.

If the user opens a paper and never saves it, clearing cache may remove that PDF and its disposable thumbnails. Saved library PDFs are never removed by cache cleanup.

## Local Data Model

The app should keep the current repository compatible while adding focused local tables or fields where needed.

### Paper Identity

arXiv papers should deduplicate by normalized arXiv ID, versioned arXiv ID, canonical abs URL, PDF URL, and existing source URL.

Manual PDFs remain local-private and deduplicate by existing import behavior and file metadata. They do not need arXiv metadata.

### User-Owned Paper Data

Each local paper should support:

- `user_summary`: manually editable user summary, initially empty.
- `user_notes`: manually editable user notes, initially empty.
- local folders/categories.
- local hierarchical tags or current tags with a migration path to hierarchy.
- generated enrichment records from Codex.

Generated enrichment should be separate from user-authored text:

- `generated_summary_en`
- `generated_summary_zh`
- `generated_tags`
- `generated_at`
- `generated_by_model`
- `generation_prompt_version`
- `generation_error`

This avoids overwriting the user's own notes when Codex refreshes an automatic summary.

### arXiv Cache

The arXiv cache should record:

- feed date.
- selected categories.
- source URLs.
- fetched paper IDs.
- metadata JSON.
- cache timestamp.
- stale/error status.
- thumbnail cache state.
- optional PDF cache state.

Small metadata and thumbnails can be retained longer. Large previews and unsaved PDFs should be disposable under a size policy.

## Local Enrichment Pipeline

Local Codex is responsible for paper summaries and tags.

Reference implementation:

- CodeArXiv `tag_prompt.md` defines the initial tag taxonomy and output format.
- CodeArXiv `codex_fill_zh.py` shows a useful batch pattern for title/abstract summarization, Chinese translation, summary generation, and tag parsing.

Paper Codex should adapt this into app-native jobs:

1. Build a prompt from arXiv metadata or extracted PDF text.
2. Run Codex locally using the app's existing Codex CLI integration.
3. Require structured JSON output.
4. Parse and validate the result.
5. Store generated summary/tag fields locally.
6. Show job progress and per-paper errors in the UI.

The first implementation can enrich from title and abstract because that is available immediately from arXiv. Full PDF-text enrichment can run after import/indexing.

Codex-generated tags are suggestions. Users can accept, edit, remove, or add local tags. Saving a paper should not require waiting for enrichment.

## Embedding And Similarity

Embedding is optional. Without embedding settings, the app still works fully; Discover falls back to date/category/tag ordering.

Settings should expose:

- enable or disable embedding.
- embedding base URL.
- API key, stored locally as a secret.
- model name.
- batch size or conservative default.
- max characters per item.
- button to test provider with one short string.

The embedding provider should be treated as an OpenAI-compatible or provider-adapted HTTP service. CodeArXiv's DashScope endpoint resolver is a useful reference, but Paper Codex should keep provider code behind a small local `EmbeddingClient` boundary so future providers do not leak through UI or ranking code.

Similarity behavior should match the CodeArXiv concept:

- Paper embeddings are generated from title plus abstract first.
- A folder/tag collection can have an interest vector computed as the mean of saved paper embeddings.
- Discover papers can be scored by cosine similarity against selected local collections.
- If several collections are selected, the displayed score is the max similarity.
- Papers are sorted within whitelist/neutral/blacklist groups by similarity when similarity data exists.

Embedding vectors and errors are stored locally. They are never uploaded by this version.

## Filters And Ranking

The app should keep the useful CodeArXiv feed controls, but localize them:

- category selection.
- tag whitelist.
- tag blacklist.
- selected similarity source folders/tags.
- language display preference.

Ranking order:

1. Apply selected arXiv categories.
2. Classify by local tags into whitelist, neutral, blacklist.
3. Sort each group by similarity if available.
4. Concatenate whitelist, neutral, blacklist.
5. Preserve deterministic fallback ordering by publish/update time and arXiv ID.

If a paper has no generated tags yet, it belongs to neutral.

## Settings

Settings should no longer show CodeArXiv base URL, username, token, or favorite sync.

Settings should contain separate sections:

- Library storage: saved paper path, cache path, cache cleanup.
- arXiv feed: categories, date/cache refresh, optional daily prefetch policy.
- Local Codex enrichment: auto-enrich on open/save, prompt version, regenerate controls.
- Embedding provider: base URL, API key, model, enable toggle, test provider.
- Ranking and filters: whitelist tags, blacklist tags, similarity source folders/tags.
- Quick prompts: title/content prompt presets for reader chat.

## Implementation Boundaries

Recommended local modules:

- `LocalArxivClient`: network calls to arXiv listing pages and Atom API.
- `ArxivFeedMapper`: converts raw arXiv records to `ArxivFeedPaper`.
- `ArxivFeedCache`: local metadata and asset cache.
- `LocalEnrichmentStore`: generated summary/tag persistence.
- `CodexEnrichmentRunner`: prompt construction, Codex execution, JSON parsing.
- `EmbeddingSettingsStore`: local embedding settings and secret access.
- `EmbeddingClient`: provider call and response parsing.
- `SimilarityRanker`: vector parsing, mean vectors, cosine similarity, local sorting.
- `DiscoverPreferencesStore`: categories, whitelist, blacklist, similarity sources.

SwiftUI views should consume app model state and call these boundaries. They should not know whether the metadata came from live arXiv, cache, Codex, or embedding provider internals.

## Error Handling

- arXiv network failures should fall back to cached feed data when available.
- arXiv parsing failures should surface the failing URL and parsing step.
- PDF downloads should validate that the response is actually a PDF.
- Codex enrichment failures should be stored per paper and shown without blocking reading.
- Embedding provider errors should disable similarity for that batch and keep the feed usable.
- Cache cleanup should never delete saved library PDFs.

## Verification

Core checks should cover:

- arXiv ID normalization.
- arXiv Atom parsing with real fixture XML from `export.arxiv.org`.
- listing-page date and ID parsing with a saved real HTML fixture.
- feed cache save/load and stale fallback.
- tag whitelist/blacklist grouping.
- cosine similarity and collection mean-vector scoring.
- enrichment JSON parsing and validation.
- embedding settings persistence without exposing API key in plain `UserDefaults`.

Manual/runtime checks should cover:

- Discover live refresh from arXiv.
- cached Discover when network is unavailable or arXiv fetch fails.
- Open download progress and reader handoff.
- Save with tag selection and cache-to-library movement.
- Settings layout after removing CodeArXiv connection controls.
- embedding disabled, invalid provider, and valid provider states.

UI checks should continue to use Computer Use when available for layout, click targets, progress states, and route stability.

## Migration From Current Code

The current app has a working Discover UI, PDF import/open/save flow, thumbnail cache, quick prompts, and local repository. Keep those.

Remove or retire:

- `arxivFeedBaseURL`
- `arxivFeedToken`
- `arxivFeedUsername`
- CodeArXiv user state refresh.
- CodeArXiv preference save endpoint.
- CodeArXiv favorite sync as an always-visible setting.
- NAS/default remote URLs.

Replace with:

- direct arXiv category settings.
- local Discover preferences.
- optional local import tool for old CodeArXiv favorites if we still need one-time migration.
- local enrichment and embedding settings.

## Open Future Door

A backend can still be added later, but it should be optional and layered behind local-first boundaries. The app should not be restructured around a backend until there is a clear need for multi-device sync or paid cloud features.

This design intentionally optimizes for a strong standalone reader first.
