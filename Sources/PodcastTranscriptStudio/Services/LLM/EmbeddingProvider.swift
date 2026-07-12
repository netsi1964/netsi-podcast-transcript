import Foundation
import NaturalLanguage

/// Which backend produces embeddings for semantic search.
enum EmbeddingChoice: String, CaseIterable, Identifiable, Sendable {
    case apple      // on-device, no setup
    case openAI
    case ollama
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .apple: return "Apple (på enheden)"
        case .openAI: return "OpenAI"
        case .ollama: return "Ollama (lokal)"
        }
    }
}

/// Produces vector embeddings for a batch of texts, for semantic (vector) search
/// (PRD-SEC-010: embeddings-baseret semantisk søgning).
protocol EmbeddingProvider: Sendable {
    func embed(_ texts: [String]) async throws -> [[Float]]
}

enum EmbeddingError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let m): return "Semantisk søgning er ikke tilgængelig: \(m)" }
    }
}

/// On-device sentence embeddings via Apple's NaturalLanguage framework — no network, no key.
struct AppleEmbeddingProvider: EmbeddingProvider {
    func embed(_ texts: [String]) async throws -> [[Float]] {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .danish)
                ?? NLEmbedding.sentenceEmbedding(for: .english) else {
            throw EmbeddingError.unavailable("ingen on-device sætnings-model på denne macOS")
        }
        let dimension = embedding.dimension
        return texts.map { text in
            if let vector = embedding.vector(for: text) { return vector.map(Float.init) }
            // Out-of-vocabulary / too long: average word vectors as a fallback.
            var sum = [Double](repeating: 0, count: dimension)
            var count = 0
            for word in text.split(separator: " ").prefix(60) {
                if let v = embedding.vector(for: String(word)) {
                    for i in 0..<dimension { sum[i] += v[i] }
                    count += 1
                }
            }
            guard count > 0 else { return [Float](repeating: 0, count: dimension) }
            return sum.map { Float($0 / Double(count)) }
        }
    }
}

/// OpenAI-compatible `/embeddings` endpoint.
struct OpenAIEmbeddingProvider: EmbeddingProvider {
    let baseURL: String
    let apiKey: String
    let model: String

    func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !apiKey.isEmpty else { throw EmbeddingError.unavailable("mangler OpenAI API key") }
        guard let url = URL(string: baseURL.trimmingTrailingSlash + "/embeddings") else {
            throw EmbeddingError.unavailable("ugyldig base-URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "input": texts])

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw EmbeddingError.unavailable("HTTP \(http.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            throw EmbeddingError.unavailable("uventet svarformat")
        }
        return items.compactMap { ($0["embedding"] as? [Double])?.map(Float.init) }
    }
}

/// Local Ollama `/api/embed` endpoint (batch input).
struct OllamaEmbeddingProvider: EmbeddingProvider {
    let baseURL: String
    let model: String

    func embed(_ texts: [String]) async throws -> [[Float]] {
        guard let url = URL(string: baseURL.trimmingTrailingSlash + "/api/embed") else {
            throw EmbeddingError.unavailable("ugyldig base-URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "input": texts])

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw EmbeddingError.unavailable("HTTP \(http.statusCode) — er modellen '\(model)' hentet?")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vectors = json["embeddings"] as? [[Double]] else {
            throw EmbeddingError.unavailable("uventet svarformat")
        }
        return vectors.map { $0.map(Float.init) }
    }
}
