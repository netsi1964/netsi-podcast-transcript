import SwiftUI

/// The episode library: searchable, sortable list of stored episodes (PRD-FEAT-001).
struct LibrarySidebar: View {
    @EnvironmentObject var model: AppModel
    @Binding var selectedEpisodeID: String?
    @Binding var showingImport: Bool
    @Binding var showingSearch: Bool
    @State private var sort: SortOption = .recentlyUpdated

    enum SortOption: String, CaseIterable, Identifiable {
        case recentlyUpdated = "Senest opdateret"
        case title = "Titel"
        case podcast = "Podcast"
        case status = "Status"
        var id: String { rawValue }
    }

    private var sortedEpisodes: [Episode] {
        switch sort {
        case .recentlyUpdated: return model.episodes
        case .title: return model.episodes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .podcast: return model.episodes.sorted { ($0.podcastID) < ($1.podcastID) }
        case .status: return model.episodes.sorted { $0.transcriptStatus.rawValue < $1.transcriptStatus.rawValue }
        }
    }

    var body: some View {
        List(selection: $selectedEpisodeID) {
            ForEach(sortedEpisodes) { episode in
                EpisodeRow(episode: episode)
                    .tag(episode.id)
                    .contextMenu {
                        Button("Indlæs transcript igen") {
                            Task { await model.fetchTranscript(for: episode) }
                        }
                        Button("Slet episode", role: .destructive) {
                            try? model.store.deleteEpisode(id: episode.id)
                            if selectedEpisodeID == episode.id { selectedEpisodeID = nil }
                            model.refreshEpisodes()
                        }
                    }
            }
        }
        .searchable(text: $model.searchText, prompt: "Søg i titel, podcast, transcript, output")
        .onChange(of: model.searchText) { _, _ in model.refreshEpisodes() }
        .safeAreaInset(edge: .top) {
            HStack {
                Picker("Sortér", selection: $sort) {
                    ForEach(SortOption.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button {
                    showingSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Søg i Apple Podcasts")
                Button {
                    showingImport = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Importér episode via link")
            }
            .padding(8)
            .background(.bar)
        }
        .navigationTitle("Bibliotek")
    }
}

struct EpisodeRow: View {
    @EnvironmentObject var model: AppModel
    let episode: Episode

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "waveform").foregroundStyle(.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.title).lineLimit(1).font(.body.weight(.medium))
                if let podcast = model.podcast(for: episode) {
                    Text(podcast.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                StatusBadge(status: episode.transcriptStatus)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Textual status badge — never colour-only, per accessibility notes (PRD-SEC-006).
struct StatusBadge: View {
    let status: TranscriptStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch status {
        case .loaded: return .green
        case .failed: return .red
        case .notFound: return .orange
        case .refreshing: return .blue
        case .notLoaded: return .secondary
        }
    }
}
