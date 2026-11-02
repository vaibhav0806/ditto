import Foundation
import CSQLite

public struct HistoryError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

public final class HistoryStore {
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(url: URL) throws {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open history"
            sqlite3_close(db)
            db = nil
            throw HistoryError(message: message)
        }
        sqlite3_busy_timeout(db, 500)
        try execute("""
            CREATE TABLE IF NOT EXISTS clips (
                id TEXT PRIMARY KEY,
                text TEXT NOT NULL UNIQUE,
                copied_at REAL NOT NULL,
                source TEXT NOT NULL,
                bundle_id TEXT NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0
            )
            """)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    deinit { sqlite3_close(db) }

    public func entries() throws -> [ClipboardEntry] {
        let stmt = try prepare("SELECT id, text, copied_at, source, bundle_id, pinned FROM clips ORDER BY copied_at DESC, id")
        defer { sqlite3_finalize(stmt) }
        var entries: [ClipboardEntry] = []
        while true {
            let result = sqlite3_step(stmt)
            if result == SQLITE_DONE { return entries }
            guard result == SQLITE_ROW else { throw error() }
            entries.append(ClipboardEntry(
                id: column(stmt, 0), text: column(stmt, 1),
                copiedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                source: column(stmt, 3), sourceBundleID: column(stmt, 4),
                pinned: sqlite3_column_int(stmt, 5) != 0
            ))
        }
    }

    public func capture(text: String, source: String = "Unknown", bundleID: String = "", at: Date = Date()) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !text.contains("\0"), text.utf8.count <= 1_048_576 else { return }
        let stmt = try prepare("""
            INSERT INTO clips (id, text, copied_at, source, bundle_id) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(text) DO UPDATE SET copied_at=excluded.copied_at, source=excluded.source, bundle_id=excluded.bundle_id
            """)
        defer { sqlite3_finalize(stmt) }
        bind(UUID().uuidString, to: stmt, at: 1)
        bind(text, to: stmt, at: 2)
        sqlite3_bind_double(stmt, 3, at.timeIntervalSince1970)
        bind(source, to: stmt, at: 4)
        bind(bundleID, to: stmt, at: 5)
        try finish(stmt)
    }

    public func setPinned(id: String, pinned: Bool) throws {
        let stmt = try prepare("UPDATE clips SET pinned=? WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, pinned ? 1 : 0)
        bind(id, to: stmt, at: 2)
        try finish(stmt)
    }

    public func delete(id: String) throws {
        let stmt = try prepare("DELETE FROM clips WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        bind(id, to: stmt, at: 1)
        try finish(stmt)
    }

    public func clear() throws { try execute("DELETE FROM clips") }

    public func prune(retentionDays: Int, maxItems: Int = 500, now: Date = Date()) throws {
        let stmt = try prepare("DELETE FROM clips WHERE pinned=0 AND copied_at < ?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, now.addingTimeInterval(-Double(max(1, retentionDays)) * 86_400).timeIntervalSince1970)
        try finish(stmt)
        let cap = try prepare("DELETE FROM clips WHERE pinned=0 AND id NOT IN (SELECT id FROM clips WHERE pinned=0 ORDER BY copied_at DESC, id LIMIT ?)")
        defer { sqlite3_finalize(cap) }
        sqlite3_bind_int(cap, 1, Int32(clamping: max(0, maxItems)))
        try finish(cap)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw error() }
        return stmt
    }

    private func execute(_ sql: String) throws {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try finish(stmt)
    }

    private func finish(_ stmt: OpaquePointer) throws {
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }

    private func bind(_ text: String, to stmt: OpaquePointer, at index: Int32) {
        _ = text.withCString { sqlite3_bind_text(stmt, index, $0, -1, transient) }
    }

    private func column(_ stmt: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: value)
    }

    private func error() -> HistoryError { HistoryError(message: String(cString: sqlite3_errmsg(db))) }
}
