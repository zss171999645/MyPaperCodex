# Paper Codex Data Backend Redesign

Date: 2026-04-29
Status: productized design for user review

## Goal

Redesign Paper Codex's data layer and backend as a standard, general-purpose product that can support public registration, paid plans, long-term operations, and local-first research workflows without compromising private paper files.

The product remains local-first: the macOS app must continue to open saved PDFs, cached arXiv feeds, notes, tags, source anchors, and recent Codex session context without a network connection. Online services add account login, metadata sync, feed enrichment, recommendations, entitlements, and operational controls; they must not become required for normal reading of already-local papers.

Paper Codex should be designed as a commercial product from the first backend release. Even if the first deployment is for one owner, the architecture must avoid personal usernames, hardcoded CodeArXiv tokens, single-user assumptions, or one-off admin scripts that cannot evolve into a public service.

## Commercial Product Principles

- Multi-tenant by default: all user-owned backend rows are scoped by `user_id`, and future team/workspace support is enabled through `workspace_id` without requiring a schema rewrite.
- Public registration capable: the account system supports email/password signup, email verification, login, refresh-token rotation, password reset, and device revocation.
- Payment-ready without forcing day-one billing: plans, subscriptions, entitlements, usage counters, and billing customer IDs are first-class tables even if the first release has only a free/internal plan.
- Privacy is a product feature: Paper Codex does not sync private PDFs. For non-arXiv papers, the backend syncs only the user-provided display title and organization data, not file bytes, extracted text, abstracts, local file paths, or content hashes.
- Product API is the only public app API. CodeArXiv becomes an internal feed/recommendation dependency behind the product API.
- Operations are part of the product: migrations, backups, audit logs, rate limits, support tooling, account deletion, and export must be designed with the backend, not added as emergency scripts later.
- The owner setup process must be guided step by step. The implementation plan should explicitly list when the user needs to provide a domain, email sender, database, object storage/CDN choice, and payment provider credentials.

## Current State

- Local SQLite stores saved papers, categories, flat tags, page text, spans, anchors, sessions, session papers, chat messages, and watched folders.
- Paper files live under Application Support: saved PDFs under `papers/`, unsaved opened arXiv PDFs under `cache/papers/`, arXiv feed JSON/assets under `arxiv-cache/`, and transient downloads under `cache/downloads/`.
- CodeArXiv is currently the remote feed and preference service. Paper Codex stores its base URL, username, and token in `UserDefaults`.
- The app can decode daily feed metadata, cache thumbnails, download PDFs, migrate favorites, and keep five-page library thumbnails.
- Publish-time risks remain: insecure HTTP defaults, an App Transport Security exception for the test host, token storage in `UserDefaults`, possible auth forwarding to arbitrary absolute asset URLs, and remote MathJax loading.

## Product Requirements

### Online And Offline

- The app opens and searches the saved local library offline.
- The app opens cached arXiv daily feeds offline for any date previously cached.
- The app opens cached arXiv thumbnails and large preview images offline.
- The app can optionally prefetch every PDF for selected arXiv feed dates.
- Offline edits to library metadata, tags, folders, notes, anchors, and reading sessions are queued and synced when connectivity returns.
- The app must clearly distinguish a disposable cache miss from a saved-library missing file.

### User Login And Sync

- Users can register with email and password from the app.
- Signup requires email verification before enabling sync.
- Users can log in with email and password.
- Users can request a password reset by email.
- A signed-in user gets online sync for library metadata, folders, hierarchical tags, notes, source anchors, reading annotations, and CodeArXiv preferences.
- The app supports multiple local devices for one user.
- The app can continue in local-only mode without login.
- Tokens and refresh credentials are stored in Keychain, not in `UserDefaults`.
- A user can revoke individual devices from the account/security settings.

### Commercial Accounts And Plans

- The backend stores users, devices, plans, subscriptions, entitlements, and usage counters separately.
- A plan can limit features such as synced library item count, active devices, daily arXiv prefetch volume, feed history retention, recommendation jobs, and future AI usage.
- Plan checks are enforced server-side through entitlements, not hidden UI switches.
- The first release can ship with `internal`, `free`, and `pro_placeholder` plans. Only `internal` needs to be active until billing is wired.
- Payment integration is not required for metadata sync Phase 1, but the schema must support Stripe or a domestic payment provider later.

### Library Data

- Papers have stable identities independent of local file path.
- arXiv papers are deduplicated by normalized arXiv ID, versioned arXiv ID, canonical abs URL, PDF URL, and file hash.
- Non-arXiv papers are local-private by default. The backend stores only the user's display title and user-owned organization data for them. Local file hashes, extracted text, abstracts, absolute paths, and PDF bytes stay local.
- Tags are hierarchical and can be attached to papers.
- Categories/folders remain hierarchical and represent organization, while tags represent facets.
- Notes are first-class data, not hidden inside chat messages.
- Each user-paper relationship has two explicit user-owned text fields: `user_summary` and `user_notes`. They are empty at creation and can be edited later without changing shared paper catalog metadata.
- User-created anchors, PDF highlights, and notes are synced as independent entities.

### Security

- Release builds use HTTPS only. HTTP and host-specific ATS exceptions are development-only.
- The app attaches Authorization headers only to the configured product API origin, never to arbitrary absolute asset or PDF URLs.
- The backend checks user ownership on every object. `username`, `paper_id`, `arxiv_id`, or sync cursors from the client are never trusted as authorization.
- Edge or reverse-proxy products may hide and protect the origin, but they are not the security boundary by themselves.

## Architecture

Paper Codex should split data into four explicit layers.

### 1. Local App Store

The macOS app owns the offline-capable SQLite database and local file store.

Responsibilities:

- Store all saved library metadata and sync state.
- Store feed manifests and cache indexes.
- Store local files, thumbnails, extracted text, spans, anchors, notes, and Codex session records.
- Queue local changes in a sync outbox.
- Apply remote changes from a sync inbox.
- Enforce local cache policies and storage budgets.

Recommended module boundaries:

- `LocalStore`: SQLite migrations and typed repositories.
- `LibraryDataStore`: papers, folders, hierarchical tags, notes, anchors, annotations, sessions.
- `ArxivCacheStore`: daily feed manifests, feed items, feed assets, optional feed PDF cache.
- `FileStore`: content-addressed file placement, movement between disposable cache and saved library, missing-file repair.
- `SyncStore`: sync cursors, local revisions, tombstones, outbox batches, remote acknowledgements.
- `CredentialStore`: Keychain wrapper for account tokens and per-device secrets.

### 2. Product API

The app should talk to a single product API, not directly to a personal NAS or raw CodeArXiv development server.

Responsibilities:

- User login and token refresh.
- Device registration and revocation.
- Library metadata sync.
- CodeArXiv feed access and preferences.
- Public feed asset metadata and cache coordination.
- Per-user rate limits, audit logs, and ownership checks.

Recommended runtime:

- API service behind HTTPS.
- PostgreSQL for user, billing, sync, and metadata tables.
- Object storage or CDN cache only for public/product assets such as arXiv thumbnails, generated feed assets, and static resources. Private user PDFs are not uploaded by the baseline product.
- Background workers for feed ingestion, thumbnail generation, recommendation vectors, and bulk prefetch jobs.
- EdgeOne or another edge/proxy layer in front of the API for TLS termination, WAF, DDoS mitigation, caching public assets, and hiding origins.

Commercial backend responsibilities:

- Email/password signup, email verification, login, password reset, and refresh-token rotation.
- Device registration, device naming, device revocation, and session invalidation.
- Plan and entitlement lookup for every feature that consumes shared backend resources.
- Usage accounting for sync writes, feed requests, background prefetch jobs, and future AI features.
- Audit events for security-sensitive and billing-sensitive actions.
- Admin/support tooling that can inspect account state without exposing private paper content.

### 3. CodeArXiv Feed Service

CodeArXiv remains the recommendation/feed engine, but Paper Codex should consume it through the product API.

Responsibilities:

- Daily arXiv ingestion.
- Feed enrichment: titles, summaries, authors, categories, tags, links, thumbnail assets, similarity scores.
- User preference application: category filters, tag whitelist/blacklist, similarity folders.
- Public arXiv asset/PDF prefetch jobs.

Paper Codex should not require the user to know a CodeArXiv token or raw CodeArXiv URL. The app should authenticate to the product API; the product API can call CodeArXiv internally.

### 4. File And Cache Layer

Paper Codex should make file state explicit.

File states:

- `saved_local`: user saved paper, stored in durable library path.
- `cache_preview`: opened from Discover but not saved, disposable.
- `feed_pdf_cache`: bulk cached PDF for a daily arXiv feed, disposable by policy but reusable if the user saves that paper.
- `remote_public`: public arXiv PDF known by URL or arXiv ID, not stored locally.
- `missing_local`: metadata exists but local PDF is unavailable.

Cache policy:

- Metadata feed cache is small and retained by date until the user clears it.
- Small thumbnails are retained by date and can be regenerated by downloading feed assets.
- Large preview images are retained under a size budget.
- Feed PDF cache is opt-in per date/date range and has a separate size budget.
- Saved library PDFs are never deleted by cache cleanup.

## Local Schema V2

The current schema should evolve rather than be patched with ad hoc columns.

### Accounts And Devices

`local_accounts`

- `id`
- `remote_user_id`
- `display_name`
- `email`
- `email_verified`
- `sync_enabled`
- `plan_code`
- `last_login_at`
- `created_at`
- `updated_at`

`devices`

- `id`
- `remote_device_id`
- `name`
- `public_key`
- `created_at`
- `revoked_at`

The app stores access and refresh tokens in Keychain. `UserDefaults` can store only non-secret UI preferences such as the selected product API environment.

### Papers And Files

`papers`

- `id`
- `canonical_key`
- `title`
- `authors_json`
- `year`
- `abstract`
- `source_kind`
- `source_url`
- `arxiv_id`
- `arxiv_id_versioned`
- `doi`
- `is_saved`
- `created_at`
- `updated_at`
- `deleted_at`
- `sync_revision`

For non-arXiv local-private papers, synced server payloads must not include `file_path`, `content_hash`, extracted `abstract`, page text, or spans. The local row can keep those fields for local search and reader context.

`paper_files`

- `id`
- `paper_id`
- `storage_state`
- `local_path`
- `content_hash`
- `byte_count`
- `mime_type`
- `remote_file_id`
- `encryption_state`
- `created_at`
- `updated_at`

`paper_sources`

- `id`
- `paper_id`
- `source_type`
- `source_id`
- `url`
- `version`
- `metadata_json`
- `created_at`

`user_papers`

- `id`
- `local_account_id`
- `paper_id`
- `remote_user_paper_id`
- `display_title`
- `source_kind`
- `arxiv_id`
- `is_saved`
- `user_summary`
- `user_notes`
- `last_read_at`
- `created_at`
- `updated_at`
- `deleted_at`
- `sync_revision`

`user_summary` and `user_notes` are initialized empty. They are user-owned fields and must not be merged into shared paper catalog metadata.

### Organization

`folders`

- `id`
- `parent_id`
- `name`
- `sort_order`
- `deleted_at`
- `sync_revision`

`paper_folders`

- `paper_id`
- `folder_id`
- `created_at`
- `deleted_at`

`tags`

- `id`
- `parent_id`
- `name`
- `color`
- `sort_order`
- `deleted_at`
- `sync_revision`

`paper_tags`

- `paper_id`
- `tag_id`
- `created_at`
- `deleted_at`

Use folders for library navigation and hierarchical tags for facets. Existing categories migrate to folders; existing flat tags migrate to root-level tags.

### Notes, Anchors, And Annotations

`paper_notes`

- `id`
- `paper_id`
- `anchor_id`
- `title`
- `body_markdown`
- `created_at`
- `updated_at`
- `deleted_at`
- `sync_revision`

`pdf_annotations`

- `id`
- `paper_id`
- `anchor_id`
- `page`
- `kind`
- `color`
- `text`
- `bbox_list_json`
- `created_at`
- `updated_at`
- `deleted_at`
- `sync_revision`

Existing `anchors`, `spans`, and `pages` stay local-first but get `updated_at`, `deleted_at`, and `sync_revision` where user-authored content needs sync. Extracted page text and spans can remain local-only until a user explicitly opts into cloud indexing.

### arXiv Cache

`arxiv_feed_dates`

- `date`
- `source`
- `feed_version`
- `filter_snapshot_json`
- `cached_at`
- `expires_at`

`arxiv_feed_items`

- `date`
- `arxiv_id`
- `paper_json`
- `sort_key`
- `similarity`
- `is_favorite`
- `cached_at`

`arxiv_assets`

- `asset_key`
- `arxiv_id`
- `date`
- `kind`
- `local_path`
- `url`
- `content_hash`
- `byte_count`
- `cached_at`
- `last_accessed_at`

`arxiv_pdf_cache`

- `arxiv_id`
- `date`
- `local_path`
- `content_hash`
- `byte_count`
- `cached_at`
- `last_accessed_at`
- `promoted_paper_id`

### Sync State

`sync_entities`

- `entity_type`
- `entity_id`
- `local_revision`
- `remote_revision`
- `dirty`
- `deleted`
- `last_synced_at`

`sync_outbox`

- `id`
- `entity_type`
- `entity_id`
- `operation`
- `payload_json`
- `base_remote_revision`
- `created_at`
- `attempt_count`
- `last_error`

`sync_cursors`

- `scope`
- `cursor`
- `updated_at`

## Sync Protocol

The sync protocol should be simple, idempotent, and conflict-aware.

### Login

Use email/password signup and login for the first public-ready backend.

Signup flow:

- The user submits email and password.
- The server creates an unverified user, stores only a password hash, and sends an email verification link or code.
- Sync is disabled until the email is verified.
- Verification marks `email_verified = true`, creates the first device, and issues short-lived access and rotatable refresh tokens.

Login flow:

- The user submits email and password.
- The server applies rate limits and verifies the password hash.
- The app registers or reuses a named device.
- The app receives an access token and refresh token from the product API.
- Access tokens are short-lived. Refresh tokens are rotatable and stored in Keychain.

Password reset flow:

- The user requests a reset by email.
- The server sends a short-lived reset token or code.
- After reset, existing refresh tokens for that user are revoked unless the user explicitly keeps trusted devices.

Local-only users can skip login. If the user signs in after building a local library, the app links the existing local database to the remote account only after explicit confirmation.

Future OAuth providers such as Apple, GitHub, or institutional SSO can be added after the email/password flow is stable. They must link into the same `users`, `user_identities`, `devices`, and entitlement model.

### Push

The app sends batches from `sync_outbox`.

Each change includes:

- `entity_type`
- `entity_id`
- `operation`
- `payload`
- `base_remote_revision`
- `client_change_id`
- `device_id`

The server applies idempotency by `client_change_id`. Ownership is derived from auth, not from payload.

### Pull

The app pulls changes with a server cursor.

The server returns:

- `changes`
- `next_cursor`
- `server_time`

The app applies changes in a local transaction and updates `sync_cursors` only after the transaction succeeds.

### Conflict Rules

- Paper identity merges by canonical keys. arXiv papers use arXiv ID, DOI, and canonical URL. Local non-arXiv file hashes can be used inside one device, but private file hashes are not sent to the product API.
- Folders and tags use entity-level revisions. Rename conflicts use last-write-wins with preserved history in audit logs.
- Paper-tag and paper-folder membership use add/remove tombstones so concurrent adds and removes are deterministic.
- Notes are independent entities; edits conflict only on the same note.
- Anchor/annotation edits are independent entities; deletion uses tombstones.
- Folder/tag tree conflicts cannot silently corrupt hierarchy. If a parent is deleted remotely while a child is edited locally, reparent the child to a `Sync Conflicts` folder/tag and surface it in Settings.

## Backend Schema

The product API should store syncable metadata in relational tables.

Core tables:

- `users`
- `user_identities`
- `devices`
- `refresh_tokens`
- `email_verification_tokens`
- `password_reset_tokens`
- `plans`
- `subscriptions`
- `entitlements`
- `usage_counters`
- `paper_catalog`
- `paper_sources`
- `library_items`
- `user_papers`
- `folders`
- `tags`
- `paper_folders`
- `paper_tags`
- `paper_notes`
- `anchors`
- `pdf_annotations`
- `sync_events`
- `sync_cursors`
- `arxiv_feed_preferences`
- `arxiv_favorites`
- `file_objects`
- `audit_events`
- `admin_audit_events`

The backend should not store raw local absolute paths. In the baseline product, it does not store private user PDF file objects at all. Each user-owned row has `user_id`, `workspace_id` where applicable, `created_at`, `updated_at`, `deleted_at`, and a revision field.

### Product Account Tables

`users`

- `id`
- `email`
- `normalized_email`
- `password_hash`
- `email_verified`
- `display_name`
- `created_at`
- `updated_at`
- `disabled_at`

`user_identities`

- `id`
- `user_id`
- `provider`
- `provider_subject`
- `email`
- `created_at`

The first provider is `password`. OAuth providers can be added later without changing the user table.

`devices`

- `id`
- `user_id`
- `device_name`
- `device_public_key`
- `platform`
- `app_version`
- `created_at`
- `last_seen_at`
- `revoked_at`

`refresh_tokens`

- `id`
- `user_id`
- `device_id`
- `token_hash`
- `rotated_from_id`
- `created_at`
- `expires_at`
- `revoked_at`

`plans`

- `code`
- `name`
- `status`
- `price_provider`
- `price_id`
- `created_at`
- `updated_at`

`subscriptions`

- `id`
- `user_id`
- `plan_code`
- `status`
- `billing_provider`
- `billing_customer_id`
- `billing_subscription_id`
- `current_period_start`
- `current_period_end`
- `created_at`
- `updated_at`

`entitlements`

- `plan_code`
- `feature`
- `limit_value`
- `limit_unit`

`usage_counters`

- `user_id`
- `feature`
- `period_start`
- `period_end`
- `used_value`
- `updated_at`

### Product Library Tables

`paper_catalog`

- `id`
- `source_kind`
- `arxiv_id`
- `doi`
- `canonical_url`
- `title`
- `authors_json`
- `year`
- `created_at`
- `updated_at`

Only public/shareable metadata belongs in `paper_catalog`. arXiv papers can use this table. Non-arXiv private papers should not be promoted into the shared catalog unless the user explicitly enters a public DOI or URL.

`user_papers`

- `id`
- `user_id`
- `workspace_id`
- `catalog_paper_id`
- `source_kind`
- `arxiv_id`
- `display_title`
- `is_saved`
- `user_summary`
- `user_notes`
- `missing_local`
- `last_read_at`
- `created_at`
- `updated_at`
- `deleted_at`
- `revision`

For arXiv papers, `catalog_paper_id` points to shared metadata and `arxiv_id` is set. For non-arXiv local-private papers, `catalog_paper_id` is null, `source_kind = manual`, and `display_title` is the only synced paper descriptor.

`user_summary` and `user_notes` are nullable or empty at creation. They are private user fields and are included in metadata sync.

## PDF Sync Strategy

Default behavior:

- Public arXiv PDFs are not uploaded by the app. The backend stores arXiv ID and canonical URL. Other devices can redownload the public PDF when needed.
- User-imported private PDFs never upload in the baseline product.
- Non-arXiv private papers sync only `display_title`, folders, tags, `user_summary`, `user_notes`, and sync bookkeeping.
- Local file paths, private file hashes, PDF bytes, extracted text, page spans, and private abstracts stay local.
- If a synced non-arXiv paper appears on a second device, it is shown as a metadata-only library item with `missing_local = true` until the user imports the PDF on that device.
- Metadata, tags, notes, anchors, and sessions sync online only when they do not require uploading private PDF contents.

Encrypted private PDF backup is not part of this product baseline. If it is ever added, it must be a separate opt-in paid feature with its own design review, consent copy, encryption model, and deletion/export policy.

## Daily arXiv Offline Behavior

Settings should expose cache policies:

- Cache daily metadata automatically for the latest N days.
- Cache small thumbnails automatically.
- Cache large previews on demand or for saved/favorited papers.
- Cache all PDFs for a selected date/date range.
- Keep feed PDF cache under a configurable size budget.
- Clear disposable arXiv cache without touching saved library PDFs.

The app should show per-date cache state:

- metadata cached
- thumbnails cached
- large previews cached
- PDFs cached count / total count

When the user saves a paper that already exists in `arxiv_pdf_cache`, the app moves or hard-links the cached PDF into the durable library path and records `promoted_paper_id`.

## Security Design

### What EdgeOne Or A Similar Edge Layer Solves

An edge/proxy layer can:

- Hide direct origin addresses.
- Terminate TLS.
- Provide WAF and DDoS protection.
- Rate-limit abusive clients.
- Cache public feed assets.
- Route traffic to healthy origins.

It does not by itself ensure data safety. Data safety still requires application-level authentication, authorization, encryption, audit logging, and careful client storage.

### Required Security Controls

- HTTPS only in release builds.
- HSTS at the product domain.
- No bearer tokens in `UserDefaults`; use Keychain.
- No shared long-lived API token in the app bundle.
- Short-lived access tokens and refresh-token rotation.
- Device registration and token revocation.
- Ownership checks on every endpoint.
- Object-level authorization tests for every sync entity.
- Request-size and file-size limits.
- Per-user and per-device rate limits.
- Audit log for login, device registration, sync writes, entitlement changes, account export, account deletion, and destructive operations.
- Sensitive fields excluded from analytics and logs.
- Auth headers attached only to first-party API origin.
- Vendored MathJax or local renderer for offline/private builds.
- Development endpoints and ATS exceptions excluded from release configuration.

The design should be checked against OWASP API Security Top 10 2023 risks, especially object-level authorization, authentication, authorization for property-level writes, unrestricted resource consumption, unsafe third-party API consumption, and security misconfiguration.

## Product Operations

A commercial-ready backend needs product operations surfaces from the first release.

Required operational capabilities:

- Database migrations are versioned, reversible where practical, and tested against a snapshot-like fixture.
- Production data is backed up automatically with restore drills.
- Every request has a request ID. Security-sensitive failures are logged without passwords, tokens, private notes, or private paper content.
- Audit logs cover signup, email verification, login, password reset, device registration, token refresh, device revocation, sync writes, entitlement changes, admin actions, account deletion, and data export.
- Rate limits exist for signup, login, password reset, feed refresh, sync writes, and background jobs.
- Admin/support tools can view account status, plan, devices, recent errors, and usage counters without exposing private notes or private paper content by default.
- Account deletion creates a queued deletion job that removes user-owned backend rows and invalidates tokens. Local files on user devices remain under the user's control.
- Data export returns account metadata, library metadata, tags/folders, notes, and arXiv IDs. It does not include PDFs because PDFs are not uploaded.
- Metrics track API latency, sync failures, feed job failures, email delivery failures, signup/login conversion, active devices, and entitlement denials.

## User Setup Responsibilities

The implementation process should guide the product owner one step at a time. The user should not need to know the backend stack in advance.

The agent should ask for or help create these resources only when each phase needs them:

- Product domain or subdomain for the API.
- Production email sender for verification and password reset.
- PostgreSQL database.
- HTTPS deployment target.
- Edge/CDN or reverse proxy choice, such as EdgeOne, once the origin exists.
- Secret storage mechanism for production environment variables.
- Optional billing provider account when paid plans are ready to activate.
- Error monitoring destination and basic admin contact email.

Do not ask the user to choose every service up front. Each implementation phase must say exactly what the user needs to do, why it is needed, and how to verify it worked.

## Migration Plan

### Phase 1: Local Store V2

- Add the new schema alongside current tables.
- Migrate current `categories` to `folders`.
- Migrate current flat `tags` to root-level hierarchical `tags`.
- Migrate `papers` into V2 paper/file/source rows.
- Preserve current IDs where possible.
- Keep current app behavior unchanged after migration.

### Phase 2: Secure Connection Settings

- Move product API credentials to Keychain.
- Remove release HTTP defaults and ATS exceptions.
- Add a product API environment profile: development, staging, production.
- Restrict Authorization headers to the product API origin.

### Phase 3: Product Account Foundation

- Implement backend email/password signup, email verification, login, refresh-token rotation, password reset, and device registration.
- Add plan, subscription, entitlement, and usage-counter tables with internal/free/pro-placeholder seed data.
- Add app login/settings UI backed by Keychain credentials.
- Keep local-only mode available.
- Add account deletion and data export API placeholders before public launch, even if the UI is minimal.

### Phase 4: arXiv Import And Offline Cache

- Add robust arXiv ID/link extraction in the local app.
- Add daily metadata/thumb/full-image/PDF cache policies.
- Add per-date cache status and background prefetch jobs.
- Promote cached PDFs into saved library paths without duplicate downloads.

### Phase 5: Product Metadata Sync

- Implement sync outbox/pull cursor.
- Sync arXiv user papers, non-arXiv metadata-only placeholders, folders, tags, memberships, `user_summary`, `user_notes`, notes, anchors, annotations, and preferences.
- Do not upload private PDFs, private file hashes, extracted full text, local absolute paths, or private abstracts.
- Add conflict handling and a small Settings view for sync health/conflicts.

### Phase 6: Commercial Operations And Billing Activation

- Add production backup/restore runbooks, admin support view, audit review, usage dashboards, and entitlement-denial UX.
- Activate a payment provider only after metadata sync and account deletion/export are stable.
- Keep PDF backup out of scope unless a separate paid privacy-reviewed feature is approved.

## Verification

Local checks:

- Migration preserves current library, tags, categories, sessions, and cached arXiv papers.
- Offline launch works with network disabled.
- Cached daily feed opens without network.
- Cached feed PDF promotes into saved library without redownloading.
- Local-only mode works without account data.
- Keychain credentials survive relaunch and are not present in `UserDefaults`.

Sync checks:

- Push is idempotent.
- Pull cursor updates only after transaction success.
- Offline edits sync after reconnect.
- Concurrent tag membership changes merge deterministically.
- Folder/tag tree conflicts do not corrupt hierarchy.
- Deleting one entity on another device creates a tombstone and preserves recoverable local state until sync is acknowledged.

Backend checks:

- Invalid, expired, and revoked tokens are rejected.
- User A cannot read or modify User B objects by changing IDs.
- Sync payloads cannot change protected fields such as `user_id`, `owner_id`, `remote_revision`, or server timestamps.
- Private PDF upload endpoints do not exist in the baseline product.
- Public arXiv asset endpoints are size-limited and origin-checked.
- Origin is not directly exposed as a public development server.
- Email verification gates sync.
- Password reset revokes old refresh tokens.
- Entitlement checks reject over-limit device registration, sync writes, and prefetch jobs.
- Admin views hide private notes and paper content unless an explicit break-glass policy is later designed.

UI checks:

- Settings shows login state, sync state, cache state, and conflicts.
- Library still works offline.
- Discover shows cached date state.
- Bulk PDF cache has visible progress and cancellation.
- Error copy distinguishes auth failure, offline mode, cache miss, and remote service failure.

## Open Decisions

1. CodeArXiv should become an internal feed/recommendation service behind the product API. The app should stop exposing raw CodeArXiv base URL/token to normal users.
2. Library notes should be paper-level first; span/anchor-attached notes can build on the same table.
3. Full-text extracted spans should remain local-only until there is a clear need and explicit user consent to sync them.
4. Release builds should vendor or localize MathJax rather than relying on a public CDN.
5. Billing provider choice can wait until the internal/free/pro-placeholder entitlement model is working.
6. Team/workspace collaboration is not in the first sync release, but `workspace_id` should be present where it prevents a future migration.

## External References

- OWASP API Security Top 10 2023: https://owasp.org/API-Security/editions/2023/en/0x11-t10/
- Apple App Transport Security: https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity
- Apple Keychain Services: https://developer.apple.com/documentation/security/keychain_services/keychain_items/using_the_keychain_to_manage_user_secrets
- Tencent Cloud EdgeOne overview: https://www.tencentcloud.com/document/product/1145/47614
