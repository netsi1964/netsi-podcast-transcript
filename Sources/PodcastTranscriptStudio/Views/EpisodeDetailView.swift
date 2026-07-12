import SwiftUI

/// Episode workspace: metadata + external actions header, then tabbed content for transcript,
/// AI outputs, prompt actions and chat (PRD-FEAT-004 / PRD-FEAT-013 / PRD-SEC-006).
struct EpisodeDetailView: View {
    @EnvironmentObject var model: AppModel
    let episode: Episode

    enum Tab: String, CaseIterable, Identifiable {
        case transcript = "Transcript"
        case output = "AI-output"
        case prompts = "Prompts"
        case chat = "Chat"
        var id: String { rawValue }
    }
    @State private var tab: Tab = .transcript

    private var podcast: Podcast? { model.podcast(for: episode) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            Group {
                switch tab {
                case .transcript: TranscriptView(episode: episode)
                case .output: OutputHistoryView(episode: episode)
                case .prompts: PromptActionsView(episode: episode)
                case .chat: ChatView(scope: .episode, episode: episode)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(episode.title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title).font(.title2.bold()).lineLimit(2)
                    if let podcast { Text(podcast.title).foregroundStyle(.secondary) }
                    HStack(spacing: 8) {
                        StatusBadge(status: episode.transcriptStatus)
                        if let published = episode.publishedAt {
                            Text(DateFormatting.medium(published)).font(.caption).foregroundStyle(.secondary)
                        }
                        if let duration = episode.durationSeconds {
                            Text(TimeFormatting.duration(seconds: duration)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                CopyMenu(markdown: { MarkdownSerializer.metadata(podcast: podcast, episode: episode) },
                         label: "Kopiér metadata")
            }

            if episode.transcriptStatus == .failed || episode.transcriptStatus == .notFound {
                retryBar
            }

            actionBar
        }
        .padding(16)
    }

    /// Retry affordance for failed/not-found transcripts (PRD-FEAT-003 acceptance).
    private var retryBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(episode.transcriptError ?? "Transcript kunne ikke hentes.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Indlæs igen") { Task { await model.fetchTranscript(for: episode) } }
        }
        .padding(10)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    /// External actions: open in Podcasts, subscribe, Google search (PRD-FEAT-013).
    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                ExternalActions.openInPodcasts(episode: episode)
            } label: { Label("Åbn i Podcasts", systemImage: "play.circle") }

            if let podcast {
                Button {
                    ExternalActions.subscribe(podcast: podcast)
                } label: { Label("Subscribe", systemImage: "plus.circle") }
            }

            Button {
                ExternalActions.googleSearch(podcast: podcast, episode: episode)
            } label: { Label("Google-søgning", systemImage: "magnifyingglass") }

            Button {
                Task { await model.fetchTranscript(for: episode) }
            } label: { Label("Indlæs igen", systemImage: "arrow.clockwise") }

            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
