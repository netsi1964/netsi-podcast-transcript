## Download (macOS, Apple Silicon)

Download **PodcastTranscriptStudio-macos-arm64.zip** below, unzip, and move *Podcast Transcript Studio.app* to your Applications folder.

**First launch:** the app isn't signed with an Apple Developer ID, so macOS Gatekeeper will block it the first time. To open it:
- **Right-click** (or Ctrl-click) the app → **Open** → **Open** in the dialog. You only need to do this once.
- If macOS says the app is "damaged", run this once in Terminal: `xattr -dr com.apple.quarantine "/Applications/Podcast Transcript Studio.app"`

Requires macOS 14 or newer. Alternatively, build from source with `swift run`.

---

Podcast Transcript Studio — a local-first SwiftUI macOS app for fetching, storing and reusing Apple Podcasts transcripts with prompt-driven LLM workflows.

- Episode library with SQLite/FTS5 search and Apple Podcasts catalogue search
- Apple TTML transcript retrieval (behind a swappable provider)
- Reading + timecoded transcript views, copy as text/Markdown
- Prompt folder (.md + frontmatter) with live watching and a fix flow
- LLM providers: OpenAI-compatible, Ollama, Apple Foundation Models — live model lists, streaming + Stop
- Chat over an episode or the whole archive
- Text and semantic (embeddings) find, with highlight + prev/next
- Export/import (Markdown, SRT, batch, backup)
