import XCTest
@testable import PodcastTranscriptStudio

final class PodcastSearchServiceTests: XCTestCase {
    /// Apple's lookup endpoint prepends the show itself as a `track` row whose `trackId` equals
    /// the `collectionId`. It must not become an episode (PRD-FEAT-002).
    private let showRow: [String: Any] = [
        "wrapperType": "track",
        "kind": "podcast",
        "collectionId": 265264862,
        "trackId": 265264862,
        "trackName": "Tara Brach",
        "collectionName": "Tara Brach",
        "trackTimeMillis": 1172,
    ]

    private func episodeRow(id: Int, name: String, released: String) -> [String: Any] {
        [
            "wrapperType": "podcastEpisode",
            "kind": "podcast-episode",
            "collectionId": 265264862,
            "trackId": id,
            "trackName": name,
            "collectionName": "Tara Brach",
            "trackViewUrl": "https://podcasts.apple.com/us/podcast/x/id265264862?i=\(id)",
            "releaseDate": released,
            "trackTimeMillis": 3380000,
        ]
    }

    func testDropsTheShowRowAndKeepsEpisodes() {
        let parsed = PodcastSearchService.parseEpisodeLookup([
            showRow,
            episodeRow(id: 1000777056215, name: "Stories That Imprison Our Heart", released: "2026-07-16T12:00:00Z"),
            episodeRow(id: 1000776955820, name: "The Art of Letting Go", released: "2026-07-15T19:30:00Z"),
        ])

        XCTAssertEqual(parsed.count, 2)
        XCTAssertFalse(parsed.contains { $0.episodeTitle == "Tara Brach" }, "the show itself leaked in as an episode")
        XCTAssertEqual(parsed.first?.appleEpisodeID, "1000777056215")
        XCTAssertEqual(parsed.first?.podcastTitle, "Tara Brach")
        XCTAssertEqual(parsed.first?.durationSeconds, 3380)
        XCTAssertEqual(parsed.allSatisfy { $0.kind == .episode }, true)
    }

    func testShowOnlyLookupYieldsNoEpisodes() {
        XCTAssertTrue(PodcastSearchService.parseEpisodeLookup([showRow]).isEmpty)
    }
}
