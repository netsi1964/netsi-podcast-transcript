import AppKit

/// Draws the app icon programmatically so the app has a proper Dock icon even when run as a bare
/// SwiftPM binary (no bundled `.icns`). A packaged `.app` would ship an asset catalog instead.
enum AppIcon {
    static func image(size: CGFloat = 512) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }
        draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        return image
    }

    /// Renders a PNG headlessly (no running NSApplication needed) — used by the icon exporter
    /// during app packaging.
    static func pngData(size: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// Draws the icon into the current graphics context, filling `rect`.
    static func draw(in rect: NSRect) {
        let size = rect.width
        let corner = size * 0.22
        let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
        path.addClip()

        // Diagonal purple→blue gradient background.
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.42, green: 0.24, blue: 0.86, alpha: 1),
            NSColor(calibratedRed: 0.18, green: 0.52, blue: 0.96, alpha: 1)
        ])
        gradient?.draw(in: rect, angle: -55)

        // Centred audio-waveform of rounded bars.
        let heights: [CGFloat] = [0.30, 0.55, 0.82, 0.48, 0.95, 0.62, 0.38, 0.70, 0.44]
        let barWidth = size * 0.052
        let gap = size * 0.038
        let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
        var x = (size - totalWidth) / 2
        NSColor.white.withAlphaComponent(0.95).setFill()
        for h in heights {
            let barHeight = size * 0.5 * h
            let barRect = NSRect(x: x, y: (size - barHeight) / 2, width: barWidth, height: barHeight)
            NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            x += barWidth + gap
        }
    }
}
