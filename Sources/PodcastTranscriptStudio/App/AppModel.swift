import Foundation
import Combine

/// App-wide coordinator held in the SwiftUI environment. Owns the store, prompt service and
/// provider configuration, and exposes the high-level actions the views call (import episode,
/// fetch transcript, run prompt, chat). Keeps view code thin.
@MainActor
final class AppModel: ObservableObject {
    let store: Store
    let prompts: PromptService

    @Published var episodes: [Episode] = []
    @Published var searchText: String = ""
    @Published var providerConfigs: [LLMProviderConfig] = []
    @Published var lastError: String?

    private var transcriptProvider: TranscriptProvider = AppleTranscriptProvider()

    init(store: Store) {
        self.store = store
        self.prompts = PromptService(store: store)
    }

    func bootstrap() {
        prompts.start()
        seedDefaultProvidersIfNeeded()
        reloadProviders()
        refreshEpisodes()
    }

    // MARK: - Library

    func refreshEpisodes() {
        do { episodes = try store.episodes(matching: searchText) }
        catch { lastError = error.localizedDescription }
    }

    func podcast(for episode: Episode) -> Podcast? {
        try? store.podcast(id: episode.podcastID)
    }

    // MARK: - Import (PRD-FEAT-002)

    /// Parses an Apple Podcasts link and creates the podcast + episode shells, then kicks off
    /// a transcript fetch. Returns the created episode id on success.
    @discardableResult
    func importEpisode(fromLink raw: String) async -> String? {
        do {
            let link = try ApplePodcastsURLParser.parse(raw)
            let podcast = try store.upsertPodcast(Podcast(
                applePodcastID: link.podcastID,
                title: link.slugTitle?.capitalized ?? "Ukendt podcast",
                appleURL: link.podcastID.map { "https://podcasts.apple.com/podcast/id\($0)" }
            ))
            var episode = Episode(
                podcastID: podcast.id,
                appleEpisodeID: link.episodeID,
                title: link.slugTitle?.capitalized ?? "Ny episode",
                appleURL: link.normalizedURL
            )
            episode = try store.upsertEpisode(episode)
            refreshEpisodes()
            let saved = episode
            Task { await fetchTranscript(for: saved, link: link) }
            return episode.id
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Embeddings / semantic search (PRD-SEC-010)

    /// Builds an embedding provider for the chosen backend, resolving URL/key from the configs.
    func makeEmbeddingProvider(_ choice: EmbeddingChoice) -> EmbeddingProvider? {
        switch choice {
        case .apple:
            return AppleEmbeddingProvider()
        case .openAI:
            guard let cfg = providerConfigs.first(where: { $0.providerType == .openAICompatible }) else { return nil }
            let key = cfg.apiKeyKeychainRef.flatMap(Keychain.get) ?? ""
            return OpenAIEmbeddingProvider(baseURL: cfg.baseURL ?? "https://api.openai.com/v1",
                                           apiKey: key, model: "text-embedding-3-small")
        case .ollama:
            guard let cfg = providerConfigs.first(where: { $0.providerType == .ollama }) else { return nil }
            return OllamaEmbeddingProvider(baseURL: cfg.baseURL ?? "http://localhost:11434",
                                           model: "nomic-embed-text")
        }
    }

    /// Embeds a batch of texts, surfacing errors via `lastError`. Returns nil on failure.
    func embed(_ texts: [String], choice: EmbeddingChoice) async -> [[Float]]? {
        guard let provider = makeEmbeddingProvider(choice) else {
            lastError = "Embedding-provideren \(choice.displayName) er ikke konfigureret."
            return nil
        }
        do { return try await provider.embed(texts) }
        catch { lastError = error.localizedDescription; return nil }
    }

    // MARK: - Catalogue search (PRD-SEC-010)

    /// Imports a podcast/episode found via search, using its rich metadata directly, then tries
    /// to fetch a transcript. Returns the created episode id (episodes only).
    @discardableResult
    func importSearchResult(_ result: PodcastSearchResult) async -> String? {
        do {
            let podcast = try store.upsertPodcast(Podcast(
                applePodcastID: result.applePodcastID,
                title: result.podcastTitle,
                appleURL: result.applePodcastID.map { "https://podcasts.apple.com/podcast/id\($0)" }
            ))
            // For a show result with no specific episode, we can only add the podcast shell.
            guard result.kind == .episode else { refreshEpisodes(); return nil }

            var episode = Episode(
                podcastID: podcast.id,
                appleEpisodeID: result.appleEpisodeID,
                title: result.episodeTitle ?? "Episode",
                descriptionMarkdown: result.descriptionText,
                publishedAt: result.releaseDate,
                durationSeconds: result.durationSeconds,
                appleURL: result.appleURL ?? "",
                artworkURL: result.artworkURL
            )
            episode = try store.upsertEpisode(episode)
            refreshEpisodes()
            // Fetch the transcript in the background so import + dismiss are instant; the library
            // shows a "Henter…" status meanwhile.
            let saved = episode
            Task { await fetchTranscript(for: saved) }
            return episode.id
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Transcript (PRD-FEAT-003)

    func fetchTranscript(for episode: Episode, link: ApplePodcastsLink? = nil) async {
        var working = episode
        working.transcriptStatus = .refreshing
        working.transcriptLastAttemptedAt = .now
        working.transcriptError = nil
        working = (try? store.upsertEpisode(working)) ?? working
        refreshEpisodes()

        do {
            let fetched = try await transcriptProvider.fetchTranscript(for: episode, link: link)
            try saveFetched(fetched, for: episode)
            working.transcriptStatus = .loaded
            working.transcriptLastLoadedAt = .now
        } catch {
            // If a fresh fetch isn't available, self-heal by re-parsing the stored raw TTML with
            // the current parser — this fixes transcripts saved by older parser versions without
            // needing Apple's local cache to still be present.
            if reparseStoredTranscript(for: episode) {
                working.transcriptStatus = .loaded
                working.transcriptLastLoadedAt = .now
                working.transcriptError = nil
            } else if case TranscriptFetchError.notDownloaded = error {
                working.transcriptStatus = .availableNotDownloaded
                working.transcriptError = error.localizedDescription
            } else if case TranscriptFetchError.notFound = error {
                working.transcriptStatus = .notFound
                working.transcriptError = error.localizedDescription
            } else {
                working.transcriptStatus = .failed
                working.transcriptError = error.localizedDescription
            }
        }
        _ = try? store.upsertEpisode(working)
        refreshEpisodes()
    }

    /// Persists a freshly fetched transcript plus its ordered segments.
    private func saveFetched(_ fetched: FetchedTranscript, for episode: Episode) throws {
        let transcript = Transcript(
            episodeID: episode.id,
            languageCode: fetched.languageCode,
            markdown: fetched.markdown,
            plainText: fetched.plainText,
            rawPayloadJSON: fetched.rawPayload
        )
        let segments = fetched.segments.enumerated().map { index, seg in
            TranscriptSegment(
                transcriptID: transcript.id, startMs: seg.startMs, endMs: seg.endMs,
                text: seg.text, markdown: seg.text, sequenceIndex: index
            )
        }
        try store.saveTranscript(transcript, segments: segments)
    }

    /// Re-parses the stored original TTML payload (if any) with the current parser and overwrites
    /// the stored transcript. Returns true when it succeeded.
    @discardableResult
    func reparseStoredTranscript(for episode: Episode) -> Bool {
        guard let existing = try? store.transcript(episodeID: episode.id),
              let raw = existing.rawPayloadJSON,
              let reparsed = try? TTMLParser.parse(raw) else { return false }
        do {
            try saveFetched(reparsed, for: episode)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Providers (PRD-FEAT-008)

    func reloadProviders() {
        providerConfigs = (try? store.providerConfigs()) ?? []
    }

    private func seedDefaultProvidersIfNeeded() {
        guard (try? store.providerConfigs())?.isEmpty ?? true else { return }
        let defaults = [
            LLMProviderConfig(providerType: .openAICompatible, displayName: "OpenAI",
                              baseURL: "https://api.openai.com/v1", defaultModel: "gpt-4o-mini",
                              apiKeyKeychainRef: "openai-default"),
            LLMProviderConfig(providerType: .ollama, displayName: "Ollama (lokal)",
                              baseURL: "http://localhost:11434", defaultModel: "llama3.1"),
            LLMProviderConfig(providerType: .appleFoundationModels, displayName: "Apple Intelligence",
                              defaultModel: "system")
        ]
        for config in defaults { try? store.saveProviderConfig(config) }
    }

    /// Resolves the provider config to use for a given preferred provider string, or the first enabled.
    func resolveConfig(preferred: String?) -> LLMProviderConfig? {
        if let preferred, let match = providerConfigs.first(where: { $0.providerType.rawValue == preferred || $0.displayName.lowercased() == preferred.lowercased() }) {
            return match
        }
        return providerConfigs.first(where: \.isEnabled)
    }

    // MARK: - Prompt execution (PRD-FEAT-009 / PRD-FEAT-010)

    /// Runs a prompt against an episode's transcript with an explicit provider/model, persisting
    /// the output with the *actually used* provider/model (PRD-FEAT-009 acceptance).
    func runPrompt(_ prompt: Prompt, on episode: Episode, using config: LLMProviderConfig, model: String) async -> AIOutput? {
        do {
            guard let transcript = try store.transcript(episodeID: episode.id) else {
                lastError = "Episoden har ikke et transcript endnu."
                return nil
            }
            let filled = prompt.bodyMarkdown.replacingOccurrences(of: "{{transcript}}", with: transcript.plainText)
            let provider = LLMProviderFactory.make(from: config)
            let content = try await provider.complete(
                messages: [LLMMessage(role: .user, content: filled)], model: model
            )
            let output = AIOutput(
                episodeID: episode.id, promptID: prompt.id, promptVersion: prompt.version,
                providerType: config.providerType, model: model, inputScope: .episode,
                inputReferenceJSON: "{\"transcriptId\":\"\(transcript.id)\"}",
                outputMarkdown: content
            )
            try store.saveOutput(output)
            return output
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// A prepared prompt run: the provider and filled messages ready to stream.
    struct PreparedRun {
        let provider: LLMProvider
        let messages: [LLMMessage]
        let transcriptID: String
    }

    /// Builds the provider + filled messages for a streaming prompt run. `overrideText` runs the
    /// prompt on just that text (e.g. a transcript selection) instead of the whole transcript
    /// (PRD-FEAT-004 selection → prompt). Returns nil if there is nothing to run on.
    func preparePromptRun(_ prompt: Prompt, on episode: Episode, using config: LLMProviderConfig,
                          overrideText: String? = nil) -> PreparedRun? {
        let sourceText: String
        let transcriptID: String
        if let overrideText, !overrideText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sourceText = overrideText
            transcriptID = (try? store.transcript(episodeID: episode.id))?.id ?? ""
        } else {
            guard let transcript = try? store.transcript(episodeID: episode.id) else {
                lastError = "Episoden har ikke et transcript endnu."
                return nil
            }
            sourceText = transcript.plainText
            transcriptID = transcript.id
        }
        let filled = prompt.bodyMarkdown.replacingOccurrences(of: "{{transcript}}", with: sourceText)
        return PreparedRun(
            provider: LLMProviderFactory.make(from: config),
            messages: [LLMMessage(role: .user, content: filled)],
            transcriptID: transcriptID
        )
    }

    /// Persists a (possibly streamed, possibly stopped-early) prompt output with the provider/model
    /// actually used (PRD-FEAT-009/010).
    @discardableResult
    func savePromptOutput(text: String, prompt: Prompt, episode: Episode,
                          config: LLMProviderConfig, model: String, transcriptID: String,
                          scope: InputScope = .episode) -> AIOutput {
        let output = AIOutput(
            episodeID: episode.id, promptID: prompt.id, promptVersion: prompt.version,
            providerType: config.providerType, model: model, inputScope: scope,
            inputReferenceJSON: "{\"transcriptId\":\"\(transcriptID)\"}",
            outputMarkdown: text
        )
        try? store.saveOutput(output)
        refreshEpisodes()
        return output
    }
}
