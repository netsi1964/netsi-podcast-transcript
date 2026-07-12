import SwiftUI

/// A reusable "copy" control offering both display-formatted and raw-Markdown copies. Used
/// everywhere content is shown, giving the app one consistent copy affordance (PRD-FEAT-005.1).
struct CopyMenu: View {
    let markdown: () -> String
    var label: String = "Kopiér"

    var body: some View {
        Menu {
            Button("Kopiér som tekst") { Clipboard.copyFormatted(markdown()) }
            Button("Kopiér som Markdown") { Clipboard.copyMarkdown(markdown()) }
        } label: {
            Label(label, systemImage: "doc.on.doc")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

/// An error banner whose message can be selected and copied (raw text). Errors are just as
/// copyable as any other content in the app (PRD-FEAT-005 copy-everything).
struct SelectableError: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                Clipboard.copyMarkdown(message)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Kopiér fejlbesked")
        }
        .padding(10)
        .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Toolbar-friendly variant with just an icon.
struct CopyIconMenu: View {
    let markdown: () -> String

    var body: some View {
        Menu {
            Button("Kopiér som tekst") { Clipboard.copyFormatted(markdown()) }
            Button("Kopiér som Markdown") { Clipboard.copyMarkdown(markdown()) }
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .help("Kopiér")
    }
}
