import Foundation

/// Row → entity decoders. Column order matches `SELECT *` on the tables defined in `Schema`.
extension Store {
    static func decodePodcast(_ r: Row) -> Podcast {
        Podcast(
            id: r.requireString(0),
            applePodcastID: r.string(1),
            title: r.requireString(2),
            publisher: r.string(3),
            appleURL: r.string(4),
            artworkURL: r.string(5),
            subscribedLocally: r.bool(6),
            createdAt: SQLDate.parse(r.string(7)) ?? .now,
            updatedAt: SQLDate.parse(r.string(8)) ?? .now
        )
    }

    static func decodeEpisode(_ r: Row) -> Episode {
        Episode(
            id: r.requireString(0),
            podcastID: r.requireString(1),
            appleEpisodeID: r.string(2),
            title: r.requireString(3),
            descriptionMarkdown: r.string(4),
            publishedAt: SQLDate.parse(r.string(5)),
            durationSeconds: r.int(6),
            appleURL: r.requireString(7),
            artworkURL: r.string(8),
            transcriptStatus: TranscriptStatus(rawValue: r.requireString(9)) ?? .notLoaded,
            transcriptLastLoadedAt: SQLDate.parse(r.string(10)),
            transcriptLastAttemptedAt: SQLDate.parse(r.string(11)),
            transcriptError: r.string(12),
            createdAt: SQLDate.parse(r.string(13)) ?? .now,
            updatedAt: SQLDate.parse(r.string(14)) ?? .now
        )
    }

    static func decodeTranscript(_ r: Row) -> Transcript {
        Transcript(
            id: r.requireString(0),
            episodeID: r.requireString(1),
            source: r.requireString(2),
            languageCode: r.string(3),
            markdown: r.requireString(4),
            plainText: r.requireString(5),
            rawPayloadJSON: r.string(6),
            createdAt: SQLDate.parse(r.string(7)) ?? .now,
            updatedAt: SQLDate.parse(r.string(8)) ?? .now
        )
    }

    static func decodeSegment(_ r: Row) -> TranscriptSegment {
        TranscriptSegment(
            id: r.requireString(0),
            transcriptID: r.requireString(1),
            startMs: r.int(2),
            endMs: r.int(3),
            text: r.requireString(4),
            markdown: r.requireString(5),
            sequenceIndex: r.int(6) ?? 0
        )
    }

    static func decodePrompt(_ r: Row) -> Prompt {
        Prompt(
            id: r.requireString(0),
            filePath: r.requireString(1),
            title: r.requireString(2),
            description: r.string(3),
            version: r.requireString(4),
            preferredProvider: r.string(5),
            preferredModel: r.string(6),
            outputType: r.string(7),
            bodyMarkdown: r.requireString(8),
            validationStatus: PromptValidationStatus(rawValue: r.requireString(9)) ?? .valid,
            validationMessage: r.string(10),
            fileModifiedAt: SQLDate.parse(r.string(11)) ?? .now
        )
    }

    static func decodeProvider(_ r: Row) -> LLMProviderConfig {
        LLMProviderConfig(
            id: r.requireString(0),
            providerType: ProviderType(rawValue: r.requireString(1)) ?? .openAICompatible,
            displayName: r.requireString(2),
            baseURL: r.string(3),
            defaultModel: r.string(4),
            apiKeyKeychainRef: r.string(5),
            isEnabled: r.bool(6),
            createdAt: SQLDate.parse(r.string(7)) ?? .now,
            updatedAt: SQLDate.parse(r.string(8)) ?? .now
        )
    }

    static func decodeOutput(_ r: Row) -> AIOutput {
        AIOutput(
            id: r.requireString(0),
            episodeID: r.string(1),
            promptID: r.string(2),
            promptVersion: r.string(3),
            providerType: ProviderType(rawValue: r.requireString(4)) ?? .openAICompatible,
            model: r.requireString(5),
            inputScope: InputScope(rawValue: r.requireString(6)) ?? .episode,
            inputReferenceJSON: r.requireString(7),
            outputMarkdown: r.requireString(8),
            createdAt: SQLDate.parse(r.string(9)) ?? .now
        )
    }

    static func decodeMessage(_ r: Row) -> ChatMessage {
        ChatMessage(
            id: r.requireString(0),
            chatSessionID: r.requireString(1),
            role: ChatMessage.Role(rawValue: r.requireString(2)) ?? .user,
            contentMarkdown: r.requireString(3),
            providerType: r.string(4).flatMap(ProviderType.init(rawValue:)),
            model: r.string(5),
            createdAt: SQLDate.parse(r.string(6)) ?? .now
        )
    }
}
