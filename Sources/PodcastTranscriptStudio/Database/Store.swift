import Foundation

/// Central data facade. Owns the single `Database` connection and serialises every access
/// through an internal queue, so views/view-models can call it from the main actor safely.
/// All persistence in the app goes through here (PRD-SEC-004 local-first / SQLite).
final class Store {
    private let db: Database
    private let queue = DispatchQueue(label: "app.podcasttranscriptstudio.store")
    /// The on-disk database file, exposed for backup/export (PRD-FEAT-012).
    let databaseURL: URL

    /// Default on-disk location: Application Support/PodcastTranscriptStudio/library.sqlite
    static func defaultDatabaseURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let dir = base.appendingPathComponent("PodcastTranscriptStudio", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.sqlite")
    }

    init(url: URL) throws {
        self.databaseURL = url
        db = try Database(path: url.path)
        try Schema.migrate(db)
    }

    /// Designated init taking a raw sqlite path so `:memory:` is passed literally (not resolved
    /// to a real file by `URL(fileURLWithPath:)`).
    private init(rawPath: String, databaseURL: URL) throws {
        self.databaseURL = databaseURL
        db = try Database(path: rawPath)
        try Schema.migrate(db)
    }

    /// Private in-memory store for tests. Each call is an isolated database.
    static func inMemory() throws -> Store {
        try Store(rawPath: ":memory:", databaseURL: URL(fileURLWithPath: "/dev/null"))
    }

    private func sync<T>(_ body: (Database) throws -> T) rethrows -> T {
        try queue.sync { try body(db) }
    }

    // MARK: - Podcast

    /// Finds a podcast by Apple id, else by title, so the same series isn't duplicated on import.
    func upsertPodcast(_ podcast: Podcast) throws -> Podcast {
        try sync { db in
            var existingID: String?
            if let appleID = podcast.applePodcastID {
                existingID = try db.query(
                    "SELECT id FROM podcast WHERE apple_podcast_id = ?;", [.text(appleID)]
                ) { $0.requireString(0) }.first
            }
            if existingID == nil {
                existingID = try db.query(
                    "SELECT id FROM podcast WHERE title = ? AND apple_podcast_id IS NULL;", [.text(podcast.title)]
                ) { $0.requireString(0) }.first
            }
            var p = podcast
            if let existingID {
                p.id = existingID
                p.updatedAt = .now
                try db.run(
                    """
                    UPDATE podcast SET apple_podcast_id=?, title=?, publisher=?, apple_url=?,
                        artwork_url=?, subscribed_locally=?, updated_at=? WHERE id=?;
                    """,
                    [.opt(p.applePodcastID), .text(p.title), .opt(p.publisher), .opt(p.appleURL),
                     .opt(p.artworkURL), .bool(p.subscribedLocally), SQLDate.value(p.updatedAt), .text(p.id)]
                )
            } else {
                try db.run(
                    """
                    INSERT INTO podcast (id, apple_podcast_id, title, publisher, apple_url,
                        artwork_url, subscribed_locally, created_at, updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?);
                    """,
                    [.text(p.id), .opt(p.applePodcastID), .text(p.title), .opt(p.publisher),
                     .opt(p.appleURL), .opt(p.artworkURL), .bool(p.subscribedLocally),
                     SQLDate.value(p.createdAt), SQLDate.value(p.updatedAt)]
                )
            }
            return p
        }
    }

    func podcast(id: String) throws -> Podcast? {
        try sync { db in
            try db.query("SELECT * FROM podcast WHERE id=?;", [.text(id)], map: Store.decodePodcast).first
        }
    }

    // MARK: - Episode

    /// Inserts or updates by Apple episode id (dedupe key, PRD-SEC-009).
    func upsertEpisode(_ episode: Episode) throws -> Episode {
        try sync { db in
            var existingID: String?
            if let appleID = episode.appleEpisodeID {
                existingID = try db.query(
                    "SELECT id FROM episode WHERE apple_episode_id = ?;", [.text(appleID)]
                ) { $0.requireString(0) }.first
            }
            var e = episode
            e.updatedAt = .now
            if let existingID {
                e.id = existingID
                try db.run(
                    """
                    UPDATE episode SET podcast_id=?, apple_episode_id=?, title=?, description_md=?,
                        published_at=?, duration_seconds=?, apple_url=?, artwork_url=?,
                        transcript_status=?, transcript_last_loaded_at=?, transcript_last_attempted_at=?,
                        transcript_error=?, updated_at=? WHERE id=?;
                    """,
                    Store.episodeUpdateParams(e) + [.text(e.id)]
                )
            } else {
                try db.run(
                    """
                    INSERT INTO episode (id, podcast_id, apple_episode_id, title, description_md,
                        published_at, duration_seconds, apple_url, artwork_url, transcript_status,
                        transcript_last_loaded_at, transcript_last_attempted_at, transcript_error,
                        updated_at, created_at)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
                    """,
                    // Column order matches: id, <updateParams ending in updated_at>, created_at.
                    [.text(e.id)] + Store.episodeUpdateParams(e) + [SQLDate.value(e.createdAt)]
                )
            }
            return e
        }
    }

    private static func episodeUpdateParams(_ e: Episode) -> [SQLValue] {
        [.text(e.podcastID), .opt(e.appleEpisodeID), .text(e.title), .opt(e.descriptionMarkdown),
         SQLDate.value(e.publishedAt), .opt(e.durationSeconds), .text(e.appleURL), .opt(e.artworkURL),
         .text(e.transcriptStatus.rawValue), SQLDate.value(e.transcriptLastLoadedAt),
         SQLDate.value(e.transcriptLastAttemptedAt), .opt(e.transcriptError), SQLDate.value(e.updatedAt)]
    }

    func episode(id: String) throws -> Episode? {
        try sync { db in
            try db.query("SELECT * FROM episode WHERE id=?;", [.text(id)], map: Store.decodeEpisode).first
        }
    }

    /// All episodes, optionally filtered by a free-text query over library fields + FTS.
    func episodes(matching query: String = "") throws -> [Episode] {
        try sync { db in
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                return try db.query(
                    "SELECT * FROM episode ORDER BY datetime(updated_at) DESC;",
                    map: Store.decodeEpisode
                )
            }
            let like = "%\(query)%"
            return try db.query(
                """
                SELECT DISTINCT e.* FROM episode e
                LEFT JOIN podcast p ON p.id = e.podcast_id
                LEFT JOIN search_index s ON s.episode_id = e.id
                WHERE e.title LIKE ? OR p.title LIKE ? OR s.body LIKE ?
                ORDER BY datetime(e.updated_at) DESC;
                """,
                [.text(like), .text(like), .text(like)],
                map: Store.decodeEpisode
            )
        }
    }

    func deleteEpisode(id: String) throws {
        try sync { db in
            try db.transaction {
                try db.run("DELETE FROM search_index WHERE episode_id=?;", [.text(id)])
                try db.run("DELETE FROM episode WHERE id=?;", [.text(id)])
            }
        }
    }

    /// Deletes a podcast and, via ON DELETE CASCADE, all its episodes/transcripts/outputs. Search
    /// rows aren't FK-linked, so they're cleared explicitly first.
    func deletePodcast(id: String) throws {
        try sync { db in
            try db.transaction {
                try db.run("DELETE FROM search_index WHERE episode_id IN (SELECT id FROM episode WHERE podcast_id=?);", [.text(id)])
                try db.run("DELETE FROM podcast WHERE id=?;", [.text(id)])
            }
        }
    }

    func deleteOutput(id: String) throws {
        try sync { db in
            try db.transaction {
                try db.run("DELETE FROM search_index WHERE kind='output' AND ref_id=?;", [.text(id)])
                try db.run("DELETE FROM ai_output WHERE id=?;", [.text(id)])
            }
        }
    }

    /// Relevance-ranked snippets across all transcripts/outputs, used to build archive-chat
    /// context without sending the whole library to the LLM (PRD-FEAT-011.3 / PRD-SEC-009).
    func searchContext(query: String, limit: Int = 6) throws -> [(title: String, body: String)] {
        let cleaned = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
        guard !cleaned.isEmpty else { return [] }
        let match = cleaned.map { "\"\($0)\"" }.joined(separator: " OR ")
        return try sync { db in
            try db.query(
                """
                SELECT title, snippet(search_index, 4, '', '', '…', 20) AS body
                FROM search_index WHERE search_index MATCH ?
                ORDER BY rank LIMIT ?;
                """,
                [.text(match), .int(limit)]
            ) { row in (row.requireString(0), row.requireString(1)) }
        }
    }

    // MARK: - Transcript

    func saveTranscript(_ transcript: Transcript, segments: [TranscriptSegment]) throws {
        try sync { db in
            try db.transaction {
                try db.run("DELETE FROM transcript WHERE episode_id=?;", [.text(transcript.episodeID)])
                try db.run(
                    """
                    INSERT INTO transcript (id, episode_id, source, language_code, markdown,
                        plain_text, raw_payload_json, created_at, updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?);
                    """,
                    [.text(transcript.id), .text(transcript.episodeID), .text(transcript.source),
                     .opt(transcript.languageCode), .text(transcript.markdown), .text(transcript.plainText),
                     .opt(transcript.rawPayloadJSON), SQLDate.value(transcript.createdAt),
                     SQLDate.value(transcript.updatedAt)]
                )
                for seg in segments {
                    try db.run(
                        """
                        INSERT INTO transcript_segment (id, transcript_id, start_ms, end_ms, text, markdown, sequence_index)
                        VALUES (?,?,?,?,?,?,?);
                        """,
                        [.text(seg.id), .text(transcript.id), .opt(seg.startMs), .opt(seg.endMs),
                         .text(seg.text), .text(seg.markdown), .int(seg.sequenceIndex)]
                    )
                }
                // Refresh FTS row for this episode's transcript.
                try db.run("DELETE FROM search_index WHERE kind='transcript' AND episode_id=?;", [.text(transcript.episodeID)])
                let title = try db.query("SELECT title FROM episode WHERE id=?;", [.text(transcript.episodeID)]) { $0.requireString(0) }.first ?? ""
                try db.run(
                    "INSERT INTO search_index (kind, ref_id, episode_id, title, body) VALUES ('transcript',?,?,?,?);",
                    [.text(transcript.id), .text(transcript.episodeID), .text(title), .text(transcript.plainText)]
                )
            }
        }
    }

    func transcript(episodeID: String) throws -> Transcript? {
        try sync { db in
            try db.query("SELECT * FROM transcript WHERE episode_id=?;", [.text(episodeID)], map: Store.decodeTranscript).first
        }
    }

    func segments(transcriptID: String) throws -> [TranscriptSegment] {
        try sync { db in
            try db.query(
                "SELECT * FROM transcript_segment WHERE transcript_id=? ORDER BY sequence_index;",
                [.text(transcriptID)], map: Store.decodeSegment
            )
        }
    }

    // MARK: - AI output

    func saveOutput(_ output: AIOutput) throws {
        try sync { db in
            try db.transaction {
                try db.run(
                    """
                    INSERT INTO ai_output (id, episode_id, prompt_id, prompt_version, provider_type,
                        model, input_scope, input_reference_json, output_markdown, created_at)
                    VALUES (?,?,?,?,?,?,?,?,?,?);
                    """,
                    [.text(output.id), .opt(output.episodeID), .opt(output.promptID), .opt(output.promptVersion),
                     .text(output.providerType.rawValue), .text(output.model), .text(output.inputScope.rawValue),
                     .text(output.inputReferenceJSON), .text(output.outputMarkdown), SQLDate.value(output.createdAt)]
                )
                if let episodeID = output.episodeID {
                    try db.run(
                        "INSERT INTO search_index (kind, ref_id, episode_id, title, body) VALUES ('output',?,?,?,?);",
                        [.text(output.id), .text(episodeID), .text("AI output"), .text(output.outputMarkdown)]
                    )
                }
            }
        }
    }

    func outputs(episodeID: String) throws -> [AIOutput] {
        try sync { db in
            try db.query(
                "SELECT * FROM ai_output WHERE episode_id=? ORDER BY datetime(created_at) DESC;",
                [.text(episodeID)], map: Store.decodeOutput
            )
        }
    }

    // MARK: - Prompts

    func replaceAllPrompts(_ prompts: [Prompt]) throws {
        try sync { db in
            try db.transaction {
                try db.run("DELETE FROM prompt;")
                for p in prompts {
                    try db.run(
                        """
                        INSERT INTO prompt (id, file_path, title, description, version, preferred_provider,
                            preferred_model, output_type, body_markdown, validation_status, validation_message, file_modified_at)
                        VALUES (?,?,?,?,?,?,?,?,?,?,?,?);
                        """,
                        [.text(p.id), .text(p.filePath), .text(p.title), .opt(p.description), .text(p.version),
                         .opt(p.preferredProvider), .opt(p.preferredModel), .opt(p.outputType), .text(p.bodyMarkdown),
                         .text(p.validationStatus.rawValue), .opt(p.validationMessage), SQLDate.value(p.fileModifiedAt)]
                    )
                }
            }
        }
    }

    func allPrompts() throws -> [Prompt] {
        try sync { db in
            try db.query("SELECT * FROM prompt ORDER BY title;", map: Store.decodePrompt)
        }
    }

    // MARK: - Chat

    func saveChatSession(_ session: ChatSession) throws {
        try sync { db in
            try db.run(
                """
                INSERT INTO chat_session (id, scope, episode_id, title, provider_type, model, created_at, updated_at)
                VALUES (?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET title=excluded.title, updated_at=excluded.updated_at;
                """,
                [.text(session.id), .text(session.scope.rawValue), .opt(session.episodeID), .opt(session.title),
                 .text(session.providerType.rawValue), .text(session.model),
                 SQLDate.value(session.createdAt), SQLDate.value(session.updatedAt)]
            )
        }
    }

    func saveChatMessage(_ message: ChatMessage) throws {
        try sync { db in
            try db.run(
                """
                INSERT INTO chat_message (id, chat_session_id, role, content_markdown, provider_type, model, created_at)
                VALUES (?,?,?,?,?,?,?);
                """,
                [.text(message.id), .text(message.chatSessionID), .text(message.role.rawValue),
                 .text(message.contentMarkdown), .opt(message.providerType?.rawValue), .opt(message.model),
                 SQLDate.value(message.createdAt)]
            )
        }
    }

    func messages(sessionID: String) throws -> [ChatMessage] {
        try sync { db in
            try db.query(
                "SELECT * FROM chat_message WHERE chat_session_id=? ORDER BY datetime(created_at);",
                [.text(sessionID)], map: Store.decodeMessage
            )
        }
    }

    // MARK: - Provider configs

    func saveProviderConfig(_ config: LLMProviderConfig) throws {
        try sync { db in
            try db.run(
                """
                INSERT INTO llm_provider_config (id, provider_type, display_name, base_url, default_model,
                    api_key_keychain_ref, is_enabled, created_at, updated_at)
                VALUES (?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET provider_type=excluded.provider_type, display_name=excluded.display_name,
                    base_url=excluded.base_url, default_model=excluded.default_model,
                    api_key_keychain_ref=excluded.api_key_keychain_ref, is_enabled=excluded.is_enabled,
                    updated_at=excluded.updated_at;
                """,
                [.text(config.id), .text(config.providerType.rawValue), .text(config.displayName),
                 .opt(config.baseURL), .opt(config.defaultModel), .opt(config.apiKeyKeychainRef),
                 .bool(config.isEnabled), SQLDate.value(config.createdAt), SQLDate.value(config.updatedAt)]
            )
        }
    }

    func providerConfigs() throws -> [LLMProviderConfig] {
        try sync { db in
            try db.query("SELECT * FROM llm_provider_config ORDER BY display_name;", map: Store.decodeProvider)
        }
    }
}
