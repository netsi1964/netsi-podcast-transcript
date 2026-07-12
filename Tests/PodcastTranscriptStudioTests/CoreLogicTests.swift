import XCTest
@testable import PodcastTranscriptStudio

final class ApplePodcastsURLParserTests: XCTestCase {
    func testParsesFullEpisodeLink() throws {
        let link = try ApplePodcastsURLParser.parse(
            "https://podcasts.apple.com/dk/podcast/some-great-show/id1693194266?l=da&i=1000775594125"
        )
        XCTAssertEqual(link.podcastID, "1693194266")
        XCTAssertEqual(link.episodeID, "1000775594125")
        XCTAssertEqual(link.storefront, "dk")
        XCTAssertEqual(link.languageCode, "da")
        XCTAssertEqual(link.slugTitle, "some great show")
    }

    func testNormalisationDropsTrackingParams() throws {
        let a = try ApplePodcastsURLParser.parse(
            "https://podcasts.apple.com/dk/podcast/x/id123?i=999&utm_source=x&l=da"
        )
        let b = try ApplePodcastsURLParser.parse(
            "https://podcasts.apple.com/dk/podcast/x/id123?l=da&i=999"
        )
        XCTAssertEqual(a.normalizedURL, b.normalizedURL, "same episode should normalise identically")
    }

    func testEmptyThrows() {
        XCTAssertThrowsError(try ApplePodcastsURLParser.parse("   "))
    }

    func testWrongHostThrows() {
        XCTAssertThrowsError(try ApplePodcastsURLParser.parse("https://example.com/foo"))
    }
}

final class TTMLParserTests: XCTestCase {
    func testParsesCuesAndTimes() throws {
        let xml = """
        <tt xml:lang="da"><body><div>
        <p begin="00:00:01.000" end="00:00:03.500">Hej med dig</p>
        <p begin="3.5s" end="6s">Velkommen til showet</p>
        </div></body></tt>
        """
        let result = try TTMLParser.parse(xml)
        XCTAssertEqual(result.languageCode, "da")
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].startMs, 1000)
        XCTAssertEqual(result.segments[0].endMs, 3500)
        XCTAssertEqual(result.segments[1].startMs, 3500)
        XCTAssertTrue(result.plainText.contains("Velkommen"))
    }

    func testTimeParsingForms() {
        XCTAssertEqual(TTMLParser.parseTime("00:01:02.500"), 62500)
        XCTAssertEqual(TTMLParser.parseTime("620ms"), 620)
        XCTAssertEqual(TTMLParser.parseTime("2.5s"), 2500)
    }

    /// Apple wraps each word in its own <span>; words must not run together (regression).
    func testWordPerSpanKeepsSpaces() throws {
        let xml = """
        <tt xml:lang="da"><body><div>
        <p begin="0s" end="2s"><span>Til</span><span>allersidste</span><span>fløjt</span></p>
        </div></body></tt>
        """
        let result = try TTMLParser.parse(xml)
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].text, "Til allersidste fløjt")
        XCTAssertTrue(result.plainText.contains("Til allersidste fløjt"))
    }
}

final class FrontmatterTests: XCTestCase {
    func testParsesFrontmatter() {
        let doc = FrontmatterParser.parse("""
        ---
        title: Resumé
        version: 2
        ---
        Body text here
        """)
        XCTAssertTrue(doc.hadFrontmatter)
        XCTAssertEqual(doc.fields["title"], "Resumé")
        XCTAssertEqual(doc.fields["version"], "2")
        XCTAssertEqual(doc.body, "Body text here")
    }

    func testMissingFrontmatterIsUsable() {
        // A plain prompt file (no frontmatter) is usable — a warning at most, never invalid.
        let doc = FrontmatterParser.parse("Just a body, no frontmatter")
        let (status, _) = PromptLoader.validate(doc: doc)
        XCTAssertEqual(status, .warning)
    }

    func testEmptyPromptIsInvalid() {
        let doc = FrontmatterParser.parse("---\ntitle: X\n---\n")
        let (status, _) = PromptLoader.validate(doc: doc)
        XCTAssertEqual(status, .invalid)
    }

    func testMissingRecommendedFieldsWarns() {
        let doc = FrontmatterParser.parse("---\ndescription: x\n---\nBody")
        let (status, _) = PromptLoader.validate(doc: doc)
        XCTAssertEqual(status, .warning)
    }
}

final class SRTExportTests: XCTestCase {
    func testSRTFormatting() {
        let segments = [
            TranscriptSegment(transcriptID: "t", startMs: 1000, endMs: 3500, text: "Hej", markdown: "Hej", sequenceIndex: 0),
            TranscriptSegment(transcriptID: "t", startMs: 3500, endMs: 6000, text: "Verden", markdown: "Verden", sequenceIndex: 1)
        ]
        let srt = MarkdownSerializer.srt(segments)
        XCTAssertNotNil(srt)
        XCTAssertTrue(srt!.contains("00:00:01,000 --> 00:00:03,500"))
        XCTAssertTrue(srt!.contains("Verden"))
    }

    func testSRTNilWhenNoTiming() {
        let segments = [TranscriptSegment(transcriptID: "t", startMs: nil, endMs: nil, text: "x", markdown: "x", sequenceIndex: 0)]
        XCTAssertNil(MarkdownSerializer.srt(segments))
    }
}

final class SemanticSearchTests: XCTestCase {
    func testCosineIdenticalIsOne() {
        XCTAssertEqual(SemanticSearch.cosine([1, 0, 1], [1, 0, 1]), 1, accuracy: 0.0001)
    }

    func testCosineOrthogonalIsZero() {
        XCTAssertEqual(SemanticSearch.cosine([1, 0], [0, 1]), 0, accuracy: 0.0001)
    }

    func testRankOrdersBySimilarityAndFilters() {
        let query: [Float] = [1, 0]
        let docs: [[Float]] = [[0, 1], [0.9, 0.1], [1, 0]]
        let ranked = SemanticSearch.rank(query: query, docs: docs, topK: 2, minScore: 0.2)
        XCTAssertEqual(ranked.count, 2)
        XCTAssertEqual(ranked.first?.index, 2, "most similar doc ranks first")
        XCTAssertFalse(ranked.contains { $0.index == 0 }, "orthogonal doc filtered out")
    }
}

final class StoreTests: XCTestCase {
    func testUpsertDeduplicatesByAppleEpisodeID() throws {
        let store = try Store.inMemory()
        let podcast = try store.upsertPodcast(Podcast(title: "P"))
        let e1 = try store.upsertEpisode(Episode(podcastID: podcast.id, appleEpisodeID: "999", title: "First", appleURL: "u"))
        let e2 = try store.upsertEpisode(Episode(podcastID: podcast.id, appleEpisodeID: "999", title: "Updated", appleURL: "u"))
        XCTAssertEqual(e1.id, e2.id, "same apple episode id must map to one row")
        XCTAssertEqual(try store.episodes().count, 1)
        XCTAssertEqual(try store.episode(id: e1.id)?.title, "Updated")
    }

    func testTranscriptSearchFindsEpisode() throws {
        let store = try Store.inMemory()
        let podcast = try store.upsertPodcast(Podcast(title: "P"))
        let episode = try store.upsertEpisode(Episode(podcastID: podcast.id, title: "E", appleURL: "u"))
        let transcript = Transcript(episodeID: episode.id, markdown: "quantum computing", plainText: "quantum computing breakthrough")
        try store.saveTranscript(transcript, segments: [])
        let hits = try store.episodes(matching: "quantum")
        XCTAssertEqual(hits.count, 1)
    }
}
