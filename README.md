# Podcast Transcript Studio

En **lokal-first macOS-app** (SwiftUI) til at hente, gemme, læse og genbruge
Apple Podcasts-transskriptioner — og køre prompt-drevne LLM-workflows oven på dit
personlige transcript-arkiv.

Indsæt et Apple Podcasts episode-link → appen henter Apples transcript, gemmer det lokalt i
SQLite, og lader dig læse det, kopiere det (som formateret tekst **eller** rå Markdown), køre
dine egne prompts på det, chatte med episoden eller hele arkivet, og eksportere til Markdown/SRT.

- **Lokal-first · BYOK · ingen login.** Alt ligger på din Mac. Du bruger dine egne LLM-nøgler.
- **Markdown er det native format.** Alt indhold kan kopieres og eksporteres som Markdown.
- **Dine egne prompts.** Prompts er `.md`-filer i en folder — nye filer bliver automatisk til
  app-handlinger.
- **Frit LLM-valg.** OpenAI-kompatibel API, lokal Ollama, eller Apple Intelligence
  (Foundation Models). API-nøgler gemmes i macOS Keychain.

Fuld produktspecifikation ligger i [PRD'en](development/prd/prd.md).

## Funktioner

- 📚 Episodebibliotek med søgning (fuldtekst via SQLite FTS5) og sortering
- 🔗 Import via Apple Podcasts episode-link (parser podcast-/episode-id)
- 📝 Transcript i to visninger: læsevenlig **Tekst** og tidskodede **Tidskoder**
- 📋 Kopiér alt — som visningsvenlig tekst og som rå Markdown
- ⚡️ Prompt-folder med default prompts, live file-watcher og validerings-/fix-flow
- 🤖 Kør prompts med foretrukken LLM (kan overrules) — output gemmes automatisk som historik
- 💬 Chat med enten aktuel episode eller hele arkivet
- 📤 Eksport til Markdown, `.srt`, batch-eksport og fuld backup-pakke (uden API-nøgler)
- 🎧 Åbn i Apple Podcasts (også ved valgt tidskode), subscribe, og Google-søgning

## Krav

- macOS 14 eller nyere
- Swift 6 / Xcode-toolchain (`swift --version`)

## Install & kør

Appen er bygget som en SwiftPM-pakke, så den kan bygges og testes fra terminalen:

```bash
git clone https://github.com/netsi1964/netsi-podcast-transcript.git
cd netsi-podcast-transcript

swift build        # kompilér
swift test         # kør unit-tests (13 stk.)
swift run          # start appen
```

Ved første start opretter appen automatisk:

- databasen `~/Library/Application Support/PodcastTranscriptStudio/library.sqlite`
- prompt-folderen `~/Library/Application Support/PodcastTranscriptStudio/Prompts/`
  med et sæt default prompts

> Vil du nulstille til "første start", så slet mappen
> `~/Library/Application Support/PodcastTranscriptStudio/`.

### Konfigurér en LLM

Åbn **Indstillinger** i appen:

- **OpenAI-kompatibel:** indtast base-URL + API key (gemmes i Keychain) + model
- **Ollama:** kør `ollama serve` lokalt — appen finder den på `http://localhost:11434`
- **Apple Intelligence:** bruges automatisk hvis din Mac understøtter Foundation Models

## Søgning i transcript

I transcript-fanen åbner **⌘F** en søgelinje med to tilstande:

- **Tekst:** almindelig ordsøgning der fremhæver forekomster (orange) med forrige/næste.
- **Semantisk:** finder afsnit efter *betydning* i stedet for præcise ord. Du beskriver hvad du
  leder efter, trykker Enter, og de mest relevante segmenter rangeres og fremhæves.

### Sådan får du en embedding-model til semantisk søgning

Semantisk søgning kræver en **embedding-model** (den omdanner tekst til vektorer). Vælg backend i
søgelinjen:

- **Apple (på enheden)** — anbefalet start. Bruger macOS' indbyggede `NaturalLanguage`-model.
  Kræver **ingen** installation eller nøgle og virker offline.
- **Ollama (lokal)** — kræver en embedding-model installeret. Almindelige chat-modeller (llama,
  qwen, gemma …) kan **ikke** lave embeddings og giver fejl. Installer én af disse:

  ```bash
  ollama pull nomic-embed-text     # let og hurtig (274 MB)
  ollama pull mxbai-embed-large    # større, ofte bedre kvalitet
  ```

  Tryk derefter 🔄 i søgelinjen for at genindlæse listen. Kun embedding-modeller vises.
- **OpenAI** — bruger `text-embedding-3-small` som standard (kræver API key i Indstillinger).

Modellisten i søgelinjen viser kun sandsynlige embedding-modeller; brug "Egen…" hvis du vil
skrive et model-id manuelt.

## Projektstruktur

```
Sources/PodcastTranscriptStudio/
  App/          @main-entry + AppModel (app-koordinator)
  Database/     SQLite-wrapper, skema + FTS5, Store (datalag)
  Models/       PRD-entiteter som value types
  Services/     Transcript-provider, LLM-providere, prompts, export, chat
  Markdown/     Markdown-serialisering + frontmatter-parser
  Views/        SwiftUI-skærme (bibliotek, episode, transcript, prompts, chat, settings)
  Resources/    Default prompts der seedes ved første start
Tests/          Unit-tests for den deterministiske logik
```

Se [CLAUDE.md](CLAUDE.md) for arkitektur-detaljer og udviklernoter.

## Status

Hele PRD v1 er implementeret og bygger; alle unit-tests er grønne. Det resterende er
pakketrin: et Xcode `.app`-bundle med kodesignering til distribution, samt at verificere den
præcise sti til Apples lokale transcript-cache på den konkrete maskine.
