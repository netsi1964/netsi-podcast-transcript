import SwiftUI

/// Top-level three-part layout: library sidebar → selected episode detail. The episode library
/// is the app's landing surface (PRD-FEAT-001 / PRD-SEC-006).
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedEpisodeID: String?
    @State private var showingImport = false
    @State private var showingSearch = false
    @State private var showingArchiveChat = false

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(selectedEpisodeID: $selectedEpisodeID,
                           showingImport: $showingImport, showingSearch: $showingSearch)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            if let id = selectedEpisodeID, let episode = model.episodes.first(where: { $0.id == id }) {
                EpisodeDetailView(episode: episode)
                    .id(episode.id)
            } else {
                WelcomeView(showingImport: $showingImport)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showingArchiveChat = true
                } label: {
                    Label(L("Chat med arkivet"), systemImage: "bubble.left.and.bubble.right")
                }
            }
        }
        .sheet(isPresented: $showingImport) {
            ImportSheet(selectedEpisodeID: $selectedEpisodeID)
        }
        .sheet(isPresented: $showingSearch) {
            SearchSheet(selectedEpisodeID: $selectedEpisodeID)
        }
        .sheet(isPresented: $showingArchiveChat) {
            ChatView(scope: .archive, episode: nil)
                .frame(minWidth: 640, minHeight: 520)
        }
        .alert(L("Der opstod en fejl"), isPresented: .init(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button(L("OK"), role: .cancel) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

struct WelcomeView: View {
    @Binding var showingImport: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Podcast Transcript Studio")
                .font(.title.bold())
            Text(L("Indsæt et Apple Podcasts episode-link for at hente og arbejde med transcriptet."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button {
                showingImport = true
            } label: {
                Label(L("Importér episode"), systemImage: "plus")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
