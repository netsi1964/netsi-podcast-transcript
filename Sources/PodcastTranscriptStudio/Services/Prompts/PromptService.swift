import Foundation
import Combine

/// Owns the on-disk prompt folder: seeds defaults on first run, loads prompt files, and
/// watches the folder so new/changed `.md` files become app actions live (PRD-FEAT-006).
@MainActor
final class PromptService: ObservableObject {
    @Published private(set) var prompts: [Prompt] = []

    /// Only genuinely-broken prompts (empty files) drive the fix banner — warnings still run, so we
    /// don't nag about optional frontmatter (PRD-FEAT-007).
    var invalidPrompts: [Prompt] { prompts.filter { $0.validationStatus == .invalid } }

    let folderURL: URL
    private let store: Store
    private var watcher: DirectoryWatcher?
    private var reloadWorkItem: DispatchWorkItem?

    init(store: Store, folderURL: URL? = nil) {
        self.store = store
        self.folderURL = folderURL ?? PromptService.defaultFolderURL()
    }

    static func defaultFolderURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("PodcastTranscriptStudio", isDirectory: true)
            .appendingPathComponent("Prompts", isDirectory: true)
    }

    /// Creates the folder + seeds defaults if empty, does the first load, and starts watching.
    func start() {
        ensureFolderAndDefaults()
        reloadNow()
        watcher = DirectoryWatcher(url: folderURL) { [weak self] in
            self?.scheduleReload()
        }
    }

    private func ensureFolderAndDefaults() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        // Seed bundled defaults per-file: any default that isn't already in the folder gets
        // copied in — on first run this seeds everything (PRD-FEAT-006 acceptance), and on later
        // launches it delivers newly bundled defaults without touching the user's existing or
        // edited prompts. A default the user has deliberately deleted will reappear next launch.
        guard let seedDir = Bundle.module.url(forResource: "DefaultPrompts", withExtension: nil),
              let seeds = try? fm.contentsOfDirectory(at: seedDir, includingPropertiesForKeys: nil)
        else { return }
        for seed in seeds where seed.pathExtension == "md" {
            let dest = folderURL.appendingPathComponent(seed.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) {
                try? fm.copyItem(at: seed, to: dest)
            }
        }
    }

    /// Debounces bursts of filesystem events into a single reload.
    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reloadNow() }
        reloadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func reloadNow() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []

        var loaded: [Prompt] = []
        for file in files where file.pathExtension == "md" {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .now
            loaded.append(PromptLoader.makePrompt(fromContents: text, filePath: file.path, modifiedAt: modified))
        }
        loaded.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        prompts = loaded
        try? store.replaceAllPrompts(loaded)
    }

    /// Writes a repaired prompt back to its file; the watcher then reloads it (PRD-FEAT-007).
    func writeFixedPrompt(_ prompt: Prompt, fields: [(String, String)], body: String) throws {
        let contents = FrontmatterParser.render(fields: fields, body: body)
        try contents.write(to: URL(fileURLWithPath: prompt.filePath), atomically: true, encoding: .utf8)
        reloadNow()
    }
}

/// Watches a directory for changes using a kernel-backed `DispatchSource`. Re-arms itself if
/// the folder is atomically replaced (common when editors save).
final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let url: URL
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        arm()
    }

    private func arm() {
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            self.onChange()
            if src.data.contains(.delete) || src.data.contains(.rename) {
                self.rearm()
            }
        }
        src.setCancelHandler { [fd = fileDescriptor] in close(fd) }
        source = src
        src.resume()
    }

    private func rearm() {
        source?.cancel()
        source = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.arm() }
    }

    deinit {
        source?.cancel()
    }
}
