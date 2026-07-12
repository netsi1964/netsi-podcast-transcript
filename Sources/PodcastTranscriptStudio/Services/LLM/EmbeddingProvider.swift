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

/// Whether a text is a search query or a stored document — some models (e.g. nomic-embed-text)
/// need different task prefixes for each to produce comparable vectors.
enum EmbeddingRole: Sendable { case query, document }

/// Produces vector embeddings for a batch of texts, for semantic (vector) search
/// (PRD-SEC-010: embeddings-baseret semantisk søgning).
protocol EmbeddingProvider: Sendable {
    func embed(_ texts: [String], role: EmbeddingRole) async throws -> [[Float]]
}

enum EmbeddingError: LocalizedError {
    case unavailable(String)
    /// The endpoint/operation isn't available on this server (retry a legacy endpoint).
    case endpointUnavailable
    /// The chosen model exists but can't produce embeddings (e.g. a chat/vision model).
    case modelCantEmbed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let m):
            return "Semantisk søgning er ikke tilgængelig: \(m)"
        case .endpointUnavailable:
            return "Semantisk søgning er ikke tilgængelig: endpoint mangler."
        case .modelCantEmbed(let model):
            return "Modellen '\(model)' understøtter ikke embeddings. "
                + "Semantisk søgning kræver en embedding-model. Installer fx en af disse i Ollama:\n"
                + "  ollama pull nomic-embed-text\n"
                + "  ollama pull mxbai-embed-large\n"
                + "…og vælg den i model-listen. (Eller brug Apple på enheden, som ikke kræver noget.)"
        }
    }
}

/// On-device sentence embeddings via Apple's NaturalLanguage framework — no network, no key.
struct AppleEmbeddingProvider: EmbeddingProvider {
    func embed(_ texts: [String], role: EmbeddingRole) async throws -> [[Float]] {
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

    func embed(_ texts: [String], role: EmbeddingRole) async throws -> [[Float]] {
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

/// Local Ollama embeddings. Requires an embedding-capable model (e.g. nomic-embed-text) — chat
/// models return 500/501. Tries the modern `/api/embed` (batch) endpoint, then falls back to the
/// legacy per-text `/api/embeddings` endpoint for older Ollama versions.
struct OllamaEmbeddingProvider: EmbeddingProvider {
    let baseURL: String
    let model: String

    func embed(_ texts: [String], role: EmbeddingRole) async throws -> [[Float]] {
        let prepared = texts.map { prefixed($0, role: role) }
        do {
            return try await embedBatch(prepared)
        } catch let error as EmbeddingError {
            // If the batch endpoint or op isn't available, try the legacy endpoint before failing.
            if case .endpointUnavailable = error {
                return try await embedLegacy(prepared)
            }
            throw error
        }
    }

    /// nomic-embed-text was trained with task prefixes; adding them sharply improves relevance so
    /// unrelated queries score low. Other models are passed through unchanged.
    private func prefixed(_ text: String, role: EmbeddingRole) -> String {
        guard model.lowercased().contains("nomic") else { return text }
        return (role == .query ? "search_query: " : "search_document: ") + text
    }

    /// Modern `/api/embed` with a batch `input`.
    private func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        guard let url = URL(string: baseURL.trimmingTrailingSlash + "/api/embed") else {
            throw EmbeddingError.unavailable("ugyldig base-URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "input": texts])

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // 404 on the batch endpoint may mean an old Ollama without it — retry the legacy one.
            if http.statusCode == 404 { throw EmbeddingError.endpointUnavailable }
            throw Self.error(forStatus: http.statusCode, model: model)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vectors = json["embeddings"] as? [[Double]] else {
            throw EmbeddingError.unavailable("uventet svarformat")
        }
        return vectors.map { $0.map(Float.init) }
    }

    /// Legacy `/api/embeddings` — one text at a time, field `prompt`.
    private func embedLegacy(_ texts: [String]) async throws -> [[Float]] {
        guard let url = URL(string: baseURL.trimmingTrailingSlash + "/api/embeddings") else {
            throw EmbeddingError.unavailable("ugyldig base-URL")
        }
        var results: [[Float]] = []
        for text in texts {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "prompt": text])
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw Self.error(forStatus: http.statusCode, model: model)
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let vector = json["embedding"] as? [Double] else {
                throw EmbeddingError.unavailable("uventet svarformat")
            }
            results.append(vector.map(Float.init))
        }
        return results
    }

    /// Turns an Ollama HTTP status into a clear, actionable message.
    private static func error(forStatus status: Int, model: String) -> EmbeddingError {
        switch status {
        case 404:
            return .unavailable("modellen '\(model)' er ikke hentet. Kør: ollama pull \(model)")
        case 500, 501:
            // The endpoint exists but the model can't embed (a chat/vision model was chosen).
            return .modelCantEmbed(model)
        default:
            return .unavailable("HTTP \(status)")
        }
    }
}
