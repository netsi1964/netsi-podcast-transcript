import SwiftUI

/// Shows the automatically-saved history of prompt runs for an episode (PRD-FEAT-010).
struct OutputHistoryView: View {
    @EnvironmentObject var model: AppModel
    let episode: Episode
    @State private var outputs: [AIOutput] = []
    @State private var find = FindState()

    private var dist: (total: Int, activeCard: Int, activeLocal: Int) {
        guard find.isPresented, !find.query.isEmpty else { return (0, -1, -1) }
        return TextSearch.distribute(query: find.query, texts: outputs.map(\.outputMarkdown), active: find.current)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !outputs.isEmpty {
                HStack {
                    Spacer()
                    Button { toggleFind() } label: { Image(systemName: "magnifyingglass") }
                        .help("Find i output (⌘F)")
                }
                .padding(.horizontal, 12).padding(.top, 8)
                if find.isPresented {
                    FindBar(state: $find).onChange(of: find.query) { _, _ in find.reset() }
                }
            }

            Group {
                if outputs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Ingen AI-output endnu.").foregroundStyle(.secondary)
                        Text("Kør en prompt fra fanen Prompts.").font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(Array(outputs.enumerated()), id: \.element.id) { index, output in
                                    OutputCard(
                                        output: output,
                                        highlight: find.isPresented ? find.query : "",
                                        activeMatch: index == dist.activeCard ? dist.activeLocal : -1
                                    )
                                    .id(output.id)
                                }
                            }
                            .padding(16)
                        }
                        .onChange(of: find.current) { _, _ in
                            if dist.activeCard >= 0 { withAnimation { proxy.scrollTo(outputs[dist.activeCard].id, anchor: .center) } }
                        }
                    }
                }
            }
        }
        .task(id: episode.id) { reload() }
        .onReceive(model.$episodes) { _ in reload() }
        .onChange(of: dist.total) { _, total in if find.matchCount != total { find.matchCount = total } }
    }

    private func toggleFind() {
        find.isPresented.toggle()
        if !find.isPresented { find.query = "" }
    }

    private func reload() {
        outputs = (try? model.store.outputs(episodeID: episode.id)) ?? []
    }
}

struct OutputCard: View {
    let output: AIOutput
    var highlight: String = ""
    var activeMatch: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(output.providerType.displayName, systemImage: "cpu")
                    .font(.caption).foregroundStyle(.secondary)
                Text("· \(output.model)").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Text(DateFormatting.medium(output.createdAt)).font(.caption).foregroundStyle(.secondary)
                CopyIconMenu(markdown: { MarkdownSerializer.output(output, promptTitle: nil) })
            }
            Divider()
            MarkdownText(markdown: output.outputMarkdown, highlight: highlight, activeMatch: activeMatch)
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
