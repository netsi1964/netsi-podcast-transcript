import Foundation

/// Talks to any OpenAI-compatible `/chat/completions` endpoint (OpenAI, Azure, OpenRouter,
/// local gateways, etc.) — PRD-FEAT-008.2.
struct OpenAICompatibleProvider: LLMProvider {
    let providerType: ProviderType = .openAICompatible
    let baseURL: String
    let apiKey: String

    func isAvailable() async -> Bool { !apiKey.isEmpty }

    /// Lists models via the `/models` endpoint (PRD-FEAT-008.2). Chat-capable ids are hard to
    /// tell apart generically, so we return them all, sorted, for the user to choose from.
    func listModels() async -> [String] {
        guard !apiKey.isEmpty, let url = URL(string: baseURL.trimmingTrailingSlash + "/models") else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["id"] as? String }.sorted()
    }

    func complete(messages: [LLMMessage], model: String) async throws -> String {
        guard !apiKey.isEmpty else { throw LLMError.notConfigured("mangler API key") }
        guard let url = URL(string: baseURL.trimmingTrailingSlash + "/chat/completions") else {
            throw LLMError.notConfigured("ugyldig base-URL")
        }

        let payload: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw LLMError.decoding("uventet svarformat")
        }
        return content
    }

    /// Streams `/chat/completions` with `stream: true` using Server-Sent Events. Each `data:`
    /// line carries a chunk whose `choices[0].delta.content` is an incremental text delta.
    func streamComplete(messages: [LLMMessage], model: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !apiKey.isEmpty else { throw LLMError.notConfigured("mangler API key") }
                    guard let url = URL(string: baseURL.trimmingTrailingSlash + "/chat/completions") else {
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
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw LLMError.http(http.statusCode, "")
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payloadText = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payloadText == "[DONE]" { break }
                        guard let data = payloadText.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String, !content.isEmpty
                        else { continue }
                        continuation.yield(content)
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

extension String {
    var trimmingTrailingSlash: String {
        hasSuffix("/") ? String(dropLast()) : self
    }
}
