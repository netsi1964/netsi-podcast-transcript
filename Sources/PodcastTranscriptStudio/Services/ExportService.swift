import AppKit

/// File export/import: single Markdown/SRT, batch Markdown, and a full backup package
/// (SQLite + prompts, without API keys) — PRD-FEAT-012.
@MainActor
enum ExportService {

    // MARK: - Single exports

    static func exportTranscriptMarkdown(_ transcript: Transcript, episodeTitle: String) {
        let md = MarkdownSerializer.transcript(transcript, episodeTitle: episodeTitle)
        save(text: md, suggestedName: sanitized(episodeTitle) + ".md", type: "md")
    }

    static func exportOutputMarkdown(_ output: AIOutput, promptTitle: String?) {
        let md = MarkdownSerializer.output(output, promptTitle: promptTitle)
        save(text: md, suggestedName: (promptTitle.map(sanitized) ?? "output") + ".md", type: "md")
    }

    /// Exports `.srt`, but only when segments actually carry timing (PRD-FEAT-012 acceptance).
    static func exportSRT(segments: [TranscriptSegment], episodeTitle: String) -> Bool {
        guard let srt = MarkdownSerializer.srt(segments) else { return false }
        save(text: srt, suggestedName: sanitized(episodeTitle) + ".srt", type: "srt")
        return true
    }

    // MARK: - Batch export

    /// Exports every transcript in the library as Markdown files into a chosen folder.
    static func batchExportAllTranscripts(store: Store) {
        guard let folder = chooseDirectory(prompt: "Vælg mappe til alle transcripts") else { return }
        let episodes = (try? store.episodes()) ?? []
        for episode in episodes {
            guard let transcript = try? store.transcript(episodeID: episode.id) else { continue }
            let md = MarkdownSerializer.transcript(transcript, episodeTitle: episode.title)
            let url = folder.appendingPathComponent(sanitized(episode.title) + ".md")
            try? md.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Backup package

    /// Copies the SQLite database + prompt folder into a chosen backup directory. API keys live
    /// in Keychain and are deliberately excluded (PRD-FEAT-012 / PRD-SEC-007).
    static func exportBackup(store: Store, promptsFolder: URL) {
        guard let target = chooseDirectory(prompt: "Vælg mappe til backup") else { return }
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let pkg = target.appendingPathComponent("PodcastTranscriptStudio-backup-\(stamp)", isDirectory: true)
        let fm = FileManager.default
        try? fm.createDirectory(at: pkg, withIntermediateDirectories: true)
        try? fm.copyItem(at: store.databaseURL, to: pkg.appendingPathComponent("library.sqlite"))
        if fm.fileExists(atPath: promptsFolder.path) {
            try? fm.copyItem(at: promptsFolder, to: pkg.appendingPathComponent("Prompts"))
        }
        NSWorkspace.shared.open(pkg)
    }

    /// Restores prompts from a backup package into the live prompt folder (merge).
    /// The database itself is not overwritten live — the file is revealed for a manual swap,
    /// so a running app can't corrupt its open connection (PRD-FEAT-012.4, conservative).
    static func importBackup(into promptsFolder: URL) {
        guard let pkg = chooseDirectory(prompt: "Vælg en backup-mappe at importere") else { return }
        let fm = FileManager.default
        let promptsSrc = pkg.appendingPathComponent("Prompts")
        if fm.fileExists(atPath: promptsSrc.path),
           let files = try? fm.contentsOfDirectory(at: promptsSrc, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "md" {
                let dest = promptsFolder.appendingPathComponent(file.lastPathComponent)
                try? fm.removeItem(at: dest)
                try? fm.copyItem(at: file, to: dest)
            }
        }
        NSWorkspace.shared.activateFileViewerSelecting([pkg.appendingPathComponent("library.sqlite")])
    }

    // MARK: - Panels

    private static func save(text: String, suggestedName: String, type: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func chooseDirectory(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Vælg"
        panel.message = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func sanitized(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return name.components(separatedBy: invalid).joined(separator: "-")
    }
}
