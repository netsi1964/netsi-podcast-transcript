import SwiftUI

/// Reusable model chooser: a dropdown of the provider's models with a refresh control and a
/// fallback to typing a model id manually. Shared by prompt-run, chat and settings so the model
/// selection behaves identically everywhere (PRD-FEAT-008 model selection).
struct ModelPicker: View {
    @Binding var model: String
    let options: [String]
    let isLoading: Bool
    let reload: () -> Void
    @State private var custom = false

    /// Options including the current value, so the selection is always representable.
    private var opts: [String] {
        var o = options
        if !model.isEmpty && !o.contains(model) { o.insert(model, at: 0) }
        return o
    }

    var body: some View {
        HStack(spacing: 6) {
            if custom || (opts.isEmpty && !isLoading) {
                TextField("model-id", text: $model).textFieldStyle(.roundedBorder)
                if !opts.isEmpty {
                    Button("Vælg fra liste") { custom = false }.buttonStyle(.link).font(.caption)
                }
            } else {
                Picker("", selection: $model) {
                    ForEach(opts, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                Button("Egen…") { custom = true }.buttonStyle(.link).font(.caption)
            }
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Hent modeller fra provideren")
            }
        }
    }
}
