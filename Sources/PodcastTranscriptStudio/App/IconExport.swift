import AppKit

/// Build-time helper: when the binary is run with `--export-iconset <dir>`, it writes the icon
/// PNGs for an `.iconset` and exits, without launching the GUI. The packaging script turns those
/// into an `.icns`. This reuses the same `AppIcon` drawing as the runtime Dock icon.
enum IconExport {
    /// Returns true if it handled an export request (the caller should then exit instead of
    /// starting the SwiftUI app).
    static func handleIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let flagIndex = args.firstIndex(of: "--export-iconset"), flagIndex + 1 < args.count else {
            return false
        }
        let directory = args[flagIndex + 1]
        do {
            try writeIconset(to: directory)
            FileHandle.standardOutput.write(Data("Wrote iconset to \(directory)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("Icon export failed: \(error)\n".utf8))
        }
        return true
    }

    private static func writeIconset(to directory: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        // Standard macOS iconset entries (points @ scale → pixels).
        let entries: [(name: String, pixels: Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024)
        ]
        let base = URL(fileURLWithPath: directory)
        for entry in entries {
            guard let data = AppIcon.pngData(size: entry.pixels) else { continue }
            try data.write(to: base.appendingPathComponent("\(entry.name).png"))
        }
    }
}
