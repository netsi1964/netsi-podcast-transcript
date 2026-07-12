import Foundation

/// Talks to any OpenAI-compatible `/chat/completions` endpoint (OpenAI, Azure, OpenRouter,
/// local gateways, etc.) — PRD-FEAT-008.2.
struct OpenAICompatibleProvider: LLMProvider {
    let providerType: ProviderType = .openAICompatible
    let baseURL: String
    let apiKey: String

    /// A real check: a valid key can list models. Empty result ⇒ missing/invalid key or bad URL.
    func isAvailable() async -> Bool {
        guard !apiKey.isEmpty else { return false }
        return !(await listModels()).isEmpty
    }

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
            throw Self.error(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
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
                        // Read the (JSON) error body from the stream so the message is useful.
                        var body = ""
                        for try await line in bytes.lines { body += line; if body.count > 2000 { break } }
                        throw Self.error(status: http.statusCode, body: body)
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

extension OpenAICompatibleProvider {
    /// Turns an HTTP status + response body into a clear, actionable error. Extracts OpenAI's
    /// `error.message` when present and adds a hint for the common failure codes.
    static func error(status: Int, body: String) -> LLMError {
        var detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = json["error"] as? [String: Any],
           let message = err["message"] as? String {
            detail = message
        }
        let hint: String
        switch status {
        case 401: hint = "API-nøglen er ugyldig eller mangler adgang. Tjek nøglen i Indstillinger."
        case 402: hint = "Betaling kræves — tjek din OpenAI-billing/kredit."
        case 404: hint = "Modellen findes ikke eller din konto har ikke adgang til den. Vælg en anden model."
        case 429: hint = "Rate limit eller kvote opbrugt. Tjek din OpenAI-kvote/billing (platform.openai.com → Usage/Billing), eller prøv igen om lidt."
        case 500, 502, 503: hint = "Provideren har midlertidige problemer. Prøv igen om lidt."
        default: hint = ""
        }
        let combined = [hint, detail.isEmpty ? nil : "Detaljer: \(detail)"].compactMap { $0 }.joined(separator: "\n")
        return .http(status, combined)
    }
}

extension String {
    var trimmingTrailingSlash: String {
        hasSuffix("/") ? String(dropLast()) : self
    }
}
