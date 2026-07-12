import SwiftUI

/// Guided repair for a prompt with missing/invalid frontmatter. Suggests the missing metadata
/// and writes a corrected file back (PRD-FEAT-007).
struct PromptFixSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let prompt: Prompt

    @State private var title = ""
    @State private var version = "1"
    @State private var description = ""
    @State private var preferredProvider = ""
    @State private var preferredModel = ""
    @State private var outputType = "markdown"
    @State private var promptBody = ""
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ret prompt").font(.title2.bold())
            Text((prompt.filePath as NSString).lastPathComponent)
                .font(.caption.monospaced()).foregroundStyle(.secondary)
            if let msg = prompt.validationMessage {
                Label(msg, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }

            Form {
                TextField("Titel", text: $title)
                TextField("Version", text: $version)
                TextField("Beskrivelse", text: $description)
                TextField("Foretrukken provider (valgfri)", text: $preferredProvider)
                TextField("Foretrukken model (valgfri)", text: $preferredModel)
                TextField("Output-type", text: $outputType)
            }
            .textFieldStyle(.roundedBorder)

            Text("Prompt-tekst (instruktionen der køres):").font(.callout.weight(.medium))
            TextEditor(text: $promptBody)
                .font(.body.monospaced())
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            if let errorText {
                Label(errorText, systemImage: "xmark.octagon").foregroundStyle(.red).font(.callout)
            }

            HStack {
                Spacer()
                Button("Annullér") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Gem rettet prompt") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear(perform: prefill)
    }

    /// Suggest sensible defaults from what we could parse (PRD-FEAT-007 acceptance).
    private func prefill() {
        title = prompt.title
        version = prompt.version == "0" ? "1" : prompt.version
        description = prompt.description ?? ""
        preferredProvider = prompt.preferredProvider ?? ""
        preferredModel = prompt.preferredModel ?? ""
        outputType = prompt.outputType ?? "markdown"
        promptBody = prompt.bodyMarkdown
        // Salvage an instruction that was accidentally typed into a frontmatter field.
        if promptBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let misplaced = prompt.preferredProvider, misplaced.count > 25 {
            promptBody = misplaced
            preferredProvider = ""
        }
    }

    private func save() {
        let fields: [(String, String)] = [
            ("title", title), ("description", description), ("version", version),
            ("preferredProvider", preferredProvider), ("preferredModel", preferredModel),
            ("outputType", outputType)
        ]
        do {
            try model.prompts.writeFixedPrompt(prompt, fields: fields, body: promptBody)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
