import SwiftUI

/// Transcript workspace with `Tekst` (reading) and `Tidskoder` (timecoded segments) tabs
/// (PRD-FEAT-004). Both tabs support copy as formatted text and raw Markdown (PRD-FEAT-005).
struct TranscriptView: View {
    @EnvironmentObject var model: AppModel
    let episode: Episode

    enum Mode: String, CaseIterable, Identifiable {
        case text = "Tekst"
        case timecodes = "Tidskoder"
        var id: String { rawValue }
    }
    @State private var mode: Mode = .text
    @State private var transcript: Transcript?
    @State private var segments: [TranscriptSegment] = []
    @State private var selectedSegmentID: String?
    @State private var runningPrompt: Prompt?
    @State private var selectionForRun: String?
    @State private var find = FindState()

    // Semantic search state (embeddings over segments).
    @State private var embeddingChoice: EmbeddingChoice = .apple
    @State private var embeddingModel = ""
    @State private var embeddingModels: [String] = []
    @State private var isLoadingEmbeddingModels = false
    @State private var docEmbeddings: [[Float]] = []
    @State private var docEmbedKey = ""
    @State private var semanticMatches: [(index: Int, score: Float)] = []
    @State private var isSemanticRunning = false
    @State private var semanticTask: Task<Void, Never>?

    /// Literal find matches across the timecoded segments (only when that tab is active).
    private var timecodeDist: (total: Int, activeCard: Int, activeLocal: Int) {
        guard find.isPresented, mode == .timecodes, !find.semantic, !find.query.isEmpty else { return (0, -1, -1) }
        return TextSearch.distribute(query: find.query, texts: segments.map(\.text), active: find.current)
    }

    /// segment index → its rank in the semantic results (for highlighting).
    private var semanticRankByIndex: [Int: Int] {
        Dictionary(uniqueKeysWithValues: semanticMatches.enumerated().map { ($0.element.index, $0.offset) })
    }

    /// The segment id to scroll to for the active match (literal or semantic).
    private var activeSegmentID: String? {
        if find.semantic {
            guard find.current < semanticMatches.count else { return nil }
            let idx = semanticMatches[find.current].index
            return segments.indices.contains(idx) ? segments[idx].id : nil
        } else {
            guard timecodeDist.activeCard >= 0, segments.indices.contains(timecodeDist.activeCard) else { return nil }
            return segments[timecodeDist.activeCard].id
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                Spacer()
                Button { toggleFind() } label: { Image(systemName: "magnifyingglass") }
                    .help(mode == .text ? "Find i teksten (⌘F)" : "Find i tidskoder (⌘F)")
                if let transcript {
                    CopyIconMenu(markdown: { copyMarkdown(transcript) })
                }
            }
            .padding(12)
            Divider()

            if find.isPresented {
                FindBar(state: $find, semanticEnabled: true, embeddingChoice: $embeddingChoice,
                        embeddingModel: $embeddingModel, embeddingModels: embeddingModels,
                        isLoadingEmbeddingModels: isLoadingEmbeddingModels,
                        reloadEmbeddingModels: loadEmbeddingModels,
                        isRunning: isSemanticRunning, onRunSemantic: runSemantic)
                    .onChange(of: find.query) { _, _ in if !find.semantic { find.reset() } }
                    .onChange(of: find.semantic) { _, sem in
                        find.current = 0; find.matchCount = 0; semanticMatches = []
                        if sem && mode == .text { mode = .timecodes }
                        if sem { loadEmbeddingModels() }
                    }
                    .onChange(of: embeddingChoice) { _, _ in
                        docEmbeddings = []; docEmbedKey = ""; embeddingModel = ""; loadEmbeddingModels()
                    }
            }

            if transcript == nil {
                emptyState
            } else if mode == .text {
                // Selection-aware, right-click to run a prompt on the selection (or all).
                SelectableTranscriptView(
                    markdown: transcript!.markdown,
                    prompts: model.prompts.prompts.filter { $0.validationStatus != .invalid },
                    onRun: { prompt, selected in
                        selectionForRun = selected
                        runningPrompt = prompt
                    },
                    highlightQuery: (find.isPresented && !find.semantic) ? find.query : "",
                    activeMatch: find.current,
                    onMatchCount: { if mode == .text, !find.semantic, find.matchCount != $0 { find.matchCount = $0 } }
                )
            } else {
                timecodeList
            }
        }
        .background {
            Button("") { toggleFind() }.keyboardShortcut("f", modifiers: .command).hidden()
        }
        // Switching tab re-scopes the search to the newly active tab.
        .onChange(of: mode) { _, _ in if !find.semantic { find.current = 0; find.matchCount = 0 } }
        .onChange(of: timecodeDist.total) { _, total in
            if mode == .timecodes, !find.semantic, find.matchCount != total { find.matchCount = total }
        }
        .task(id: episode.id) { load() }
        .sheet(item: $runningPrompt) { prompt in
            PromptRunSheet(prompt: prompt, episode: episode, selectionText: selectionForRun)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.alignleft").font(.largeTitle).foregroundStyle(.secondary)
            if episode.transcriptStatus == .availableNotDownloaded {
                Text("Findes hos Apple – ikke hentet lokalt endnu")
                    .font(.headline)
                Text("Åbn episoden i Apple Podcasts og vis transskriptionen, så cachelagrer Apple den. Tryk derefter \"Indlæs igen\".")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
                HStack {
                    Button("Åbn i Podcasts") { ExternalActions.openInPodcasts(episode: episode) }
                        .buttonStyle(.borderedProminent)
                    Button("Indlæs igen") { Task { await model.fetchTranscript(for: episode) } }
                }
            } else {
                Text(episode.transcriptStatus == .refreshing ? "Henter transcript…" : "Intet transcript endnu.")
                    .foregroundStyle(.secondary)
                if episode.transcriptStatus != .refreshing {
                    Button("Hent transcript") { Task { await model.fetchTranscript(for: episode) } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Timecoded segment list; a selected segment enables "open at this point" (PRD-FEAT-013.2).
    /// Find highlights matching segments (orange) and scrolls to the active one.
    private var timecodeList: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedSegmentID) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    HStack(alignment: .top, spacing: 10) {
                        if let start = segment.startMs {
                            Button(TimeFormatting.clock(ms: start)) {
                                ExternalActions.openInPodcasts(episode: episode, atMs: start)
                            }
                            .buttonStyle(.link)
                            .font(.caption.monospacedDigit())
                            .frame(width: 64, alignment: .leading)
                        }
                        segmentText(segment, index: index)
                    }
                    .tag(segment.id)
                    .id(segment.id)
                    .contextMenu {
                        Button("Kopiér segment") { Clipboard.copyMarkdown(segment.text) }
                        if let start = segment.startMs {
                            Button("Åbn i Podcasts her") {
                                ExternalActions.openInPodcasts(episode: episode, atMs: start)
                            }
                        }
                    }
                }
            }
            .onChange(of: find.current) { _, _ in
                if let id = activeSegmentID { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    /// A segment's text, highlighting literal substring matches or (in semantic mode) shading the
    /// whole segment orange when it's a semantic result.
    @ViewBuilder
    private func segmentText(_ segment: TranscriptSegment, index: Int) -> some View {
        if find.isPresented && find.semantic {
            let rank = semanticRankByIndex[index]
            Text(segment.text)
                .textSelection(.enabled)
                .padding(.vertical, 2).padding(.horizontal, rank != nil ? 5 : 0)
                .background {
                    if let rank {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(rank == find.current ? Color.netsiOrange : Color.netsiOrange.opacity(0.3))
                    }
                }
                .foregroundStyle(rank == find.current ? .black : .primary)
        } else {
            Text(TextSearch.highlighted(
                segment.text,
                query: find.isPresented ? find.query : "",
                activeLocal: index == timecodeDist.activeCard ? timecodeDist.activeLocal : -1
            ))
            .textSelection(.enabled)
        }
    }

    /// Loads candidate embedding models for the chosen backend, and picks a sensible default
    /// (prefers a model whose name mentions "embed").
    private func loadEmbeddingModels() {
        guard embeddingChoice != .apple else { embeddingModels = []; return }
        isLoadingEmbeddingModels = true
        Task {
            let models = await model.listEmbeddingModels(embeddingChoice)
            embeddingModels = models
            if embeddingModel.isEmpty || !models.contains(embeddingModel) {
                embeddingModel = models.first(where: { $0.localizedCaseInsensitiveContains("embed") })
                    ?? AppModel.defaultEmbeddingModel(embeddingChoice)
            }
            isLoadingEmbeddingModels = false
        }
    }

    /// Runs embeddings-based semantic search over the segments (PRD-SEC-010). Segment vectors are
    /// cached per transcript + embedding provider + model; only the query is re-embedded each run.
    private func runSemantic() {
        let query = find.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !segments.isEmpty else { semanticMatches = []; find.matchCount = 0; return }
        if mode == .text { mode = .timecodes }
        semanticTask?.cancel()
        isSemanticRunning = true
        semanticTask = Task {
            let texts = segments.map(\.text)
            let key = (transcript?.id ?? "") + "|" + embeddingChoice.rawValue + "|" + embeddingModel
            if docEmbedKey != key || docEmbeddings.count != texts.count {
                guard let docs = await model.embed(texts, choice: embeddingChoice, model: embeddingModel), !Task.isCancelled else {
                    isSemanticRunning = false; return
                }
                docEmbeddings = docs
                docEmbedKey = key
            }
            guard let queryVector = (await model.embed([query], choice: embeddingChoice, model: embeddingModel))?.first, !Task.isCancelled else {
                isSemanticRunning = false; return
            }
            semanticMatches = SemanticSearch.rank(query: queryVector, docs: docEmbeddings)
            find.current = 0
            find.matchCount = semanticMatches.count
            isSemanticRunning = false
        }
    }

    private func toggleFind() {
        find.isPresented.toggle()
        if !find.isPresented { find.query = "" }
    }

    private func load() {
        transcript = try? model.store.transcript(episodeID: episode.id)
        if let transcript {
            segments = (try? model.store.segments(transcriptID: transcript.id)) ?? []
        } else {
            segments = []
        }
    }

    private func copyMarkdown(_ transcript: Transcript) -> String {
        mode == .text
            ? MarkdownSerializer.transcript(transcript, episodeTitle: episode.title)
            : MarkdownSerializer.timecoded(segments, episodeTitle: episode.title)
    }
}
