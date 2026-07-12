import Foundation
import SQLite3

/// SQLITE_TRANSIENT tells SQLite to copy bound bytes; the default (STATIC) assumes the
/// buffer outlives the call, which is unsafe for Swift `String`/`Data` temporaries.
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DatabaseError: LocalizedError {
    case open(String)
    case prepare(String)
    case step(String)

    var errorDescription: String? {
        switch self {
        case .open(let m): return "Kunne ikke åbne databasen: \(m)"
        case .prepare(let m): return "SQL-forberedelse fejlede: \(m)"
        case .step(let m): return "SQL-kørsel fejlede: \(m)"
        }
    }
}

/// Thin serial wrapper around a single SQLite connection. Not thread-safe by itself; the
/// app funnels all access through `Store`, which owns one `Database` on a serial queue.
final class Database {
    private var handle: OpaquePointer?

    init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw DatabaseError.open(msg)
        }
        handle = db
        try exec("PRAGMA journal_mode = WAL;")
        try exec("PRAGMA foreign_keys = ON;")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    private var lastError: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no connection"
    }

    /// Runs one or more statements with no bindings and no result rows.
    func exec(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.step(lastError)
        }
    }

    /// Prepares `sql`, binds `params` positionally, runs it, and discards any rows.
    func run(_ sql: String, _ params: [SQLValue] = []) throws {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw DatabaseError.step(lastError)
        }
    }

    /// Prepares + runs `sql`, mapping each result row through `map`.
    func query<T>(_ sql: String, _ params: [SQLValue] = [], map: (Row) -> T) throws -> [T] {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        var results: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                results.append(map(Row(stmt: stmt)))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw DatabaseError.step(lastError)
            }
        }
        return results
    }

    /// Runs `body` inside a transaction, rolling back on any thrown error.
    func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE;")
        do {
            try body()
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    private func prepare(_ sql: String, _ params: [SQLValue]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepare("\(lastError) — in: \(sql)")
        }
        for (index, value) in params.enumerated() {
            value.bind(to: stmt, at: Int32(index + 1))
        }
        return stmt
    }
}

/// A typed SQLite value for positional binding.
enum SQLValue {
    case text(String)
    case int(Int)
    case double(Double)
    case null

    func bind(to stmt: OpaquePointer?, at index: Int32) {
        switch self {
        case .text(let s): sqlite3_bind_text(stmt, index, s, -1, SQLITE_TRANSIENT)
        case .int(let i): sqlite3_bind_int64(stmt, index, Int64(i))
        case .double(let d): sqlite3_bind_double(stmt, index, d)
        case .null: sqlite3_bind_null(stmt, index)
        }
    }
}

/// Read-only accessor over a single result row of a live statement.
struct Row {
    let stmt: OpaquePointer?

    func string(_ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }

    func requireString(_ index: Int32) -> String { string(index) ?? "" }

    func int(_ index: Int32) -> Int? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, index))
    }

    func bool(_ index: Int32) -> Bool { (int(index) ?? 0) != 0 }
}
