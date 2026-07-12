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
                                        promptTitle: promptTitle(for: output),
                                        highlight: find.isPresented ? find.query : "",
                                        activeMatch: index == dist.activeCard ? dist.activeLocal : -1,
                                        onDelete: { delete(output) }
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

    /// The prompt's title (its "type") if the prompt still exists, else a generic label.
    private func promptTitle(for output: AIOutput) -> String {
        if let id = output.promptID, let prompt = model.prompts.prompts.first(where: { $0.id == id }) {
            return prompt.title
        }
        return L("AI-svar")
    }

    private func delete(_ output: AIOutput) {
        try? model.store.deleteOutput(id: output.id)
        reload()
    }

    private func reload() {
        outputs = (try? model.store.outputs(episodeID: episode.id)) ?? []
    }
}

struct OutputCard: View {
    let output: AIOutput
    var promptTitle: String?
    var highlight: String = ""
    var activeMatch: Int = 0
    var onDelete: () -> Void = {}
    @State private var expanded = false
    @State private var confirmingDelete = false

    /// Collapsed by default; always expanded while searching so highlights/navigation work.
    private var showContent: Bool { expanded || !highlight.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showContent ? "chevron.down" : "chevron.right")
                        .font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(promptTitle ?? L("AI-svar")).font(.headline)
                        HStack(spacing: 6) {
                            Label(output.providerType.displayName, systemImage: "cpu")
                            Text("· \(output.model)").monospaced()
                            Text("· \(DateFormatting.medium(output.createdAt))")
                        }
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    CopyIconMenu(markdown: { MarkdownSerializer.output(output, promptTitle: promptTitle) })
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help(L("Slet dette AI-svar"))
                    .confirmationDialog(L("Slet dette AI-svar?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
                        Button(L("Slet"), role: .destructive, action: onDelete)
                        Button(L("Annullér"), role: .cancel) {}
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showContent {
                Divider()
                MarkdownText(markdown: output.outputMarkdown, highlight: highlight, activeMatch: activeMatch)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
