import Foundation

/// Parses TTML (Timed Text Markup Language) — the format Apple Podcasts uses for transcripts.
/// Extracts each `<p>` cue with its `begin`/`end` timing into a `FetchedSegment`.
final class TTMLParser: NSObject, XMLParserDelegate {

    static func parse(_ xml: String) throws -> FetchedTranscript {
        let parser = TTMLParser()
        return try parser.run(xml)
    }

    private var segments: [FetchedSegment] = []
    private var currentText = ""
    private var currentBegin: Int?
    private var currentEnd: Int?
    private var insideParagraph = false
    private var languageCode: String?

    private func run(_ xml: String) throws -> FetchedTranscript {
        guard let data = xml.data(using: .utf8) else {
            throw TranscriptFetchError.parsing("ugyldig tekstkodning")
        }
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw TranscriptFetchError.parsing(parser.parserError?.localizedDescription ?? "ukendt XML-fejl")
        }
        guard !segments.isEmpty else { throw TranscriptFetchError.notFound }

        let plain = segments.map(\.text).joined(separator: " ")
        let markdown = segments.map { "\($0.text)" }.joined(separator: "\n\n")
        return FetchedTranscript(
            languageCode: languageCode,
            markdown: markdown,
            plainText: plain,
            segments: segments,
            rawPayload: xml
        )
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        let name = elementName.lowercased()
        if name == "tt", let lang = attributes["xml:lang"] ?? attributes["lang"] {
            languageCode = lang
        }
        if name == "p" {
            insideParagraph = true
            currentText = ""
            currentBegin = attributes["begin"].flatMap(TTMLParser.parseTime)
            currentEnd = attributes["end"].flatMap(TTMLParser.parseTime)
        }
        // Apple's TTML puts each word in its own nested element (usually <span>) with no
        // whitespace text node between them, so any nested element start inside a paragraph must
        // be treated as a word boundary — otherwise every word runs together.
        if insideParagraph, name != "p", needsSeparatorBeforeNextRun() {
            currentText += " "
        }
    }

    /// True when the accumulated text is non-empty and doesn't already end in whitespace.
    private func needsSeparatorBeforeNextRun() -> Bool {
        guard let last = currentText.last else { return false }
        return !last.isWhitespace
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideParagraph else { return }
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName.lowercased() == "p" else { return }
        insideParagraph = false
        let text = currentText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        segments.append(FetchedSegment(startMs: currentBegin, endMs: currentEnd, text: text))
    }

    /// Accepts both clock (`00:01:02.345`) and offset (`62.5s`, `620ms`) TTML time forms.
    static func parseTime(_ raw: String) -> Int? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.contains(":") {
            let parts = value.split(separator: ":").map(String.init)
            let nums = parts.compactMap { Double($0) }
            guard nums.count == parts.count, !nums.isEmpty else { return nil }
            var seconds = 0.0
            for n in nums { seconds = seconds * 60 + n }
            return Int(seconds * 1000)
        }
        if value.hasSuffix("ms"), let ms = Double(value.dropLast(2)) {
            return Int(ms)
        }
        if value.hasSuffix("s"), let s = Double(value.dropLast()) {
            return Int(s * 1000)
        }
        if let s = Double(value) {
            return Int(s * 1000)
        }
        return nil
    }
}
