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
    @State private var importedIDs: Set<String> = []
    @State private var errorText: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var importTask: Task<Void, Never>?
    @State private var detailResult: PodcastSearchResult?
    @State private var sortField: SortField = .relevance
    @State private var sortAscending = true

    enum SortField: String, CaseIterable, Identifiable {
        case relevance = "Relevans"
        case title = "Titel"
        case podcast = "Podcast"
        case date = "Dato"
        var id: String { rawValue }
    }

    /// Results sorted by the chosen field + direction (Relevans keeps Apple's own order).
    private var sortedResults: [PodcastSearchResult] {
        let base: [PodcastSearchResult]
        switch sortField {
        case .relevance:
            base = results
        case .title:
            base = results.sorted {
                ($0.episodeTitle ?? $0.podcastTitle).localizedCaseInsensitiveCompare($1.episodeTitle ?? $1.podcastTitle) == .orderedAscending
            }
        case .podcast:
            base = results.sorted { $0.podcastTitle.localizedCaseInsensitiveCompare($1.podcastTitle) == .orderedAscending }
        case .date:
            base = results.sorted { ($0.releaseDate ?? .distantPast) < ($1.releaseDate ?? .distantPast) }
        }
        return sortAscending ? base : base.reversed()
    }

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
                HStack(spacing: 6) {
                    Text("Sortér:").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $sortField) {
                        ForEach(SortField.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    Button { sortAscending.toggle() } label: {
                        Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                    }
                    .help(sortAscending ? "Stigende" : "Faldende")
                    .disabled(sortField == .relevance)
                    Spacer()
                    Text("\(results.count) resultater").font(.caption).foregroundStyle(.secondary)
                }
                List(sortedResults) { result in
                    SearchResultRow(
                        result: result,
                        isImporting: importingID == result.id,
                        isImported: importedIDs.contains(result.id),
                        onImport: { importResult(result) },
                        onSelect: { detailResult = result }
                    )
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(width: 620, height: 560)
        .overlay { if importingID != nil { importingOverlay } }
        .sheet(item: $detailResult) { result in
            SearchResultDetail(
                result: result,
                isImporting: importingID == result.id,
                onImport: { detailResult = nil; importResult(result) }
            )
        }
    }

    /// Blocking loading state with Annuller (also bound to Esc) so an import can't feel stuck.
    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                Text("Importerer…").font(.headline)
                Button("Annullér", role: .cancel) { cancelImport() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
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

    /// Imports a result but keeps the search open (import several) and keeps the query so the user
    /// can keep browsing. Imported rows are marked with a checkmark.
    private func importResult(_ result: PodcastSearchResult) {
        importingID = result.id
        errorText = nil
        importTask = Task {
            let id = await model.importSearchResult(result)
            if Task.isCancelled { importingID = nil; return }
            importingID = nil
            if let id {
                // Clear any library filter so the imported episode is visible once the sheet closes.
                model.searchText = ""
                model.refreshEpisodes()
                selectedEpisodeID = id
                importedIDs.insert(result.id)
            } else {
                // Shows now import their episodes too, so a nil result is a genuine failure for
                // both kinds — never mark it as imported.
                errorText = model.lastError
                    ?? (result.kind == .podcast ? "Kunne ikke importere podcasten." : "Kunne ikke importere episoden.")
                model.lastError = nil
            }
        }
    }

    private func cancelImport() {
        importTask?.cancel()
        importingID = nil
    }
}

struct SearchResultRow: View {
    let result: PodcastSearchResult
    let isImporting: Bool
    var isImported: Bool = false
    let onImport: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            artwork
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
            // Tapping the info area opens details (PRD-FEAT-001 details before import).
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)

            Spacer()
            Button { onSelect() } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless).help("Vis detaljer")
            if isImporting {
                ProgressView().controlSize(.small)
            } else if isImported {
                Label("Importeret", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.caption)
                Button("Igen", action: onImport).buttonStyle(.bordered).controlSize(.small)
                    .help("Importér igen / opdatér")
            } else {
                Button("Importér", action: onImport).buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var artwork: some View {
        AsyncImage(url: result.artworkURL.flatMap(URL.init)) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                .overlay(Image(systemName: "waveform").foregroundStyle(.secondary))
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

/// Detail preview of a search result before importing.
struct SearchResultDetail: View {
    @Environment(\.dismiss) private var dismiss
    let result: PodcastSearchResult
    let isImporting: Bool
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                AsyncImage(url: result.artworkURL.flatMap(URL.init)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                        .overlay(Image(systemName: "waveform").foregroundStyle(.secondary))
                }
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.episodeTitle ?? result.podcastTitle).font(.title3.bold()).lineLimit(3)
                    if result.episodeTitle != nil {
                        Text(result.podcastTitle).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        if let date = result.releaseDate {
                            Label(DateFormatting.medium(date), systemImage: "calendar").font(.caption)
                        }
                        if let dur = result.durationSeconds {
                            Label(TimeFormatting.duration(seconds: dur), systemImage: "clock").font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let description = result.descriptionText, !description.isEmpty {
                Divider()
                ScrollView {
                    Text(description)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }

            Spacer()
            HStack {
                if let appleURL = result.appleURL, let url = URL(string: appleURL) {
                    Link(destination: url) { Label("Åbn i Podcasts", systemImage: "play.circle") }
                }
                Spacer()
                Button("Luk") { dismiss() }.keyboardShortcut(.cancelAction)
                if isImporting {
                    ProgressView().controlSize(.small)
                } else if result.kind == .episode {
                    Button("Importér", action: onImport)
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                } else {
                    Button("Tilføj podcast", action: onImport).buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 540, height: 460)
    }
}
