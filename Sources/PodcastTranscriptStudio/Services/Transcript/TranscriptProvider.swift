import Foundation

/// A retrieved transcript before it is persisted: reading Markdown plus timed segments.
struct FetchedTranscript {
    var languageCode: String?
    var markdown: String
    var plainText: String
    var segments: [FetchedSegment]
    var rawPayload: String?
}

struct FetchedSegment {
    var startMs: Int?
    var endMs: Int?
    var text: String
}

enum TranscriptFetchError: LocalizedError {
    case notFound
    case notDownloaded
    case unsupported
    case parsing(String)

    var errorDescription: String? {
        switch self {
        case .notFound: return "Der blev ikke fundet et transcript for episoden."
        case .notDownloaded:
            return "Apple har et transcript til episoden, men det er ikke hentet ned på din Mac endnu. "
                + "Åbn episoden i Apple Podcasts, vis transskriptionen, og tryk så \"Indlæs igen\"."
        case .unsupported: return "Denne transcript-kilde understøttes ikke endnu."
        case .parsing(let m): return "Kunne ikke læse transcriptet: \(m)"
        }
    }
}

/// Abstraction over *where* a transcript comes from. Apple is the v1 source, but keeping this
/// behind a protocol isolates the fragile integration risk (PRD-SEC-009) and lets other
/// sources (Whisper, uploads) slot in later without touching the rest of the app.
protocol TranscriptProvider: Sendable {
    /// Attempts to fetch a transcript for the given episode. Throws `.notFound` when none exists.
    func fetchTranscript(for episode: Episode, link: ApplePodcastsLink?) async throws -> FetchedTranscript
}
