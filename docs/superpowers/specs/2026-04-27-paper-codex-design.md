# Paper Codex: macOS Local Paper Library and Reading Assistant Design

Date: 2026-04-27
Status: user-approved design draft

## Goal

Build a macOS local App for managing, reading, selecting, and discussing academic papers with Codex-backed cloud AI sessions.

The product should feel like a local paper manager plus an AlphaXiv-style reading assistant:

- Manage a local paper library with manual multi-level categories and tags.
- Read PDF papers in a native macOS interface.
- Select words, sentences, or paragraphs in the PDF and use that source position inside an ongoing Codex conversation.
- Ask questions about one paper or a user-selected set of papers.
- Let answers cite back to original PDF positions.
- Keep paper files, index files, categories, tags, anchors, and App sessions local.
- Use real Codex sessions and cloud models through the Codex CLI, not a mock chat layer.

## Non-Goals for the First Implementation

- No web-hosted product.
- No Zotero sync in the first implementation.
- No automatic reading status.
- No automatic categorization or auto-tagging.
- No OCR/scanned PDF support in the first implementation.
- No full-library open-ended research chat in the first implementation.
- No requirement to convert every PDF into a full `paper.md` as the primary source.

## Reference Projects

These projects are useful references, but the design should not be a direct fork of any one of them:

- `Cinnamon/kotaemon`: mature document QA UI, useful for citation-oriented document chat ideas.
- `denser-org/denser-chat`: useful for PDF source highlighting and retrieval UI ideas.
- `run-llama/sec-insights`: useful for citation highlighting in a PDF viewer.
- PDF.js highlight examples: useful for viewer-level text span and bbox highlighting concepts.

The App's differentiator is the combination of native macOS PDF reading, local paper-library management, and real Codex session orchestration.

## Product Shape

The product is a macOS native local App.

Recommended stack:

- SwiftUI for the macOS UI.
- PDFKit for native PDF display, text selection, page navigation, and visible highlight overlays.
- A local backend process or service for indexing, SQLite storage, file watching, and Codex CLI orchestration.
- Codex CLI as the agent runtime, invoked as a child process with per-session workspaces.

This is preferred over Electron/Tauri because the primary daily workflow is local paper reading on macOS, where native PDFKit behavior and system integration matter.

## UI Structure

The App uses two main pages.

### Paper Library Page

The library page is for organization and discovery.

Layout:

- Left: multi-level category tree.
- Right: paper list.
- Top controls: search, import PDF, configure watched folders.

Library behavior:

- Papers can be manually imported.
- Watched folders can be configured; new PDFs are indexed when discovered.
- Categories are manually maintained and support nesting.
- Tags are manually maintained and flat.
- A paper can belong to multiple categories and have multiple tags.
- Opening a paper navigates to the reading page.

### Reading and Chat Page

The reading page is for close reading and conversation.

Layout:

- Left: PDF reader.
- Right: Chat panel.

PDF reader behavior:

- Displays the original PDF.
- Supports page navigation and zoom.
- Supports selecting words, sentences, or paragraphs from the text layer.
- Selection creates a stable source anchor.
- App highlights cited regions when a Codex answer references them.

Chat behavior:

- The top of the Chat panel has only:
  - a session dropdown;
  - a `New` button.
- The session dropdown switches among Codex-backed sessions for the current paper or paper set.
- `New` creates a new App session and a new Codex session workspace.
- Selected PDF source anchors are included inside conversation messages, not shown in a separate evidence panel.
- Codex citations are rendered inline as clickable markers.

## Core Architecture

The system has four main components.

### 1. macOS App

Responsibilities:

- Render library and reading UI.
- Manage PDFKit selection and highlight overlays.
- Capture user source selections.
- Display Chat messages and session controls.
- Route user actions to the local backend.

### 2. Local Backend

Responsibilities:

- Maintain SQLite database.
- Import PDFs and compute stable file hashes.
- Watch user-selected folders.
- Extract lightweight text and coordinate indexes from PDFs with text layers.
- Create and resolve anchors.
- Build prompt payloads for Codex.
- Manage session workspaces.
- Invoke and resume Codex CLI processes.

The backend should expose a narrow API to the SwiftUI layer. The UI should not directly manipulate Codex workspaces or index files.

### 3. PDF Index Layer

The original PDF remains the primary source.

On import, the App creates a lightweight auxiliary index rather than forcing a complete `paper.md` conversion.

Per paper, the index should include:

- `metadata.json`: title, authors, year, source URL if available, local path, file hash.
- `pages.jsonl`: page number, extracted text, rough layout metadata, extraction confidence.
- `spans.jsonl`: text blocks with stable IDs, page numbers, bbox coordinates, text, char ranges, section hints, and confidence.
- `anchors.jsonl`: user-created source selections.
- optional local snippet caches when needed for a specific prompt or session.

The first implementation supports only PDFs with a usable text layer.

### 4. Codex Session Runtime

Each App chat session maps to a Codex session and a local workspace.

The App creates workspaces like:

```text
Application Support/PaperCodex/sessions/{session_id}/
  session.json
  prompt_contract.md
  papers/
    {paper_id}/
      original.pdf
      metadata.json
      pages.jsonl
      spans.jsonl
      anchors.jsonl
  turns/
    0001-user.json
    0001-codex.json
```

Starting a session uses `codex exec`.

Continuing a session uses `codex exec resume {codex_session_id}`.

The App captures streamed or JSONL Codex output and stores the final response in the App session log.

## How Codex Reads PDFs

Codex should not be asked to blindly read the PDF binary as its main context.

The reading protocol has two layers:

1. Prompt-level context:
   - the user's question;
   - selected source anchors;
   - a small set of relevant spans retrieved by the local backend;
   - paper metadata;
   - citation-output rules.

2. Workspace-level context:
   - original PDF;
   - lightweight index files;
   - anchor files;
   - prompt contract.

This gives Codex autonomy to inspect context files when useful, while the App keeps source-position truth grounded in PDFKit-derived anchors and spans.

Later, this protocol can become a Codex skill that teaches the agent how to read these paper workspaces, how to interpret anchor IDs, and how to emit citation IDs.

## Data Model

### Paper

Fields:

- `id`
- `file_path`
- `file_hash`
- `title`
- `authors`
- `year`
- `source_url`
- `imported_at`
- `updated_at`

### Category

Fields:

- `id`
- `parent_id`
- `name`
- `sort_order`

Paper-category relation:

- `paper_id`
- `category_id`

### Tag

Fields:

- `id`
- `name`

Paper-tag relation:

- `paper_id`
- `tag_id`

### Span

Stable ID format:

```text
paper:{paper_id}:p{page}:b{block_index}
```

Fields:

- `id`
- `paper_id`
- `page`
- `bbox`
- `text`
- `char_range`
- `section_hint`
- `confidence`

### Anchor

Stable ID format:

```text
paper:{paper_id}:p{page}:a{timestamp_or_ulid}
```

Fields:

- `id`
- `paper_id`
- `page`
- `selected_text`
- `bbox_list`
- `matched_span_ids`
- `before_context`
- `after_context`
- `created_session_id`
- `created_at`
- `confidence`

Anchors may refer to a word, sentence, paragraph, or cross-span selection.

### Session

Fields:

- `id`
- `title`
- `paper_ids`
- `codex_session_id`
- `workspace_path`
- `created_at`
- `updated_at`

Session behavior:

- A paper can have multiple sessions.
- A session can include multiple explicitly selected papers.
- Multi-paper conversation is scoped by the user's explicit selection, not by automatic full-library search.

## Anchor and Citation Protocol

When a user selects text in PDFKit:

1. App captures page, selected text, and selection bounds.
2. App maps the selection to nearest spans by text and bbox.
3. App creates an anchor with nearby context.
4. App inserts a source reference into the user's message.

Prompt representation:

```text
[selected source]
anchor_id: paper:abc:p5:a20260427003115
paper: Representation Autoencoders...
page: 5
text: "..."
nearby_spans: paper:abc:p5:b16, paper:abc:p5:b17, paper:abc:p5:b18
```

Codex answer contract:

- Use normal prose for the explanation.
- Cite source positions with markers:

```text
[[cite:paper:{paper_id}:p5:b17]]
[[cite:paper:{paper_id}:p5:a20260427003115]]
```

- If evidence is insufficient, say so explicitly.
- Do not invent paper positions.

App citation handling:

- Parse citation markers.
- Resolve IDs through local span/anchor tables.
- Render citations as clickable inline markers.
- On click, navigate to the PDF page and highlight the bbox.
- If an ID cannot be resolved, display it as a broken citation rather than silently hiding the problem.

Highlight precision:

- Default: block-level highlight.
- Enhanced: sentence or phrase-level highlight when bbox and text matching are high confidence.
- Fallback: page-level jump if block-level mapping is unavailable.

## Error Handling

Only boundary layers should wrap errors heavily:

- file import;
- PDF parsing;
- folder watching;
- Codex CLI process management;
- database migration;
- external metadata lookup if added later.

Internal application logic should expose failures clearly instead of hiding them behind broad catch-all handling.

Important failure cases:

- PDF has no text layer: reject or mark as unsupported for Q&A.
- Span extraction confidence is low: allow reading, degrade citation precision.
- Anchor matching fails: do not create a fake anchor.
- Codex CLI is missing: show setup error.
- Codex is not logged in: show setup error.
- Codex session resume fails: keep App session logs and offer a new session or retry.
- Citation ID cannot be resolved: show a broken citation marker.

## Testing Strategy

Use real PDFs and real Codex CLI integration for core tests.

Test areas:

- PDF import with text-layer papers.
- Duplicate detection by file hash.
- Category and tag CRUD.
- Folder watching with real filesystem changes.
- Span extraction and bbox persistence.
- Anchor creation for word, sentence, paragraph, cross-line, and double-column selections.
- Citation marker parsing.
- PDF navigation and highlight resolution.
- Session creation, switching, and resume.
- Codex CLI smoke test using `codex exec` and `codex exec resume`.
- UI flow for library page and reading page.

Use fixture files rather than mocks. UI tests can use small real PDFs and deterministic local fixture databases; process-level tests should exercise real file and Codex CLI boundaries.

## Implementation Order

1. Create macOS app shell with library page and reading page.
2. Add SQLite schema for papers, categories, tags, spans, anchors, sessions.
3. Implement manual PDF import and folder watching.
4. Add PDFKit reader, selection capture, and highlight overlay.
5. Implement text-layer span extraction for supported PDFs.
6. Implement anchor creation and citation resolution.
7. Create session workspace manager.
8. Integrate Codex CLI session start and resume.
9. Add prompt builder and citation-output contract.
10. Add tests with real PDFs and real Codex CLI smoke runs.

## Design Constraints

- The first version should prioritize reliable paper reading and source-grounded conversation over broad library-level search.
- Full PDF-to-Markdown conversion should remain optional and local, not a required primary representation.
- The App should preserve enough workspace structure that future Codex skills can standardize how the agent reads paper context.
- All meaningful code or spec changes should be committed with standard commit messages.
