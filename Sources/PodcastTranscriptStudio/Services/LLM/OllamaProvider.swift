import Foundation

/// Talks to a local Ollama server over its HTTP API (`localhost:11434` by default), which
/// typically needs no auth locally (PRD-FEAT-008.3).
struct OllamaProvider: LLMProvider {
    let providerType: ProviderType = .ollama
    let baseURL: String

    /// Probes `/api/tags` to detect whether a local Ollama server is running (PRD-FEAT-008 acceptance).
    func isAvailable() async -> Bool {
        guard let url = URL(string: baseURL.trimmingTrailingSlash + "/api/tags") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Lists locally installed models via `/api/tags` (PRD-FEAT-008.3).
    func listModels() async -> [String] {
        guard let url = URL(string: baseURL.trimmingTrailingSlash + "/api/tags") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }.sorted()
    }

    func complete(messages: [LLMMessage], model: String) async throws -> String {
        guard let url = URL(string: baseURL.trimmingTrailingSlash + "/api/chat") else {
            throw LLMError.notConfigured("ugyldig base-URL")
        }
        let payload: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LLMError.transport(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw LLMError.decoding("uventet svarformat")
        }
        return content
    }

    /// Streams `/api/chat` with `stream: true`. Ollama returns newline-delimited JSON objects,
    /// each carrying an incremental `message.content` delta.
    func streamComplete(messages: [LLMMessage], model: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: baseURL.trimmingTrailingSlash + "/api/chat") else {
                        throw LLMError.notConfigured("ugyldig base-URL")
                    }
                    let payload: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
                    ]
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw LLMError.http(http.statusCode, "")
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        if let message = json["message"] as? [String: Any],
                           let delta = message["content"] as? String, !delta.isEmpty {
                            continuation.yield(delta)
                        }
                        if json["done"] as? Bool == true { break }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
