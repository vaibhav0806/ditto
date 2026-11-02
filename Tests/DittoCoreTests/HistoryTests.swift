import Foundation
import DittoCore

final class HistoryTests {
    func withStore(_ body: (HistoryStore, URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.sqlite")
        try body(HistoryStore(url: url), url)
    }

    func testPersistsUnicodeAndSQLCharactersAcrossReopen() throws {
        try withStore { store, url in
            try store.capture(text: "👋 café ' ; DROP TABLE clips; --", source: "Notes", bundleID: "test.notes", at: Date(timeIntervalSince1970: 100))
            let reopened = try HistoryStore(url: url)
            let item = try unwrap(reopened.entries().first)
            expectEqual(item.text, "👋 café ' ; DROP TABLE clips; --")
            expectEqual(item.source, "Notes")
            expectEqual(item.sourceBundleID, "test.notes")
        }
    }

    func testRecopyPromotesWithoutDuplicatingOrLosingPin() throws {
        try withStore { store, _ in
            try store.capture(text: "one", source: "A", at: Date(timeIntervalSince1970: 100))
            let id = try unwrap(store.entries().first).id
            try store.setPinned(id: id, pinned: true)
            try store.capture(text: "two", at: Date(timeIntervalSince1970: 200))
            try store.capture(text: "one", source: "B", at: Date(timeIntervalSince1970: 300))
            let entries = try store.entries()
            expectEqual(entries.map(\.text), ["one", "two"])
            expectEqual(entries[0].id, id)
            expectTrue(entries[0].pinned)
            expectEqual(entries[0].source, "B")
        }
    }

    func testRetentionPreservesPinnedAndDeleteAndClearAreDurable() throws {
        try withStore { store, url in
            try store.capture(text: "old", at: Date(timeIntervalSince1970: 1))
            try store.capture(text: "keep", at: Date(timeIntervalSince1970: 2))
            let pinnedID = try unwrap(store.entries().first).id
            try store.setPinned(id: pinnedID, pinned: true)
            try store.capture(text: "recent", at: Date(timeIntervalSince1970: 1_000_000))
            try store.prune(retentionDays: 7, now: Date(timeIntervalSince1970: 1_000_001))
            expectEqual(try store.entries().map(\.text), ["recent", "keep"])
            try store.delete(id: pinnedID)
            expectEqual(try store.entries().map(\.text), ["recent"])
            try store.clear()
            expectEqual(try HistoryStore(url: url).entries().count, 0)
        }
    }

    func testRejectsEmptyAndOversizeAndNullTextAndBoundsUnpinnedHistory() throws {
        try withStore { store, _ in
            try store.capture(text: " \n ")
            try store.capture(text: "bad\0text")
            try store.capture(text: String(repeating: "x", count: 1_048_577))
            expectEqual(try store.entries().count, 0)
            for n in 0..<5 { try store.capture(text: "item \(n)", at: Date(timeIntervalSince1970: Double(n))) }
            try store.prune(retentionDays: 7, maxItems: 2, now: Date(timeIntervalSince1970: 10))
            expectEqual(try store.entries().map(\.text), ["item 4", "item 3"])
        }
    }
}
