# CodeArXiv Discover And Library Design

Status: superseded by `docs/superpowers/specs/2026-04-29-paper-codex-local-first-arxiv-design.md`.

This document describes the previous CodeArXiv-server-backed direction. The current product direction is local-first: Paper Codex should query arXiv directly, store user data locally, and use CodeArXiv only as an implementation reference.

## Goal

Paper Codex should treat CodeArXiv as the server-side arXiv feed and preference engine, while the macOS app remains the local reader, library, cache, and Codex chat surface.

## Behavior

- Discover shows a CodeArXiv-like paper card flow with stable thumbnail, title, summary, tag, similarity, Add, Open, and per-paper download state. Cards must not overlap at normal desktop widths.
- CodeArXiv provides sorted feed data for a configured username. The server applies the user's category filters, tag whitelist/blacklist, favorite-folder similarity vectors, and favorite membership before the app renders the feed.
- Settings is a standalone page. It owns CodeArXiv connection, username, token, editable similarity folders, editable category/tag whitelist/blacklist filters, quick prompts, storage path display, cache controls, and favorite migration.
- Library rows show a five-page thumbnail strip for PDFs when available. The left/list split position persists across route changes.
- Open downloads an unsaved paper into disposable cache and opens the reader/chat. Save moves it into the configured library path.
- Quick prompts are user-editable title/content pairs. The chat status area exposes a dropdown of prompt titles; choosing one sends the matching content.
- Migrating the `caopu` CodeArXiv favorites creates local folders/categories and imports the favorited PDFs into the saved library, preserving folder membership and tags.

## Data Model

- CodeArXiv API returns optional user fields on feed papers: `similarity`, `filter_group`, and `is_favorite`.
- CodeArXiv API exposes a user-state payload with filters, tag options, favorites, favorite paper IDs, and favorite paper metadata.
- CodeArXiv API exposes a Bearer-token-protected filter update endpoint so Paper Codex can edit categories, whitelist tags, blacklist tags, similarity favorite IDs, and language preference without using browser CSRF.
- Paper Codex stores quick prompts and CodeArXiv username in local user defaults.
- Paper Codex reuses local categories for remote favorite folders and local tags for remote paper tags.
- PDF thumbnails are cached under application support and can be regenerated from saved PDFs.

## Verification

- Remote tests cover token protection, user-state export, favorite metadata, filters, and similarity/group ordering. If `pytest` is unavailable on the remote `.venv`, use `py_compile` plus a real Flask test-client smoke for the same API paths.
- Local core checks cover decoding user fields, applying similarity/group sorting, quick prompt persistence, and thumbnail cache generation.
- Computer Use is the required UI test path for Discover layout, Settings layout stability, full-row navigation clicks, Open spinner/progress, quick prompt sending, Library thumbnails, and splitter persistence.

## UI Reference

Image generation reference:
`/Users/chunqiu/.codex/generated_images/019dd24a-f35b-7323-b5d1-f0418443ff48/ig_0f9ca81e58aa63fe0169f050c81a4c81918490ea1ec2113157.png`
