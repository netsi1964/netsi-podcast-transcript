import SwiftUI

/// Chat over either the current episode or the whole archive (PRD-FEAT-011). The active scope
/// and the chosen provider/model are always shown; every message can be copied and searched.
struct ChatView: View {
    @EnvironmentObject var model: AppModel
    let scope: InputScope
    let episode: Episode?

    @StateObject private var controller = ChatController()
    @State private var draft = ""
    @State private var find = FindState()

    /// Distribution of the global active match across the message bubbles.
    private var dist: (total: Int, activeCard: Int, activeLocal: Int) {
        guard find.isPresented, !find.query.isEmpty else { return (0, -1, -1) }
        return TextSearch.distribute(query: find.query, texts: controller.messages.map(\.contentMarkdown), active: find.current)
    }

    var body: some View {
        VStack(spacing: 0) {
            scopeBar
            Divider()
            providerBar
            Divider()
            if find.isPresented {
                FindBar(state: $find)
                    .onChange(of: find.query) { _, _ in find.reset() }
            }
            messagesList
            Divider()
            inputBar
        }
        .task { controller.configure(model: model, scope: scope, episode: episode) }
        .onChange(of: dist.total) { _, total in if find.matchCount != total { find.matchCount = total } }
        .background {
            Button("") { toggleFind() }.keyboardShortcut("f", modifiers: .command).hidden()
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(controller.messages.enumerated()), id: \.element.id) { index, message in
                        ChatBubble(
                            message: message,
                            highlight: find.isPresented ? find.query : "",
                            activeMatch: index == dist.activeCard ? dist.activeLocal : -1
                        )
                        .id(message.id)
                    }
                    if controller.isThinking {
                        HStack { ProgressView().controlSize(.small); Text("Tænker…").foregroundStyle(.secondary) }
                    }
                }
                .padding(16)
            }
            .onChange(of: controller.messages.count) { _, _ in
                if let last = controller.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onChange(of: find.current) { _, _ in
                if dist.activeCard >= 0 { withAnimation { proxy.scrollTo(controller.messages[dist.activeCard].id, anchor: .center) } }
            }
        }
    }

    private var scopeBar: some View {
        HStack {
            Label(scope == .episode ? "Scope: Aktuel episode" : "Scope: Hele arkivet",
                  systemImage: scope == .episode ? "doc.text" : "books.vertical")
                .font(.callout.weight(.medium))
            if let episode, scope == .episode {
                Text("· \(episode.title)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { toggleFind() } label: { Image(systemName: "magnifyingglass") }
                .help("Find i chatten (⌘F)")
            if !controller.messages.isEmpty {
                CopyIconMenu(markdown: { controller.transcriptMarkdown() })
            }
        }
        .padding(12)
        .background(.bar)
    }

    /// Provider + model selection for the conversation.
    private var providerBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $controller.configID) {
                ForEach(controller.providerConfigs) { Text($0.displayName).tag($0.id) }
            }
            .labelsHidden()
            .fixedSize()
            .onChange(of: controller.configID) { _, _ in controller.loadModels() }

            ModelPicker(
                model: $controller.modelName,
                options: controller.availableModels,
                isLoading: controller.isLoadingModels,
                reload: { controller.loadModels() }
            )
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Skriv en besked…", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .onSubmit(send)
                .disabled(controller.isThinking)
            if controller.isThinking {
                Button(role: .cancel) { controller.stop() } label: { Image(systemName: "stop.fill") }
                    .keyboardShortcut(.cancelAction).tint(.red).help("Stop (Esc)")
            } else {
                Button { send() } label: { Image(systemName: "paperplane.fill") }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
    }

    private func toggleFind() {
        find.isPresented.toggle()
        if !find.isPresented { find.query = "" }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task { await controller.send(text) }
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    var highlight: String = ""
    var activeMatch: Int = 0
    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                MarkdownText(markdown: message.contentMarkdown, highlight: highlight, activeMatch: activeMatch)
                HStack(spacing: 6) {
                    if let model = message.model {
                        Text(model).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    CopyIconMenu(markdown: { message.contentMarkdown })
                }
            }
            .padding(10)
            .background(isUser ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10))
            if !isUser { Spacer(minLength: 40) }
        }
    }
}
