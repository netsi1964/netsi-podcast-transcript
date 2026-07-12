import Foundation

/// Timestamp formatting shared by the timecoded transcript view and SRT export.
enum TimeFormatting {
    /// `1:23` or `1:02:03` — compact, for the on-screen timecoded list.
    static func clock(ms: Int) -> String {
        let totalSeconds = ms / 1000
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// `HH:MM:SS,mmm` — the exact form SubRip (.srt) requires (PRD-FEAT-012).
    static func srt(ms: Int) -> String {
        let h = ms / 3_600_000
        let m = (ms % 3_600_000) / 60_000
        let s = (ms % 60_000) / 1000
        let millis = ms % 1000
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, millis)
    }

    /// Human duration like `42 min` / `1 t 05 min` for library metadata.
    static func duration(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h) t \(String(format: "%02d", m)) min" }
        return "\(m) min"
    }
}
