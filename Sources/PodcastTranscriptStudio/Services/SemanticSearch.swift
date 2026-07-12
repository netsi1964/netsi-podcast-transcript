import Foundation

/// Cosine-similarity ranking over embeddings for semantic search.
enum SemanticSearch {
    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom > 0 ? dot / denom : 0
    }

    /// Ranks `docs` by similarity to `query`, keeping the top matches above `minScore`.
    static func rank(query: [Float], docs: [[Float]], topK: Int = 12, minScore: Float = 0.2) -> [(index: Int, score: Float)] {
        docs.enumerated()
            .map { (index: $0.offset, score: cosine(query, $0.element)) }
            .filter { $0.score >= minScore }
            .sorted { $0.score > $1.score }
            .prefix(topK)
            .map { $0 }
    }
}
