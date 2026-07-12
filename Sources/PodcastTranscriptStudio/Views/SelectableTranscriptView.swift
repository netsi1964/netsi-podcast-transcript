import SwiftUI
import AppKit

/// A read-only, fully selectable transcript view backed by `NSTextView`, with a right-click
/// "Kør prompt" menu. If the user has selected text, only that selection is sent to the prompt;
/// otherwise the whole transcript is used (PRD-FEAT-004 selection → prompt).
struct SelectableTranscriptView: NSViewRepresentable {
    let markdown: String
    let prompts: [Prompt]
    /// Called with the chosen prompt and the selected text (nil = no selection → use everything).
    let onRun: (Prompt, String?) -> Void
    /// Literal in-text find: highlight matches (orange), scroll to the active one, report count.
    var highlightQuery: String = ""
    var activeMatch: Int = 0
    var onMatchCount: (Int) -> Void = { _ in }
    /// Semantic find: whole segment texts to highlight, ranked; `semanticActive` is the current one.
    var semanticHighlights: [String] = []
    var semanticActive: Int = 0

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PromptTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isRichText = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = textView
        context.coordinator.textView = textView
        update(textView)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? PromptTextView else { return }
        update(textView)
    }

    private func update(_ textView: PromptTextView) {
        textView.prompts = prompts
        textView.onRun = onRun
        if textView.cachedMarkdown != markdown {
            textView.cachedMarkdown = markdown
            textView.textStorage?.setAttributedString(TranscriptAttributedString.make(from: markdown))
        }
        if !semanticHighlights.isEmpty {
            textView.applySemanticHighlights(texts: semanticHighlights, active: semanticActive)
        } else {
            let count = textView.applyHighlights(query: highlightQuery, active: activeMatch)
            DispatchQueue.main.async { onMatchCount(count) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { weak var textView: PromptTextView? }
}

/// NSTextView that injects a "Kør prompt" submenu into its context menu.
final class PromptTextView: NSTextView {
    var prompts: [Prompt] = []
    var onRun: ((Prompt, String?) -> Void)?
    var cachedMarkdown: String = "\u{0}"   // sentinel so first real value always applies

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard !prompts.isEmpty else { return menu }

        menu.addItem(.separator())
        let hasSelection = selectedRange().length > 0
        let parent = NSMenuItem(
            title: hasSelection ? "Kør prompt på markering" : "Kør prompt på hele transcriptet",
            action: nil, keyEquivalent: ""
        )
        let submenu = NSMenu()
        for prompt in prompts {
            let item = NSMenuItem(title: prompt.title, action: #selector(runPromptItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = prompt
            submenu.addItem(item)
        }
        parent.submenu = submenu
        menu.addItem(parent)
        return menu
    }

    @objc private func runPromptItem(_ sender: NSMenuItem) {
        guard let prompt = sender.representedObject as? Prompt else { return }
        let range = selectedRange()
        let selected = range.length > 0 ? (string as NSString).substring(with: range) : nil
        onRun?(prompt, selected)
    }

    /// Highlights all case-insensitive matches with an orange background (the active one brighter),
    /// scrolls the active match into view, and returns the total match count. Uses layout-manager
    /// temporary attributes so the underlying text styling is left untouched.
    func applyHighlights(query: String, active: Int) -> Int {
        guard let layoutManager, let textStorage else { return 0 }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return 0 }

        let text = textStorage.string as NSString
        var ranges: [NSRange] = []
        var searchStart = 0
        while searchStart < text.length {
            let found = text.range(of: q, options: .caseInsensitive,
                                   range: NSRange(location: searchStart, length: text.length - searchStart))
            if found.location == NSNotFound { break }
            ranges.append(found)
            searchStart = found.location + max(found.length, 1)
        }

        for (index, range) in ranges.enumerated() {
            let isActive = index == active
            layoutManager.addTemporaryAttribute(.backgroundColor,
                value: isActive ? NSColor.netsiOrange : NSColor.netsiOrange.withAlphaComponent(0.35),
                forCharacterRange: range)
            if isActive {
                layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor.black, forCharacterRange: range)
            }
        }
        if active < ranges.count {
            scrollRangeToVisible(ranges[active])
        }
        return ranges.count
    }

    /// Highlights whole segment texts (semantic results), brighter for the active one, and scrolls
    /// the active segment into view.
    func applySemanticHighlights(texts: [String], active: Int) {
        guard let layoutManager, let textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)

        let haystack = textStorage.string as NSString
        var activeRange: NSRange?
        for (index, text) in texts.enumerated() where !text.isEmpty {
            let range = haystack.range(of: text)
            guard range.location != NSNotFound else { continue }
            let isActive = index == active
            layoutManager.addTemporaryAttribute(.backgroundColor,
                value: isActive ? NSColor.netsiOrange : NSColor.netsiOrange.withAlphaComponent(0.35),
                forCharacterRange: range)
            if isActive {
                layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor.black, forCharacterRange: range)
                activeRange = range
            }
        }
        if let activeRange { scrollRangeToVisible(activeRange) }
    }
}

/// Builds a lightweight styled `NSAttributedString` for transcript markdown: bold headings,
/// body text otherwise. Kept simple — the transcript is mostly prose.
enum TranscriptAttributedString {
    static func make(from markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let blocks = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let bodyColor = NSColor.labelColor
        for (index, block) in blocks.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n\n")) }
            let (text, font): (String, NSFont)
            if block.hasPrefix("## ") {
                text = String(block.dropFirst(3)); font = .boldSystemFont(ofSize: 15)
            } else if block.hasPrefix("# ") {
                text = String(block.dropFirst(2)); font = .boldSystemFont(ofSize: 17)
            } else {
                text = block; font = .systemFont(ofSize: 13)
            }
            result.append(NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: bodyColor
            ]))
        }
        return result
    }
}
