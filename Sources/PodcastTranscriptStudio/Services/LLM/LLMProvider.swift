import Foundation

/// A provider-agnostic chat message passed to any LLM backend.
struct LLMMessage: Sendable {
    enum Role: String, Sendable { case system, user, assistant }
    var role: Role
    var content: String
}

enum LLMError: LocalizedError {
    case notConfigured(String)
    case unavailable(String)
    case http(Int, String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let m): return "Provideren er ikke konfigureret: \(m)"
        case .unavailable(let m): return "Provideren er ikke tilgængelig: \(m)"
        case .http(let code, let m): return "Fejl fra provider (HTTP \(code)): \(m)"
        case .decoding(let m): return "Kunne ikke læse svaret: \(m)"
        case .transport(let m): return "Netværksfejl: \(m)"
        }
    }
}

/// The behaviour every LLM backend implements (PRD-FEAT-008.1 provider protocol).
protocol LLMProvider: Sendable {
    var providerType: ProviderType { get }
    /// Whether this backend can currently run (e.g. Apple Intelligence availability, key present).
    func isAvailable() async -> Bool
    /// Lists model identifiers this backend currently offers, for the model picker. Returns an
    /// empty array if the backend can't be queried (the UI then falls back to manual entry).
    func listModels() async -> [String]
    /// Runs a single completion over the message list and returns assistant text.
    func complete(messages: [LLMMessage], model: String) async throws -> String
    /// Streams the completion as incremental text deltas. Cancelling the consuming task stops
    /// generation (PRD-FEAT-009/011 streaming + stop).
    func streamComplete(messages: [LLMMessage], model: String) -> AsyncThrowingStream<String, Error>
}

extension LLMProvider {
    func listModels() async -> [String] { [] }

    /// Default streaming: emit the full completion as a single chunk. Providers that support
    /// true token streaming override this.
    func streamComplete(messages: [LLMMessage], model: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let text = try await complete(messages: messages, model: model)
                    continuation.yield(text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Builds a concrete `LLMProvider` from a stored `LLMProviderConfig`, resolving the API key
/// from Keychain when needed. This is the one place that maps config → live provider.
enum LLMProviderFactory {
    static func make(from config: LLMProviderConfig) -> LLMProvider {
        switch config.providerType {
        case .openAICompatible:
            let key = config.apiKeyKeychainRef.flatMap(Keychain.get) ?? ""
            return OpenAICompatibleProvider(
                baseURL: config.baseURL ?? "https://api.openai.com/v1",
                apiKey: key
            )
        case .ollama:
            return OllamaProvider(baseURL: config.baseURL ?? "http://localhost:11434")
        case .appleFoundationModels:
            return AppleFoundationModelsProvider()
        }
    }
}
