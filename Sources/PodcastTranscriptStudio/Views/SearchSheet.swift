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
    @State private var importTask: Task<Void, Never>?
    @State private var detailResult: PodcastSearchResult?

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
                    SearchResultRow(
                        result: result,
                        isImporting: importingID == result.id,
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

    private func importResult(_ result: PodcastSearchResult) {
        importingID = result.id
        errorText = nil
        importTask = Task {
            let id = await model.importSearchResult(result)
            if Task.isCancelled { importingID = nil; return }
            importingID = nil
            if let id {
                // Clear any library filter so the freshly imported episode is actually visible.
                model.searchText = ""
                model.refreshEpisodes()
                selectedEpisodeID = id
                dismiss()
            } else if result.kind == .podcast {
                dismiss()
            } else {
                errorText = model.lastError ?? "Kunne ikke importere episoden."
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
