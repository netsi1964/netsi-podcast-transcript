import Foundation

/// Owns the versioned schema. Bump `migrations` (append-only) to evolve the database;
/// `user_version` tracks how far a given file has been migrated.
enum Schema {
    /// Each entry is applied in order once. Never edit an already-shipped migration —
    /// append a new one instead.
    static let migrations: [String] = [
        // v1 — foundation tables + FTS5 (PRD-SEC-005)
        """
        CREATE TABLE podcast (
            id TEXT PRIMARY KEY,
            apple_podcast_id TEXT,
            title TEXT NOT NULL,
            publisher TEXT,
            apple_url TEXT,
            artwork_url TEXT,
            subscribed_locally INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE episode (
            id TEXT PRIMARY KEY,
            podcast_id TEXT NOT NULL REFERENCES podcast(id) ON DELETE CASCADE,
            apple_episode_id TEXT,
            title TEXT NOT NULL,
            description_md TEXT,
            published_at TEXT,
            duration_seconds INTEGER,
            apple_url TEXT NOT NULL,
            artwork_url TEXT,
            transcript_status TEXT NOT NULL DEFAULT 'not_loaded',
            transcript_last_loaded_at TEXT,
            transcript_last_attempted_at TEXT,
            transcript_error TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX idx_episode_podcast ON episode(podcast_id);
        CREATE UNIQUE INDEX idx_episode_apple ON episode(apple_episode_id) WHERE apple_episode_id IS NOT NULL;

        CREATE TABLE transcript (
            id TEXT PRIMARY KEY,
            episode_id TEXT NOT NULL REFERENCES episode(id) ON DELETE CASCADE,
            source TEXT NOT NULL DEFAULT 'apple',
            language_code TEXT,
            markdown TEXT NOT NULL,
            plain_text TEXT NOT NULL,
            raw_payload_json TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE UNIQUE INDEX idx_transcript_episode ON transcript(episode_id);

        CREATE TABLE transcript_segment (
            id TEXT PRIMARY KEY,
            transcript_id TEXT NOT NULL REFERENCES transcript(id) ON DELETE CASCADE,
            start_ms INTEGER,
            end_ms INTEGER,
            text TEXT NOT NULL,
            markdown TEXT NOT NULL,
            sequence_index INTEGER NOT NULL
        );
        CREATE INDEX idx_segment_transcript ON transcript_segment(transcript_id, sequence_index);

        CREATE TABLE prompt (
            id TEXT PRIMARY KEY,
            file_path TEXT NOT NULL,
            title TEXT NOT NULL,
            description TEXT,
            version TEXT NOT NULL,
            preferred_provider TEXT,
            preferred_model TEXT,
            output_type TEXT,
            body_markdown TEXT NOT NULL,
            validation_status TEXT NOT NULL,
            validation_message TEXT,
            file_modified_at TEXT NOT NULL
        );

        CREATE TABLE llm_provider_config (
            id TEXT PRIMARY KEY,
            provider_type TEXT NOT NULL,
            display_name TEXT NOT NULL,
            base_url TEXT,
            default_model TEXT,
            api_key_keychain_ref TEXT,
            is_enabled INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE ai_output (
            id TEXT PRIMARY KEY,
            episode_id TEXT REFERENCES episode(id) ON DELETE CASCADE,
            prompt_id TEXT,
            prompt_version TEXT,
            provider_type TEXT NOT NULL,
            model TEXT NOT NULL,
            input_scope TEXT NOT NULL,
            input_reference_json TEXT NOT NULL,
            output_markdown TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        CREATE INDEX idx_output_episode ON ai_output(episode_id);

        CREATE TABLE chat_session (
            id TEXT PRIMARY KEY,
            scope TEXT NOT NULL,
            episode_id TEXT REFERENCES episode(id) ON DELETE CASCADE,
            title TEXT,
            provider_type TEXT NOT NULL,
            model TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE chat_message (
            id TEXT PRIMARY KEY,
            chat_session_id TEXT NOT NULL REFERENCES chat_session(id) ON DELETE CASCADE,
            role TEXT NOT NULL,
            content_markdown TEXT NOT NULL,
            provider_type TEXT,
            model TEXT,
            created_at TEXT NOT NULL
        );
        CREATE INDEX idx_message_session ON chat_message(chat_session_id, created_at);

        -- Full-text search across transcripts + AI outputs (PRD-FEAT-001 search, FTS5).
        CREATE VIRTUAL TABLE search_index USING fts5(
            kind UNINDEXED,        -- 'transcript' | 'output'
            ref_id UNINDEXED,      -- source row id
            episode_id UNINDEXED,
            title,
            body
        );
        """
    ]

    static func migrate(_ db: Database) throws {
        let current = try db.query("PRAGMA user_version;") { $0.int(0) ?? 0 }.first ?? 0
        guard current < migrations.count else { return }
        try db.transaction {
            for version in current..<migrations.count {
                try db.exec(migrations[version])
            }
            // PRAGMA can't be parameterised; version is a trusted Int.
            try db.exec("PRAGMA user_version = \(migrations.count);")
        }
    }
}

/// Shared date <-> storage conversion. Dates persist as ISO-8601 text for readability.
enum SQLDate {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }
    static func value(_ date: Date?) -> SQLValue { date.map { .text(string($0)) } ?? .null }

    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        return formatter.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

extension SQLValue {
    /// Convenience for optional strings.
    static func opt(_ s: String?) -> SQLValue { s.map { .text($0) } ?? .null }
    static func opt(_ i: Int?) -> SQLValue { i.map { .int($0) } ?? .null }
    static func bool(_ b: Bool) -> SQLValue { .int(b ? 1 : 0) }
}
