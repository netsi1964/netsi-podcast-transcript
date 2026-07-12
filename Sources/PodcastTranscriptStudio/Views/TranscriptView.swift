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
                    .help("Find i teksten (⌘F)")
                if let transcript {
                    CopyIconMenu(markdown: { copyMarkdown(transcript) })
                }
            }
            .padding(12)
            Divider()

            if find.isPresented {
                FindBar(state: $find)
                    .onChange(of: find.query) { _, _ in find.reset() }
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
                    highlightQuery: find.isPresented ? find.query : "",
                    activeMatch: find.current,
                    onMatchCount: { if find.matchCount != $0 { find.matchCount = $0 } }
                )
            } else {
                timecodeList
            }
        }
        .background {
            Button("") { toggleFind() }.keyboardShortcut("f", modifiers: .command).hidden()
        }
        .task(id: episode.id) { load() }
        .sheet(item: $runningPrompt) { prompt in
            PromptRunSheet(prompt: prompt, episode: episode, selectionText: selectionForRun)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.alignleft").font(.largeTitle).foregroundStyle(.secondary)
            Text(episode.transcriptStatus == .refreshing ? "Henter transcript…" : "Intet transcript endnu.")
                .foregroundStyle(.secondary)
            if episode.transcriptStatus != .refreshing {
                Button("Hent transcript") { Task { await model.fetchTranscript(for: episode) } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Timecoded segment list; a selected segment enables "open at this point" (PRD-FEAT-013.2).
    private var timecodeList: some View {
        List(segments, selection: $selectedSegmentID) { segment in
            HStack(alignment: .top, spacing: 10) {
                if let start = segment.startMs {
                    Button(TimeFormatting.clock(ms: start)) {
                        ExternalActions.openInPodcasts(episode: episode, atMs: start)
                    }
                    .buttonStyle(.link)
                    .font(.caption.monospacedDigit())
                    .frame(width: 64, alignment: .leading)
                }
                Text(segment.text).textSelection(.enabled)
            }
            .tag(segment.id)
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
