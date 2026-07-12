import Foundation

/// One row from an Apple podcast search — either a show or a specific episode.
struct PodcastSearchResult: Identifiable, Hashable {
    enum Kind { case podcast, episode }

    var id: String
    var kind: Kind
    var podcastTitle: String
    var episodeTitle: String?
    var appleURL: String?
    var artworkURL: String?
    var releaseDate: Date?
    var durationSeconds: Int?
    var descriptionText: String?
    var applePodcastID: String?
    var appleEpisodeID: String?
    var feedURL: String?
}

/// Searches Apple's public **iTunes Search API** (no auth) so the user can find and import
/// podcasts and episodes instead of pasting links (PRD-SEC-010 future expansion: katalog-søgning).
enum PodcastSearchService {
    private static let base = "https://itunes.apple.com/search"

    static func search(term: String, kind: PodcastSearchResult.Kind, limit: Int = 25) async throws -> [PodcastSearchResult] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: base)!
        components.queryItems = [
            .init(name: "media", value: "podcast"),
            .init(name: "entity", value: kind == .episode ? "podcastEpisode" : "podcast"),
            .init(name: "term", value: trimmed),
            .init(name: "limit", value: String(limit))
        ]
        guard let url = components.url else { return [] }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMError.http(http.statusCode, "iTunes Search")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { parse($0, kind: kind) }
    }

    private static func parse(_ item: [String: Any], kind: PodcastSearchResult.Kind) -> PodcastSearchResult? {
        let collectionName = item["collectionName"] as? String ?? item["artistName"] as? String ?? "Ukendt podcast"
        let artwork = (item["artworkUrl600"] as? String) ?? (item["artworkUrl100"] as? String)
        let podcastID = (item["collectionId"] as? Int).map(String.init)

        switch kind {
        case .episode:
            let episodeTitle = item["trackName"] as? String ?? "Episode"
            let appleURL = item["trackViewUrl"] as? String ?? item["collectionViewUrl"] as? String
            let episodeID = (item["trackId"] as? Int).map(String.init)
            return PodcastSearchResult(
                id: episodeID ?? UUID().uuidString,
                kind: .episode,
                podcastTitle: collectionName,
                episodeTitle: episodeTitle,
                appleURL: appleURL,
                artworkURL: artwork,
                releaseDate: parseDate(item["releaseDate"] as? String),
                durationSeconds: (item["trackTimeMillis"] as? Int).map { $0 / 1000 },
                descriptionText: item["description"] as? String ?? item["shortDescription"] as? String,
                applePodcastID: podcastID,
                appleEpisodeID: episodeID,
                feedURL: item["feedUrl"] as? String
            )
        case .podcast:
            let appleURL = item["collectionViewUrl"] as? String
            return PodcastSearchResult(
                id: podcastID ?? UUID().uuidString,
                kind: .podcast,
                podcastTitle: collectionName,
                episodeTitle: nil,
                appleURL: appleURL,
                artworkURL: artwork,
                releaseDate: parseDate(item["releaseDate"] as? String),
                durationSeconds: nil,
                descriptionText: nil,
                applePodcastID: podcastID,
                appleEpisodeID: nil,
                feedURL: item["feedUrl"] as? String
            )
        }
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }
}
