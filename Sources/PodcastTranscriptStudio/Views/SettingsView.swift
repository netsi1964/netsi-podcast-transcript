import SwiftUI

/// App settings: LLM providers, prompt folder, and data export/import (PRD-SEC-006 settings flow).
struct SettingsView: View {
    var body: some View {
        TabView {
            ProvidersSettings()
                .tabItem { Label("LLM-providere", systemImage: "cpu") }
            PromptFolderSettings()
                .tabItem { Label("Prompts", systemImage: "text.badge.star") }
            DataSettings()
                .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 560, height: 460)
    }
}

/// Provider configuration with Keychain-backed API keys and an availability probe (PRD-FEAT-008).
struct ProvidersSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(model.providerConfigs) { config in
                    ProviderCard(config: config)
                }
            }
            .padding(16)
        }
        .onAppear { model.reloadProviders() }
    }
}

struct ProviderCard: View {
    @EnvironmentObject var model: AppModel
    let config: LLMProviderConfig

    @State private var baseURL = ""
    @State private var defaultModel = ""
    @State private var apiKey = ""
    @State private var isEnabled = true
    @State private var availability: String?

    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var useCustomModel = false
    @State private var didSave = false

    private var needsKey: Bool { config.providerType == .openAICompatible }
    private var needsURL: Bool { config.providerType != .appleFoundationModels }

    private var modelOptions: [String] {
        var options = availableModels
        if !defaultModel.isEmpty && !options.contains(defaultModel) { options.insert(defaultModel, at: 0) }
        return options
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(config.displayName).font(.headline)
                    Text(config.providerType.displayName).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Aktiv", isOn: $isEnabled).labelsHidden()
                }

                if needsURL {
                    LabeledContent("Base-URL") {
                        TextField("base URL", text: $baseURL).textFieldStyle(.roundedBorder)
                    }
                }
                LabeledContent("Standardmodel") { modelField }
                if needsKey {
                    LabeledContent("API key (Keychain)") {
                        SecureField("gemmes i Keychain", text: $apiKey).textFieldStyle(.roundedBorder)
                    }
                }

                HStack(spacing: 10) {
                    Button("Gem") { save() }.buttonStyle(.borderedProminent)
                    Button("Test tilgængelighed") { test() }
                    if didSave {
                        Label("Gemt", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.caption)
                            .transition(.opacity)
                    }
                    if let availability {
                        Text(availability).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .onAppear {
            load()
            loadModels()
        }
    }

    /// Dropdown of the provider's actual models, with refresh + a manual-entry fallback for when
    /// the provider can't be queried (e.g. no API key yet).
    @ViewBuilder
    private var modelField: some View {
        HStack(spacing: 6) {
            if useCustomModel || (modelOptions.isEmpty && !isLoadingModels) {
                TextField("model-id", text: $defaultModel).textFieldStyle(.roundedBorder)
                if !modelOptions.isEmpty {
                    Button("Vælg fra liste") { useCustomModel = false }.buttonStyle(.link).font(.caption)
                }
            } else {
                Picker("", selection: $defaultModel) {
                    ForEach(modelOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                Button("Egen…") { useCustomModel = true }.buttonStyle(.link).font(.caption)
            }
            if isLoadingModels {
                ProgressView().controlSize(.small)
            } else {
                Button { loadModels() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Hent modeller fra provideren")
            }
        }
    }

    private func load() {
        baseURL = config.baseURL ?? ""
        defaultModel = config.defaultModel ?? ""
        isEnabled = config.isEnabled
        if let ref = config.apiKeyKeychainRef, let existing = Keychain.get(ref: ref) {
            apiKey = existing
        }
    }

    /// Queries the provider for its models using the *currently edited* URL/key, so the list
    /// reflects unsaved changes.
    private func loadModels() {
        var probe = config
        probe.baseURL = baseURL.isEmpty ? nil : baseURL
        if needsKey {
            let ref = config.apiKeyKeychainRef ?? "key-\(config.id)"
            if !apiKey.isEmpty { Keychain.set(apiKey, ref: ref) }
            probe.apiKeyKeychainRef = ref
        }
        isLoadingModels = true
        let provider = LLMProviderFactory.make(from: probe)
        Task {
            availableModels = await provider.listModels()
            if defaultModel.isEmpty { defaultModel = availableModels.first ?? "" }
            isLoadingModels = false
        }
    }

    private func save() {
        var updated = config
        updated.baseURL = baseURL.isEmpty ? nil : baseURL
        updated.defaultModel = defaultModel.isEmpty ? nil : defaultModel
        updated.isEnabled = isEnabled
        updated.updatedAt = .now
        if needsKey {
            let ref = config.apiKeyKeychainRef ?? "key-\(config.id)"
            updated.apiKeyKeychainRef = ref
            if apiKey.isEmpty { Keychain.delete(ref: ref) } else { Keychain.set(apiKey, ref: ref) }
        }
        try? model.store.saveProviderConfig(updated)
        model.reloadProviders()

        // Visible confirmation, auto-dismissed after a moment (addresses "no save feedback").
        withAnimation { didSave = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { didSave = false }
        }
    }

    private func test() {
        availability = "Tester…"
        let provider = LLMProviderFactory.make(from: config)
        Task {
            let ok = await provider.isAvailable()
            availability = ok ? "✅ Tilgængelig" : "⚠️ Ikke tilgængelig"
        }
    }
}

struct PromptFolderSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Prompt-folder").font(.headline)
            Text(model.prompts.folderURL.path)
                .font(.caption.monospaced()).foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Button {
                    NSWorkspace.shared.open(model.prompts.folderURL)
                } label: { Label("Åbn folder", systemImage: "folder") }
                Button {
                    model.prompts.reloadNow()
                } label: { Label("Genindlæs prompts", systemImage: "arrow.clockwise") }
            }
            Divider()
            Text("\(model.prompts.prompts.count) prompts indlæst · \(model.prompts.invalidPrompts.count) med problemer")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DataSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Eksport & import").font(.headline)
            Text("API keys eksporteres ikke — de bliver i Keychain.")
                .font(.callout).foregroundStyle(.secondary)

            Button {
                ExportService.batchExportAllTranscripts(store: model.store)
            } label: { Label("Eksportér alle transcripts (Markdown)", systemImage: "square.and.arrow.up") }

            Button {
                ExportService.exportBackup(store: model.store, promptsFolder: model.prompts.folderURL)
            } label: { Label("Lav backup-pakke (database + prompts)", systemImage: "archivebox") }

            Button {
                ExportService.importBackup(into: model.prompts.folderURL)
                model.prompts.reloadNow()
            } label: { Label("Importér backup", systemImage: "square.and.arrow.down") }

            Spacer()
            Text("Database: \(model.store.databaseURL.path)")
                .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
