import SwiftUI

extension Color {
    /// Highlight colour for in-text search, from netsi.dk. Adjust this one constant to match the
    /// site exactly if needed.
    static let netsiOrange = Color(red: 0.96, green: 0.51, blue: 0.12) // #F5811F
}

extension NSColor {
    static let netsiOrange = NSColor(calibratedRed: 0.96, green: 0.51, blue: 0.12, alpha: 1)
}

/// State for a find-in-text session on one content surface.
struct FindState: Equatable {
    var isPresented = false
    var query = ""
    var matchCount = 0
    var current = 0   // 0-based index of the active match
    /// Literal text find (false) vs. embeddings-based semantic search (true).
    var semantic = false

    mutating func next() { if matchCount > 0 { current = (current + 1) % matchCount } }
    mutating func previous() { if matchCount > 0 { current = (current - 1 + matchCount) % matchCount } }
    mutating func reset() { current = 0 }
}

/// Case-insensitive match counting shared by the highlighters.
enum TextSearch {
    static func count(in text: String, query: String) -> Int {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 1 else { return 0 }
        var count = 0
        var start = text.startIndex
        while let r = text.range(of: q, options: .caseInsensitive, range: start..<text.endIndex) {
            count += 1
            start = r.upperBound
        }
        return count
    }

    /// Builds an `AttributedString` for a plain string with an orange background on every
    /// case-insensitive match (`activeLocal` gets the brighter active style; -1 for none).
    static func highlighted(_ text: String, query: String, activeLocal: Int) -> AttributedString {
        var attr = AttributedString(text)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return attr }
        var start = text.startIndex
        var index = 0
        while let r = text.range(of: q, options: .caseInsensitive, range: start..<text.endIndex) {
            let lowerOffset = text.distance(from: text.startIndex, to: r.lowerBound)
            let length = text.distance(from: r.lowerBound, to: r.upperBound)
            let lower = attr.index(attr.startIndex, offsetByCharacters: lowerOffset)
            let upper = attr.index(lower, offsetByCharacters: length)
            let isActive = index == activeLocal
            attr[lower..<upper].backgroundColor = isActive ? Color.netsiOrange : Color.netsiOrange.opacity(0.35)
            if isActive { attr[lower..<upper].foregroundColor = .black }
            index += 1
            start = r.upperBound
        }
        return attr
    }

    /// Maps a global active-match index onto a list of text blocks (e.g. output cards or chat
    /// bubbles): returns the total match count and which block holds the active match plus its
    /// local index within that block. `activeCard == -1` when there are no matches.
    static func distribute(query: String, texts: [String], active: Int) -> (total: Int, activeCard: Int, activeLocal: Int) {
        let counts = texts.map { count(in: $0, query: query) }
        let total = counts.reduce(0, +)
        guard total > 0 else { return (0, -1, -1) }
        var remaining = ((active % total) + total) % total
        for (index, c) in counts.enumerated() {
            if remaining < c { return (total, index, remaining) }
            remaining -= c
        }
        return (total, -1, -1)
    }
}

/// Compact find bar: query field, match counter, previous/next, and close. Bound to a `FindState`.
/// Opened with ⌘F, navigated with ⌘G / ⌘⇧G, closed with Esc (PRD-FEAT-001 search-everywhere).
struct FindBar: View {
    @Binding var state: FindState
    var placeholder: String = "Find i teksten"
    /// When true, offers a literal/semantic radio and (for semantic) an embedding-provider menu.
    var semanticEnabled: Bool = false
    var embeddingChoice: Binding<EmbeddingChoice>? = nil
    /// Embedding model selection (shown for non-Apple backends).
    var embeddingModel: Binding<String>? = nil
    var embeddingModels: [String] = []
    var isLoadingEmbeddingModels: Bool = false
    var reloadEmbeddingModels: (() -> Void)? = nil
    var isRunning: Bool = false
    /// Called when the user submits a semantic query (semantic search runs on Enter, not per key).
    var onRunSemantic: (() -> Void)? = nil
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.callout)
            TextField(state.semantic ? "Beskriv hvad du leder efter…" : placeholder, text: $state.query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { if state.semantic { onRunSemantic?() } else { state.next() } }

            if isRunning { ProgressView().controlSize(.small) }

            Text(state.query.isEmpty ? "" : "\(state.matchCount == 0 ? 0 : state.current + 1)/\(state.matchCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 40)

            Button { state.previous() } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless).disabled(state.matchCount == 0)
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .help("Forrige (⌘⇧G)")
            Button { state.next() } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless).disabled(state.matchCount == 0)
                .keyboardShortcut("g", modifiers: .command)
                .help("Næste (⌘G)")

            if semanticEnabled {
                Divider().frame(height: 16)
                Picker("", selection: $state.semantic) {
                    Text("Tekst").tag(false)
                    Text("Semantisk").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if state.semantic, let embeddingChoice {
                    Picker("", selection: embeddingChoice) {
                        ForEach(EmbeddingChoice.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .help("Embedding-backend til semantisk søgning")
                    // Model picker for non-Apple backends (e.g. choose an installed Ollama model).
                    if embeddingChoice.wrappedValue != .apple, let embeddingModel {
                        ModelPicker(model: embeddingModel, options: embeddingModels,
                                    isLoading: isLoadingEmbeddingModels,
                                    reload: { reloadEmbeddingModels?() })
                            .frame(maxWidth: 220)
                    }
                    Button { onRunSemantic?() } label: { Image(systemName: "sparkle.magnifyingglass") }
                        .buttonStyle(.borderless).help("Kør semantisk søgning (Enter)")
                }
            }

            Button { state.isPresented = false; state.query = "" } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Luk (Esc)")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .onAppear { focused = true }
    }
}
