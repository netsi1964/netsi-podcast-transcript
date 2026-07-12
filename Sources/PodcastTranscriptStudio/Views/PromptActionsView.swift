import SwiftUI

/// The dynamic prompt panel: one action per `.md` file in the prompt folder, plus a banner for
/// prompts needing repair (PRD-FEAT-006 / PRD-FEAT-007).
struct PromptActionsView: View {
    @EnvironmentObject var model: AppModel
    let episode: Episode
    @State private var runningPrompt: Prompt?
    @State private var fixingPrompt: Prompt?

    private var validPrompts: [Prompt] { model.prompts.prompts.filter { $0.validationStatus != .invalid } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !model.prompts.invalidPrompts.isEmpty {
                    invalidBanner
                }

                if validPrompts.isEmpty {
                    Text("Ingen prompts fundet. Læg `.md`-filer i prompt-folderen.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(validPrompts) { prompt in
                        PromptCard(prompt: prompt) { runningPrompt = prompt }
                    }
                }

                HStack {
                    Button {
                        NSWorkspace.shared.open(model.prompts.folderURL)
                    } label: { Label("Åbn prompt-folder", systemImage: "folder") }
                    Button {
                        model.prompts.reloadNow()
                    } label: { Label("Genindlæs", systemImage: "arrow.clockwise") }
                }
                .buttonStyle(.bordered).controlSize(.small)
                .padding(.top, 4)
            }
            .padding(16)
        }
        .sheet(item: $runningPrompt) { prompt in
            PromptRunSheet(prompt: prompt, episode: episode)
        }
        .sheet(item: $fixingPrompt) { prompt in
            PromptFixSheet(prompt: prompt)
        }
    }

    /// "En ny prompt er set, den er ikke som forventet…" (PRD-FEAT-007 acceptance wording).
    private var invalidBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("En ny prompt er set, den er ikke som forventet – vil du have hjælp til at få den fixet?",
                  systemImage: "wand.and.stars")
                .font(.callout.weight(.medium))
            ForEach(model.prompts.invalidPrompts) { prompt in
                HStack {
                    VStack(alignment: .leading) {
                        Text((prompt.filePath as NSString).lastPathComponent).font(.caption.monospaced())
                        if let msg = prompt.validationMessage {
                            Text(msg).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Fix") { fixingPrompt = prompt }
                }
            }
        }
        .padding(12)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct PromptCard: View {
    let prompt: Prompt
    let run: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(prompt.title).font(.headline)
                    if prompt.validationStatus == .warning {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                    }
                }
                if let desc = prompt.description {
                    Text(desc).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    if let provider = prompt.preferredProvider {
                        Text(provider).font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.blue.opacity(0.12), in: Capsule())
                    }
                    if let output = prompt.outputType {
                        Text(output).font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.purple.opacity(0.12), in: Capsule())
                    }
                }
            }
            Spacer()
            Button("Kør", action: run).buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
