import Foundation

// MARK: - Enums

/// Lifecycle of an episode's transcript. Mirrors `Episode.transcript_status` in the PRD.
enum TranscriptStatus: String, Codable, CaseIterable, Sendable {
    case notLoaded = "not_loaded"
    case loaded
    case failed
    case notFound = "not_found"
    case refreshing
    /// Apple has a transcript for this episode, but it hasn't been downloaded to this Mac yet.
    case availableNotDownloaded = "available_not_downloaded"

    /// Human-facing Danish label. Status is always textual, never colour-only (PRD-SEC-006).
    var label: String {
        switch self {
        case .notLoaded: return "Ikke hentet"
        case .loaded: return "Hentet"
        case .failed: return "Fejlet"
        case .notFound: return "Ikke fundet"
        case .refreshing: return "Henter…"
        case .availableNotDownloaded: return "Findes hos Apple"
        }
    }
}

/// The kind of LLM backend behind a provider config (PRD-FEAT-008).
enum ProviderType: String, Codable, CaseIterable, Sendable {
    case openAICompatible = "openai_compatible"
    case ollama
    case appleFoundationModels = "apple_foundation_models"

    var displayName: String {
        switch self {
        case .openAICompatible: return "OpenAI-kompatibel"
        case .ollama: return "Ollama (lokal)"
        case .appleFoundationModels: return "Apple Intelligence"
        }
    }
}

/// Scope an AI run or chat session operates over (PRD-FEAT-009 / PRD-FEAT-011).
enum InputScope: String, Codable, CaseIterable, Sendable {
    case episode
    case archive
    case selection
}

/// Validation state of a prompt file's frontmatter (PRD-FEAT-007).
enum PromptValidationStatus: String, Codable, Sendable {
    case valid
    case warning
    case invalid
}

// MARK: - Entities

struct Podcast: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var applePodcastID: String?
    var title: String
    var publisher: String?
    var appleURL: String?
    var artworkURL: String?
    var subscribedLocally: Bool = false
    var createdAt: Date = .now
    var updatedAt: Date = .now
}

struct Episode: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var podcastID: String
    var appleEpisodeID: String?
    var title: String
    var descriptionMarkdown: String?
    var publishedAt: Date?
    var durationSeconds: Int?
    var appleURL: String
    var artworkURL: String?
    var transcriptStatus: TranscriptStatus = .notLoaded
    var transcriptLastLoadedAt: Date?
    var transcriptLastAttemptedAt: Date?
    var transcriptError: String?
    var createdAt: Date = .now
    var updatedAt: Date = .now
}

struct Transcript: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var episodeID: String
    var source: String = "apple"
    var languageCode: String?
    var markdown: String
    var plainText: String
    var rawPayloadJSON: String?
    var createdAt: Date = .now
    var updatedAt: Date = .now
}

struct TranscriptSegment: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var transcriptID: String
    var startMs: Int?
    var endMs: Int?
    var text: String
    var markdown: String
    var sequenceIndex: Int
}

struct Prompt: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var filePath: String
    var title: String
    var description: String?
    var version: String
    var preferredProvider: String?
    var preferredModel: String?
    var outputType: String?
    var bodyMarkdown: String
    var validationStatus: PromptValidationStatus
    var validationMessage: String?
    var fileModifiedAt: Date
}

struct LLMProviderConfig: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var providerType: ProviderType
    var displayName: String
    var baseURL: String?
    var defaultModel: String?
    var apiKeyKeychainRef: String?
    var isEnabled: Bool = true
    var createdAt: Date = .now
    var updatedAt: Date = .now
}

struct AIOutput: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var episodeID: String?
    var promptID: String?
    var promptVersion: String?
    var providerType: ProviderType
    var model: String
    var inputScope: InputScope
    var inputReferenceJSON: String
    var outputMarkdown: String
    var createdAt: Date = .now
}

struct ChatSession: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var scope: InputScope
    var episodeID: String?
    var title: String?
    var providerType: ProviderType
    var model: String
    var createdAt: Date = .now
    var updatedAt: Date = .now
}

struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    enum Role: String, Codable, Sendable {
        case user, assistant, system
    }
    var id: String = UUID().uuidString
    var chatSessionID: String
    var role: Role
    var contentMarkdown: String
    var providerType: ProviderType?
    var model: String?
    var createdAt: Date = .now
}
