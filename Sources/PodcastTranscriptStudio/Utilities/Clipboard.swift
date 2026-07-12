import AppKit

/// Central clipboard helper. Every copy action in the app goes through here so behaviour is
/// consistent (PRD-FEAT-005 copy-everything principle).
enum Clipboard {
    /// Copies raw Markdown as plain text.
    static func copyMarkdown(_ markdown: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(markdown, forType: .string)
    }

    /// Copies a display-friendly form: rendered rich text with the Markdown as a plain-text
    /// fallback, so pasting into rich editors looks formatted and plain editors still work.
    static func copyFormatted(_ markdown: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let attributed = try? NSAttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ), let rtf = try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            pb.setData(rtf, forType: .rtf)
            pb.setString(attributed.string, forType: .string)
        } else {
            pb.setString(markdown, forType: .string)
        }
    }
}
