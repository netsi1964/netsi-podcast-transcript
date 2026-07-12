import SwiftUI

/// Runs a prompt against the episode. Shows the prompt's preferred LLM but lets the user
/// override provider/model before running (PRD-FEAT-009).
struct PromptRunSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let prompt: Prompt
    let episode: Episode
    /// When set, the prompt runs on this selected text only (PRD-FEAT-004 selection → prompt).
    var selectionText: String? = nil

    @State private var configID: String = ""
    @State private var modelName: String = ""
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var useCustomModel = false
    @State private var isRunning = false
    @State private var streamedText = ""
    @State private var runTask: Task<Void, Never>?
    @State private var result: AIOutput?
    @State private var errorText: String?

    private var selectedConfig: LLMProviderConfig? {
        model.providerConfigs.first { $0.id == configID }
    }

    /// Picker options: fetched models plus the currently-chosen one, so the selection is always
    /// representable even if the list is stale.
    private var modelOptions: [String] {
        var options = availableModels
        if !modelName.isEmpty && !options.contains(modelName) { options.insert(modelName, at: 0) }
        return options
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(prompt.title).font(.title2.bold())
            if let desc = prompt.description {
                Text(desc).foregroundStyle(.secondary)
            }

            if let preferred = prompt.preferredProvider {
                Label("Foretrukken LLM: \(preferred)\(prompt.preferredModel.map { " · \($0)" } ?? "")",
                      systemImage: "star")
                    .font(.callout).foregroundStyle(.secondary)
            }

            if let selectionText, !selectionText.isEmpty {
                Label("Kører på markeret tekst (\(selectionText.count) tegn)", systemImage: "text.viewfinder")
                    .font(.callout).foregroundStyle(.blue)
            }

            GroupBox {
                Grid(alignment: .leading, verticalSpacing: 8) {
                    GridRow {
                        Text("Provider")
                        Picker("", selection: $configID) {
                            ForEach(model.providerConfigs) { Text($0.displayName).tag($0.id) }
                        }
                        .labelsHidden()
                        .onChange(of: configID) { _, _ in loadModels() }
                    }
                    GridRow {
                        Text("Model")
                        modelField
                    }
                }
            }

            // Live output area: shows tokens as they stream in.
            if isRunning || !streamedText.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        MarkdownText(markdown: streamedText.isEmpty ? "…" : streamedText)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(maxHeight: 260)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: streamedText) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            if let errorText {
                SelectableError(message: errorText)
            }

            HStack {
                if !streamedText.isEmpty {
                    CopyMenu(markdown: { copyableOutput() })
                }
                Spacer()
                if isRunning {
                    // Stop generation — also bound to Esc.
                    Button(role: .cancel) { stop() } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else if result != nil {
                    Button("Færdig") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                    Button("Kør igen") { run() }
                } else {
                    Button("Annullér") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Kør prompt") { run() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedConfig == nil || modelName.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 540)
        .onAppear(perform: preselect)
        .onDisappear { runTask?.cancel() }
    }

    private func copyableOutput() -> String {
        if let result { return MarkdownSerializer.output(result, promptTitle: prompt.title) }
        return streamedText
    }

    /// Model chooser: a dropdown of the provider's actual models, with a refresh control and a
    /// fallback to typing a model id manually (useful when the provider can't be queried).
    @ViewBuilder
    private var modelField: some View {
        HStack(spacing: 6) {
            if useCustomModel || (modelOptions.isEmpty && !isLoadingModels) {
                TextField("model-id", text: $modelName).textFieldStyle(.roundedBorder)
                if !modelOptions.isEmpty {
                    Button("Vælg fra liste") { useCustomModel = false }
                        .buttonStyle(.link).font(.caption)
                }
            } else {
                Picker("", selection: $modelName) {
                    ForEach(modelOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                Button("Egen…") { useCustomModel = true }
                    .buttonStyle(.link).font(.caption)
            }
            if isLoadingModels {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    loadModels()
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Opdatér modelliste")
            }
        }
    }

    /// Preselects the prompt's preferred provider/model, else the first configured provider.
    private func preselect() {
        let config = model.resolveConfig(preferred: prompt.preferredProvider)
        configID = config?.id ?? model.providerConfigs.first?.id ?? ""
        modelName = prompt.preferredModel ?? selectedConfig?.defaultModel ?? config?.defaultModel ?? ""
        loadModels()
    }

    /// Queries the selected provider for its available models (PRD-FEAT-008 model selection).
    private func loadModels() {
        guard let config = selectedConfig else { return }
        // Reset custom mode when switching providers, and default the model to the config default.
        useCustomModel = false
        if modelName.isEmpty { modelName = config.defaultModel ?? "" }
        isLoadingModels = true
        let provider = LLMProviderFactory.make(from: config)
        Task {
            let models = await provider.listModels()
            availableModels = models
            if !models.isEmpty, !models.contains(modelName) {
                modelName = prompt.preferredModel.flatMap { models.contains($0) ? $0 : nil }
                    ?? config.defaultModel.flatMap { models.contains($0) ? $0 : nil }
                    ?? models.first ?? modelName
            }
            isLoadingModels = false
        }
    }

    /// Streams the prompt output token-by-token so the user sees progress immediately.
    private func run() {
        guard let config = selectedConfig else { return }
        guard let prepared = model.preparePromptRun(prompt, on: episode, using: config, overrideText: selectionText) else {
            errorText = model.lastError; model.lastError = nil; return
        }
        errorText = nil
        result = nil
        streamedText = ""
        isRunning = true
        runTask = Task {
            do {
                for try await delta in prepared.provider.streamComplete(messages: prepared.messages, model: modelName) {
                    if Task.isCancelled { break }
                    streamedText += delta
                }
            } catch {
                errorText = error.localizedDescription
            }
            // Save whatever was produced (also on stop), so partial output isn't lost.
            if !streamedText.isEmpty {
                result = model.savePromptOutput(
                    text: streamedText, prompt: prompt, episode: episode,
                    config: config, model: modelName, transcriptID: prepared.transcriptID,
                    scope: selectionText == nil ? .episode : .selection
                )
            }
            isRunning = false
        }
    }

    /// Stops generation (Stop button / Esc). The saved output keeps whatever streamed so far.
    private func stop() {
        runTask?.cancel()
        isRunning = false
    }
}
