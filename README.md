# Podcast Transcript Studio

A **local-first macOS app** (SwiftUI) for fetching, storing, reading and reusing Apple Podcasts
transcripts — and running prompt-driven LLM workflows on top of your personal transcript archive.

Paste an Apple Podcasts episode link → the app fetches Apple's transcript, stores it locally in
SQLite, and lets you read it, copy it (as formatted text **or** raw Markdown), run your own
prompts on it, chat with the episode or the whole archive, and export to Markdown/SRT.

- **Local-first · BYOK · no login.** Everything stays on your Mac. You use your own LLM keys.
- **Markdown is the native format.** All content can be copied and exported as Markdown.
- **Your own prompts.** Prompts are `.md` files in a folder — new files automatically become
  app actions.
- **Bring any LLM.** OpenAI-compatible API, local Ollama, or Apple Intelligence (Foundation
  Models). API keys are stored in the macOS Keychain.
- **English or Danish UI.** Choose the language in Settings; defaults to your macOS language.

The full product specification lives in the [PRD](development/prd/prd.md) (in Danish).

## Features

- 📚 Episode library with search (full-text via SQLite FTS5) and sorting
- 🔎 Search the Apple Podcasts catalogue (iTunes Search API) and import directly
- 📝 Transcript in two views: readable **Text** and timecoded **Timecodes**
- 📋 Copy anything — as display-friendly text and as raw Markdown
- 🔍 Find-in-text (literal) and semantic (embeddings) search with highlight + prev/next
- ⚡️ Prompt folder with default prompts, a live file-watcher and a validation/fix flow
- 🤖 Run prompts with a preferred LLM (overridable) and token streaming + Stop — output is saved automatically
- 💬 Chat with either the current episode or the whole archive
- 📤 Export to Markdown, `.srt`, batch export and a full backup package (without API keys)
- 🎧 Open in Apple Podcasts (also at a selected timecode), subscribe, and Google search

## Requirements

- macOS 14 or newer
- Swift 6 / Xcode toolchain (`swift --version`)

## Install & run

### Download a prebuilt app

Grab the latest `.app` from [Releases](https://github.com/netsi1964/netsi-podcast-transcript/releases)
(Apple Silicon). It isn't signed with an Apple Developer ID, so on first launch **right-click →
Open**, or run `xattr -dr com.apple.quarantine "/Applications/Podcast Transcript Studio.app"`.

### Build from source

The app is a SwiftPM package, so it can be built and tested from the terminal:

```bash
git clone https://github.com/netsi1964/netsi-podcast-transcript.git
cd netsi-podcast-transcript

swift build        # compile
swift test         # run unit tests
swift run          # launch the app
./scripts/build-app.sh   # build a double-clickable dist/Podcast Transcript Studio.app
```

On first launch the app automatically creates:

- the database `~/Library/Application Support/PodcastTranscriptStudio/library.sqlite`
- the prompt folder `~/Library/Application Support/PodcastTranscriptStudio/Prompts/`
  with a set of default prompts

> To reset to "first launch", delete the folder
> `~/Library/Application Support/PodcastTranscriptStudio/`.

### Configure an LLM

Open **Settings** in the app:

- **OpenAI-compatible:** enter base URL + API key (stored in Keychain) + model
- **Ollama:** run `ollama serve` locally — the app finds it at `http://localhost:11434`
- **Apple Intelligence:** used automatically if your Mac supports Foundation Models

## Transcript search

In the transcript tab, **⌘F** opens a search bar with two modes:

- **Text:** ordinary keyword search that highlights matches (orange) with previous/next.
- **Semantic:** finds passages by *meaning* rather than exact words. Describe what you're looking
  for, press Enter, and the most relevant segments are ranked and highlighted. A relevance slider
  tunes how strict the matching is (it re-ranks live).

### Getting an embedding model for semantic search

Semantic search needs an **embedding model** (it turns text into vectors). Pick a backend in the
search bar:

- **Apple (on-device)** — recommended starting point. Uses macOS' built-in `NaturalLanguage`
  model. Requires **no** installation or key and works offline.
- **Ollama (local)** — requires an embedding model. Ordinary chat models (llama, qwen, gemma …)
  **cannot** produce embeddings and will error. Install one of:

  ```bash
  ollama pull nomic-embed-text     # light and fast (274 MB)
  ollama pull mxbai-embed-large    # larger, often better quality
  ```

  Then press 🔄 in the search bar to reload the list. Only embedding models are shown.
- **OpenAI** — uses `text-embedding-3-small` by default (requires an API key in Settings).

The model list in the search bar shows only likely embedding models; use "Custom…" to type a
model id manually.

## Examples

See real output from the app in [development/examples/](development/examples/):

- [Key quotes](development/examples/key-quotes-80000-hours-neel-nanda.md) — the built-in
  `key-quotes.md` prompt run on an 80,000 Hours episode (OpenAI · gpt-4.1).
- [Study notes](development/examples/study-notes-80000-hours-neel-nanda.md) — the built-in
  `study-notes.md` prompt on the same episode (OpenAI · gpt-4.1).

## Project structure

```
Sources/PodcastTranscriptStudio/
  App/            @main entry + AppModel (app coordinator)
  Localization/   runtime English/Danish localization
  Database/       SQLite wrapper, schema + FTS5, Store (data layer)
  Models/         PRD entities as value types
  Services/       transcript provider, LLM/embedding providers, prompts, export, chat, search
  Markdown/       Markdown serialization + frontmatter parser
  Views/          SwiftUI screens (library, episode, transcript, prompts, chat, settings)
  Resources/      default prompts seeded on first launch
Tests/            unit tests for the deterministic logic
```

See [CLAUDE.md](CLAUDE.md) for architecture details and developer notes.

## Status

The full PRD v1 is implemented, builds, and all unit tests pass. Releases ship a double-clickable
`.app` (built automatically by GitHub Actions on each version tag). Remaining work: Developer ID
signing/notarization for distribution to other machines, and finishing UI localization coverage.
