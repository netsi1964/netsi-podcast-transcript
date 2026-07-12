import Foundation

/// Parsed identifiers from an Apple Podcasts episode URL (PRD-FEAT-002).
struct ApplePodcastsLink: Equatable, Sendable {
    /// The normalised, canonical URL string that gets stored on the episode.
    var normalizedURL: String
    /// Numeric podcast id parsed from the `/idXXXX` path segment, when present.
    var podcastID: String?
    /// Numeric episode id parsed from the `i=` query parameter, when present.
    var episodeID: String?
    /// Storefront/country code parsed from the first path segment (e.g. `dk`), when present.
    var storefront: String?
    /// Language hint parsed from the `l=` query parameter, when present.
    var languageCode: String?
    /// A best-effort human-readable slug title from the `/podcast/<slug>/` segment.
    var slugTitle: String?
}

enum ApplePodcastsURLError: LocalizedError, Equatable {
    case empty
    case notAURL
    case wrongHost(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Linket er tomt. Indsæt et Apple Podcasts episode-link."
        case .notAURL:
            return "Teksten kunne ikke læses som en URL."
        case .wrongHost(let host):
            return "Linket peger på \(host), ikke på podcasts.apple.com."
        }
    }
}

/// Parses links such as
/// `https://podcasts.apple.com/dk/podcast/some-slug/id1693194266?l=da&i=1000775594125`.
/// Invalid links throw a readable error rather than crashing (PRD-FEAT-002 acceptance).
enum ApplePodcastsURLParser {
    static func parse(_ raw: String) throws -> ApplePodcastsLink {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ApplePodcastsURLError.empty }

        guard let components = URLComponents(string: trimmed), let host = components.host else {
            throw ApplePodcastsURLError.notAURL
        }
        guard host.hasSuffix("apple.com") else {
            throw ApplePodcastsURLError.wrongHost(host)
        }

        // Path segments: e.g. ["dk", "podcast", "<slug>", "id1693194266"]
        let segments = components.path.split(separator: "/").map(String.init)

        var storefront: String?
        if let first = segments.first, first.count == 2, first.allSatisfy(\.isLetter) {
            storefront = first.lowercased()
        }

        var podcastID: String?
        if let idSegment = segments.first(where: { $0.hasPrefix("id") }),
           idSegment.dropFirst(2).allSatisfy(\.isNumber),
           idSegment.count > 2 {
            podcastID = String(idSegment.dropFirst(2))
        }

        var slugTitle: String?
        if let podcastIdx = segments.firstIndex(of: "podcast"), podcastIdx + 1 < segments.count {
            let slug = segments[podcastIdx + 1]
            if !slug.hasPrefix("id") {
                slugTitle = slug.replacingOccurrences(of: "-", with: " ")
            }
        }

        let queryItems = components.queryItems ?? []
        let episodeID = queryItems.first(where: { $0.name == "i" })?.value
        let languageCode = queryItems.first(where: { $0.name == "l" })?.value

        return ApplePodcastsLink(
            normalizedURL: normalize(components),
            podcastID: podcastID,
            episodeID: episodeID,
            storefront: storefront,
            languageCode: languageCode,
            slugTitle: slugTitle
        )
    }

    /// Drops volatile/tracking query params, keeping only the identity-bearing ones so the
    /// same episode normalises to the same URL (used as a dedupe key on import — PRD-SEC-009).
    private static func normalize(_ components: URLComponents) -> String {
        var copy = components
        copy.fragment = nil
        let keep: Set<String> = ["i", "l"]
        if let items = copy.queryItems {
            let filtered = items
                .filter { keep.contains($0.name) }
                .sorted { $0.name < $1.name }
            copy.queryItems = filtered.isEmpty ? nil : filtered
        }
        return copy.string ?? components.string ?? ""
    }
}
