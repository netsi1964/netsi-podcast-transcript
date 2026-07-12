import SwiftUI

/// The paste-a-link import flow (PRD-FEAT-002). Validates the link and shows a readable error
/// instead of failing silently.
struct ImportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedEpisodeID: String?

    @State private var link = ""
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Importér episode").font(.title2.bold())
            Text("Indsæt et Apple Podcasts episode-link.")
                .foregroundStyle(.secondary)

            TextField("https://podcasts.apple.com/…", text: $link, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .onSubmit(runImport)

            if let errorText {
                SelectableError(message: errorText)
            }

            HStack {
                Spacer()
                Button("Annullér") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    runImport()
                } label: {
                    if isWorking { ProgressView().controlSize(.small) }
                    else { Text("Importér") }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func runImport() {
        errorText = nil
        // Validate up front so obvious errors show immediately (PRD-FEAT-002 acceptance).
        do { _ = try ApplePodcastsURLParser.parse(link) }
        catch { errorText = error.localizedDescription; return }

        isWorking = true
        Task {
            let id = await model.importEpisode(fromLink: link)
            isWorking = false
            if let id {
                selectedEpisodeID = id
                dismiss()
            } else {
                errorText = model.lastError
                model.lastError = nil
            }
        }
    }
}
