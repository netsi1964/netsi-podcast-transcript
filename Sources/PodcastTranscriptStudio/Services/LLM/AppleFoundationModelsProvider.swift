import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Uses on-device Apple Intelligence via the Foundation Models framework, when the OS and
/// hardware support it (PRD-FEAT-008.4). Compiles to a graceful "unavailable" stub on systems
/// where the framework is absent, so the app still builds and runs everywhere.
struct AppleFoundationModelsProvider: LLMProvider {
    let providerType: ProviderType = .appleFoundationModels

    func isAvailable() async -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        return false
        #else
        return false
        #endif
    }

    func listModels() async -> [String] {
        await isAvailable() ? ["system"] : []
    }

    func complete(messages: [LLMMessage], model: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.availability == .available else {
                throw LLMError.unavailable("Apple Intelligence er ikke aktiveret på denne Mac")
            }
            let instructions = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n")
            let conversation = messages.filter { $0.role != .system }
                .map { "\($0.role == .user ? "Bruger" : "Assistent"): \($0.content)" }
                .joined(separator: "\n")
            let session = LanguageModelSession(instructions: instructions.isEmpty ? nil : instructions)
            do {
                let response = try await session.respond(to: conversation)
                return response.content
            } catch let error as LanguageModelSession.GenerationError {
                throw LLMError.unavailable(Self.describe(error))
            }
        }
        throw LLMError.unavailable("kræver macOS 26 eller nyere")
        #else
        throw LLMError.unavailable("Foundation Models er ikke tilgængeligt i dette build")
        #endif
    }

    #if canImport(FoundationModels)
    /// Turns Foundation Models' errors into a clear Danish message. The on-device safety
    /// guardrail ("detected content likely to be unsafe") is the common one on real transcripts:
    /// the model refuses rather than answering, so we explain it and suggest another provider.
    @available(macOS 26.0, *)
    private static func describe(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .guardrailViolation:
            return "Apple Intelligence blokerede indholdet af sikkerhedshensyn "
                + "(\"detected content likely to be unsafe\") og svarede ikke. "
                + "Transskriptioner udløser ofte denne filtrering. Prøv en anden provider "
                + "(fx OpenAI eller Ollama) for dette indhold."
        case .exceededContextWindowSize:
            return "Teksten er for lang til Apple Intelligences kontekstvindue. "
                + "Prøv en kortere episode eller en anden provider."
        case .unsupportedLanguageOrLocale:
            return "Apple Intelligence understøtter ikke sproget for dette indhold."
        default:
            return "Apple Intelligence-fejl: \(error.localizedDescription)"
        }
    }
    #endif
}
