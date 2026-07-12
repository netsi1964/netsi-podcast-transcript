import Foundation

/// Turns app entities into Markdown — the app's native internal text format (PRD-SEC-001).
/// Every "copy as raw Markdown" action routes through here, so the serialisation is
/// defined in exactly one place (PRD-FEAT-005.2).
enum MarkdownSerializer {

    /// Podcast + episode metadata as a Markdown block (PRD-FEAT-014).
    static func metadata(podcast: Podcast?, episode: Episode) -> String {
        var lines: [String] = ["# \(episode.title)"]
        if let podcast { lines.append("**Podcast:** \(podcast.title)") }
        if let publisher = podcast?.publisher { lines.append("**Udgiver:** \(publisher)") }
        if let published = episode.publishedAt {
            lines.append("**Dato:** \(DateFormatting.medium(published))")
        }
        if let duration = episode.durationSeconds {
            lines.append("**Varighed:** \(TimeFormatting.duration(seconds: duration))")
        }
        lines.append("**Transcript-status:** \(episode.transcriptStatus.label)")
        lines.append("**Apple-link:** \(episode.appleURL)")
        if let desc = episode.descriptionMarkdown, !desc.isEmpty {
            lines.append("")
            lines.append(desc)
        }
        return lines.joined(separator: "\n")
    }

    /// The reading-friendly transcript is stored as Markdown already; this just guarantees
    /// a heading is present when copying the whole transcript.
    static func transcript(_ transcript: Transcript, episodeTitle: String) -> String {
        if transcript.markdown.hasPrefix("#") { return transcript.markdown }
        return "# \(episodeTitle) — transcript\n\n\(transcript.markdown)"
    }

    /// Timecoded segments as a Markdown list, e.g. `- **[1:23]** text`.
    static func timecoded(_ segments: [TranscriptSegment], episodeTitle: String) -> String {
        var lines = ["# \(episodeTitle) — tidskoder", ""]
        for seg in segments {
            if let start = seg.startMs {
                lines.append("- **[\(TimeFormatting.clock(ms: start))]** \(seg.text)")
            } else {
                lines.append("- \(seg.text)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// SubRip subtitle export from timecoded segments (PRD-FEAT-012).
    /// Returns nil when no segment carries timing information.
    static func srt(_ segments: [TranscriptSegment]) -> String? {
        let timed = segments.filter { $0.startMs != nil }
        guard !timed.isEmpty else { return nil }
        var blocks: [String] = []
        for (index, seg) in timed.enumerated() {
            let start = seg.startMs ?? 0
            let end = seg.endMs ?? (start + 2000)
            blocks.append("""
            \(index + 1)
            \(TimeFormatting.srt(ms: start)) --> \(TimeFormatting.srt(ms: end))
            \(seg.text)
            """)
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    /// AI output as a self-contained Markdown document with a provenance footer
    /// (which provider/model actually ran — PRD-FEAT-009 / PRD-FEAT-010).
    static func output(_ output: AIOutput, promptTitle: String?) -> String {
        var lines: [String] = []
        if let promptTitle { lines.append("# \(promptTitle)") }
        lines.append(output.outputMarkdown)
        lines.append("")
        lines.append("---")
        // Plain provenance line — no backticks/emphasis, which leaked an AttributedString
        // code-span placeholder ("%%CODEBLOCK0%%") and mangled styling when copied.
        lines.append("Genereret af \(output.providerType.displayName) · model \(output.model) · \(DateFormatting.medium(output.createdAt))")
        return lines.joined(separator: "\n")
    }

    /// A single chat message as Markdown (PRD-FEAT-011 copy support).
    static func chatMessage(_ message: ChatMessage) -> String {
        let who = message.role == .user ? "Du" : "Assistent"
        return "**\(who):**\n\n\(message.contentMarkdown)"
    }

    /// A whole chat session transcript.
    static func chatSession(_ session: ChatSession, messages: [ChatMessage]) -> String {
        var lines = ["# \(session.title ?? "Chat")", ""]
        lines.append(contentsOf: messages.map { chatMessage($0) + "\n" })
        return lines.joined(separator: "\n")
    }
}

enum DateFormatting {
    private static let medium: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "da_DK")
        return f
    }()
    static func medium(_ date: Date) -> String { medium.string(from: date) }
}
