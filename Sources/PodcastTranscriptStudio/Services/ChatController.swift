import Foundation
import Combine

/// Drives one chat session: builds scope-appropriate context, calls the LLM, and persists both
/// sides automatically (PRD-FEAT-011). Chat answers are saved as they arrive (PRD-FEAT-011 acceptance).
@MainActor
final class ChatController: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isThinking = false

    // User-selectable provider + model for the conversation (PRD-FEAT-009 override in chat).
    @Published var configID: String = ""
    @Published var modelName: String = ""
    @Published var availableModels: [String] = []
    @Published var isLoadingModels = false

    private var model: AppModel?
    private var session: ChatSession?
    private var scope: InputScope = .episode
    private var episode: Episode?
    private var streamTask: Task<Void, Never>?

    var providerConfigs: [LLMProviderConfig] { model?.providerConfigs ?? [] }
    private var selectedConfig: LLMProviderConfig? { providerConfigs.first { $0.id == configID } }

    func configure(model: AppModel, scope: InputScope, episode: Episode?) {
        guard session == nil else { return }
        self.model = model
        self.scope = scope
        self.episode = episode
        let config = model.providerConfigs.first(where: \.isEnabled)
        configID = config?.id ?? model.providerConfigs.first?.id ?? ""
        modelName = config?.defaultModel ?? ""
        let session = ChatSession(
            scope: scope, episodeID: episode?.id,
            title: scope == .episode ? episode?.title : "Arkiv-chat",
            providerType: config?.providerType ?? .appleFoundationModels,
            model: config?.defaultModel ?? "system"
        )
        self.session = session
        try? model.store.saveChatSession(session)
        loadModels()
    }

    /// Loads the selected provider's models for the chat model picker.
    func loadModels() {
        guard let config = selectedConfig else { return }
        if modelName.isEmpty { modelName = config.defaultModel ?? "" }
        isLoadingModels = true
        let provider = LLMProviderFactory.make(from: config)
        Task {
            let models = await provider.listModels()
            availableModels = models
            if !models.isEmpty, !models.contains(modelName) {
                modelName = config.defaultModel.flatMap { models.contains($0) ? $0 : nil } ?? models.first ?? modelName
            }
            isLoadingModels = false
        }
    }

    func send(_ text: String) async {
        guard let model, let session else { return }
        let userMessage = ChatMessage(chatSessionID: session.id, role: .user, contentMarkdown: text)
        messages.append(userMessage)
        try? model.store.saveChatMessage(userMessage)

        guard let config = selectedConfig ?? model.providerConfigs.first(where: \.isEnabled) else {
            appendError("Ingen LLM-provider er konfigureret. Åbn Indstillinger.")
            return
        }

        isThinking = true
        let llmMessages = buildMessages(userText: text)
        let provider = LLMProviderFactory.make(from: config)
        let modelName = self.modelName.isEmpty ? (config.defaultModel ?? "system") : self.modelName

        // Append an empty assistant message and stream tokens into it live.
        var assistant = ChatMessage(
            chatSessionID: session.id, role: .assistant, contentMarkdown: "",
            providerType: config.providerType, model: modelName
        )
        messages.append(assistant)
        let index = messages.count - 1

        streamTask = Task {
            do {
                for try await delta in provider.streamComplete(messages: llmMessages, model: modelName) {
                    if Task.isCancelled { break }
                    assistant.contentMarkdown += delta
                    messages[index] = assistant
                }
            } catch {
                assistant.contentMarkdown += (assistant.contentMarkdown.isEmpty ? "" : "\n\n") + "⚠️ \(error.localizedDescription)"
                messages[index] = assistant
            }
            if assistant.contentMarkdown.isEmpty {
                assistant.contentMarkdown = "⏹ Stoppet."
                messages[index] = assistant
            }
            try? model.store.saveChatMessage(assistant)
            isThinking = false
        }
        await streamTask?.value
    }

    /// Stops the in-flight response (Stop button / Esc). Whatever streamed so far is kept.
    func stop() {
        streamTask?.cancel()
    }

    func transcriptMarkdown() -> String {
        guard let session else { return "" }
        return MarkdownSerializer.chatSession(session, messages: messages)
    }

    /// Assembles system context (transcript for episode scope, FTS snippets for archive scope)
    /// plus the running conversation (PRD-FEAT-011.2 / PRD-FEAT-011.3).
    private func buildMessages(userText: String) -> [LLMMessage] {
        guard let model else { return [] }
        var result: [LLMMessage] = []
        var context = "Du er en hjælpsom assistent, der svarer på dansk ud fra podcast-transskriptioner.\n\n"

        switch scope {
        case .episode, .selection:
            if let episode, let transcript = try? model.store.transcript(episodeID: episode.id) {
                context += "Kontekst — transcript for \"\(episode.title)\":\n"
                context += String(transcript.plainText.prefix(12000))
            } else {
                context += "Der er intet transcript for den aktuelle episode endnu."
            }
        case .archive:
            let snippets = (try? model.store.searchContext(query: userText)) ?? []
            if snippets.isEmpty {
                context += "Ingen relevante arkiv-uddrag fundet for spørgsmålet."
            } else {
                context += "Relevante uddrag fra arkivet:\n"
                context += snippets.map { "- [\($0.title)] \($0.body)" }.joined(separator: "\n")
            }
        }

        result.append(LLMMessage(role: .system, content: context))
        // Prior turns (cap history to keep prompts bounded).
        for message in messages.suffix(12) {
            result.append(LLMMessage(
                role: message.role == .user ? .user : .assistant,
                content: message.contentMarkdown
            ))
        }
        return result
    }

    private func appendError(_ text: String) {
        guard let session else { return }
        let message = ChatMessage(chatSessionID: session.id, role: .assistant,
                                  contentMarkdown: "⚠️ \(text)")
        messages.append(message)
    }
}
