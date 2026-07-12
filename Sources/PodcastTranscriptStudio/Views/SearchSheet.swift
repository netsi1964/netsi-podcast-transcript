import SwiftUI

/// Search Apple's podcast catalogue and import results directly (PRD-SEC-010).
struct SearchSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedEpisodeID: String?

    @State private var term = ""
    @State private var kind: PodcastSearchResult.Kind = .episode
    @State private var results: [PodcastSearchResult] = []
    @State private var isSearching = false
    @State private var importingID: String?
    @State private var errorText: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Søg i Apple Podcasts").font(.title2.bold())
                Spacer()
                Button("Luk") { dismiss() }.keyboardShortcut(.cancelAction)
            }

            Picker("", selection: $kind) {
                Text("Episoder").tag(PodcastSearchResult.Kind.episode)
                Text("Podcasts").tag(PodcastSearchResult.Kind.podcast)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: kind) { _, _ in runSearch() }

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Søg efter titel, emne eller person…", text: $term)
                    .textFieldStyle(.plain)
                    .onSubmit(runSearch)
                if isSearching { ProgressView().controlSize(.small) }
            }
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            if let errorText {
                SelectableError(message: errorText)
            }

            if results.isEmpty && !isSearching {
                ContentUnavailableView(
                    term.isEmpty ? "Søg i Apples katalog" : "Ingen resultater",
                    systemImage: "waveform.magnifyingglass",
                    description: Text(term.isEmpty ? "Skriv en søgning og tryk Enter." : "Prøv en anden søgning.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(results) { result in
                    SearchResultRow(result: result, isImporting: importingID == result.id) {
                        importResult(result)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(width: 620, height: 560)
    }

    private func runSearch() {
        searchTask?.cancel()
        let query = term
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; return }
        errorText = nil
        isSearching = true
        searchTask = Task {
            do {
                let found = try await PodcastSearchService.search(term: query, kind: kind)
                if !Task.isCancelled { results = found }
            } catch {
                if !Task.isCancelled { errorText = error.localizedDescription }
            }
            if !Task.isCancelled { isSearching = false }
        }
    }

    private func importResult(_ result: PodcastSearchResult) {
        importingID = result.id
        Task {
            let id = await model.importSearchResult(result)
            importingID = nil
            if let id {
                selectedEpisodeID = id
                dismiss()
            } else if result.kind == .podcast {
                dismiss()   // podcast shell added
            } else {
                errorText = model.lastError ?? "Kunne ikke importere episoden."
                model.lastError = nil
            }
        }
    }
}

struct SearchResultRow: View {
    let result: PodcastSearchResult
    let isImporting: Bool
    let onImport: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: result.artworkURL.flatMap(URL.init)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                    .overlay(Image(systemName: "waveform").foregroundStyle(.secondary))
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(result.episodeTitle ?? result.podcastTitle)
                    .font(.body.weight(.medium)).lineLimit(2)
                if result.episodeTitle != nil {
                    Text(result.podcastTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let date = result.releaseDate {
                        Text(DateFormatting.medium(date)).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let dur = result.durationSeconds {
                        Text(TimeFormatting.duration(seconds: dur)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if isImporting {
                ProgressView().controlSize(.small)
            } else {
                Button("Importér", action: onImport).buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
