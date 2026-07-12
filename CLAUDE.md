# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current state

The v1 app is implemented as a **SwiftPM executable package** (`Package.swift`) so it can be
compiled and unit-tested from the CLI. All PRD v1 features have a working implementation.

- `development/prd/prd.md` — the authoritative product spec (in Danish). Still the source of truth.
- `Sources/PodcastTranscriptStudio/` — the app (see layout below).
- `Tests/PodcastTranscriptStudioTests/` — unit tests for the deterministic logic.

### Commands

```bash
swift build          # compile the whole app + library
swift test           # run all unit tests
swift test --filter StoreTests/testUpsertDeduplicatesByAppleEpisodeID   # single test
.build/debug/PodcastTranscriptStudio   # launch the app (creates DB + seeds prompts on first run)
```

Runtime data lives in `~/Library/Application Support/PodcastTranscriptStudio/`
(`library.sqlite` + `Prompts/`). Delete that folder to reset first-run state.

Language mode is pinned to Swift 5 (`swiftSettings: [.swiftLanguageMode(.v5)]`) to keep the large
SwiftUI/AppKit codebase free of strict-concurrency friction. `SQLite3` is linked as the system
library (`.linkedLibrary("sqlite3")`), not a package dependency. Packaging as a distributable
`.app` bundle (Info.plist, code signing) is the remaining step and would move to an Xcode project.

### Source layout

- `App/` — `@main` entry (`PodcastTranscriptStudioApp`) and `AppModel` (the environment coordinator).
- `Database/` — `Database` (SQLite C-API wrapper), `Schema` (migrations + FTS5), `Store` (data facade), `Store+Decode` (row decoders).
- `Models/` — all PRD entities as value types.
- `Services/` — `Transcript/` (provider protocol + Apple TTML reader), `LLM/` (provider protocol + OpenAI/Ollama/Apple impls), `Prompts/` (loader + folder watcher), `ExternalActions`, `ChatController`, `ExportService`.
- `Markdown/` — `MarkdownSerializer`, `Frontmatter` parser.
- `Views/` — SwiftUI screens (library, episode detail, transcript tabs, prompts, chat, settings) + shared copy controls.
- `Resources/DefaultPrompts/` — seeded into the user's prompt folder on first run.

## What is being built

**Podcast Transcript Studio** — a local-first, BYOK (bring-your-own-key), no-login **SwiftUI macOS app** for fetching, storing, and reusing Apple Podcasts transcripts, with prompt-driven LLM workflows on top of a local transcript archive.

Planned stack (from PRD §PRD-SEC-004): SwiftUI (macOS), local-first MVVM or reducer-based state, **SQLite** with **FTS5** full-text search, macOS **Keychain** for API keys, and a pluggable LLM provider layer.

## Architecture the code must follow

These are load-bearing design decisions from the PRD. Preserve them when writing code:

- **Markdown is the native internal text format.** Transcripts, AI outputs, chat messages, and metadata are all stored and manipulated as Markdown.
- **Copy-everything principle** (PRD-FEAT-005): every user-facing piece of content must be copyable both as display-formatted text *and* as raw Markdown, via a shared copy-action component and a single Markdown serializer.
- **Dual transcript storage:** persist both Markdown (`Transcript.markdown`) *and* structured timecoded `TranscriptSegment` records. Segments are required for the timecoded view and `.srt` export — never collapse to Markdown-only.
- **Transcript source is isolated behind a `TranscriptProvider` interface.** Apple transcript retrieval is treated as a fragile integration that may change; keep it swappable and behind this abstraction.
- **LLM providers sit behind a provider protocol** with three planned implementations: OpenAI-compatible API, local Ollama (`localhost:11434`), and Apple Foundation Models (Apple Intelligence, availability-gated). Prompts declare a `preferredProvider`/`preferredModel` in frontmatter, but the user can override at run time — and the *actually used* provider/model is saved with every output.
- **Prompts are `.md` files in a local folder**, each with YAML frontmatter (`version`, `preferredProvider`, `preferredModel`, `title`, `description`, `outputType`). A file watcher turns new/changed files into app actions live; a validator + guided fix flow handles malformed frontmatter.
- **Secrets never go in SQLite.** API keys live in macOS Keychain; SQLite stores only a Keychain reference. Exports exclude API keys by default.

## Data model

The full conceptual schema is in PRD §PRD-SEC-005. Core entities and relationships:

```
Podcast 1—* Episode 1—1 Transcript 1—* TranscriptSegment
Episode 1—* AIOutput   *—1 Prompt
Episode 1—* ChatSession 1—* ChatMessage
LLMProviderConfig (standalone provider settings)
```

Use Apple `podcast_id`, `episode_id`, and original URL as dedupe keys on import/merge.

## Delivery phases

The PRD (§PRD-SEC-008) sequences all v1 work into phases v1.1–v1.6 (Foundation → Transcript Core → Prompt System → LLM Execution → Chat & Archive → Export/Import & External Actions). All are part of v1; the phasing is build order, not scope-cutting. Follow this order unless told otherwise.

## Requirement traceability

The PRD uses stable IDs: sections `PRD-SEC-00X`, features `PRD-FEAT-0XX`, sub-tasks `PRD-FEAT-0XX.Y`. Reference these IDs in commits and PRs so work traces back to the spec.

## Language note

The PRD and product UI copy are in **Danish**; keep user-facing strings consistent with the PRD's wording. Code identifiers and this file are in English.
