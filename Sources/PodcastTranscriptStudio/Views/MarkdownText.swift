import SwiftUI

/// Renders a block of Markdown as read-friendly text. Everything is composed into a single
/// `AttributedString` shown in one `Text`, so the user can select continuously across the whole
/// content — separate `Text` views can't share one selection on macOS (PRD-FEAT-004 selection).
struct MarkdownText: View {
    let markdown: String
    /// In-text search: matches get an orange background; the active match is stronger.
    var highlight: String = ""
    var activeMatch: Int = 0

    var body: some View {
        Text(rendered)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var rendered: AttributedString {
        // Line-based rendering so lists, headings and single line breaks all survive — a plain
        // block split collapsed list items into one run-together paragraph.
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        var result = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 { result += AttributedString("\n") }
            result += attributed(for: line)
        }
        applyHighlights(to: &result)
        return result
    }

    /// Paints an orange background on every case-insensitive match, brighter on the active one.
    private func applyHighlights(to attr: inout AttributedString) {
        let q = highlight.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let plain = String(attr.characters)
        var start = plain.startIndex
        var matchIndex = 0
        while let r = plain.range(of: q, options: .caseInsensitive, range: start..<plain.endIndex) {
            let lowerOffset = plain.distance(from: plain.startIndex, to: r.lowerBound)
            let length = plain.distance(from: r.lowerBound, to: r.upperBound)
            let lower = attr.index(attr.startIndex, offsetByCharacters: lowerOffset)
            let upper = attr.index(lower, offsetByCharacters: length)
            let isActive = matchIndex == activeMatch
            attr[lower..<upper].backgroundColor = isActive ? Color.netsiOrange : Color.netsiOrange.opacity(0.35)
            if isActive { attr[lower..<upper].foregroundColor = .black }
            matchIndex += 1
            start = r.upperBound
        }
    }

    /// Renders one Markdown line: headings, bullet/numbered list items, thematic rules, or a
    /// paragraph with inline styling.
    private func attributed(for line: String) -> AttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return AttributedString("") }

        // Thematic break (---, ***, ___).
        if trimmed.count >= 3, Set(trimmed).isSubset(of: ["-", "*", "_"]) {
            var s = AttributedString(String(repeating: "─", count: 24))
            s.foregroundColor = .secondary
            return s
        }
        if trimmed.hasPrefix("### ") { return heading(String(trimmed.dropFirst(4)), font: .headline) }
        if trimmed.hasPrefix("## ") { return heading(String(trimmed.dropFirst(3)), font: .title3.bold()) }
        if trimmed.hasPrefix("# ") { return heading(String(trimmed.dropFirst(2)), font: .title2.bold()) }

        // Bullet list: -, *, +
        if let marker = ["- ", "* ", "+ "].first(where: { trimmed.hasPrefix($0) }) {
            return AttributedString("•\t") + inline(String(trimmed.dropFirst(marker.count)))
        }
        // Numbered list: "1. ", "2) " …
        if let range = trimmed.range(of: #"^\d+[.)]\s"#, options: .regularExpression) {
            let number = trimmed[trimmed.startIndex..<trimmed.index(before: range.upperBound)]
            return AttributedString("\(number)\t") + inline(String(trimmed[range.upperBound...]))
        }
        // Blockquote
        if trimmed.hasPrefix("> ") {
            var s = inline(String(trimmed.dropFirst(2)))
            s.foregroundColor = .secondary
            return s
        }
        return inline(line)
    }

    private func heading(_ text: String, font: Font) -> AttributedString {
        var s = inline(text)
        s.font = font
        return s
    }

    /// Inline Markdown (bold/italic/links/code) for a single line. `.inlineOnly` keeps it on one
    /// line; `.full` would wrap it in block structure.
    private func inline(_ text: String) -> AttributedString {
        if var parsed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                           failurePolicy: .returnPartiallyParsedIfPossible)
        ) {
            parsed.font = parsed.font ?? .body
            return parsed
        }
        return AttributedString(text)
    }
}
