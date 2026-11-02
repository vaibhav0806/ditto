import Foundation
import DittoCore

final class CompletionTests {
    func testEventQueryTracksTypingWithoutAnAccessibilityDocument() {
        var session = CompletionSession()
        expectTrue(session.isKeystrokeTracked)
        expectTrue(session.recordTypedText("di"))
        expectTrue(session.recordTypedText("t"))
        expectEqual(session.query, "dit")
        expectTrue(session.recordBackspace())
        expectEqual(session.query, "di")
        expectEqual(session.insertionSuffix(for: "ditto"), "tto")
        expectFalse(session.validates(text: "di", selection: NSRange(location: 2, length: 0)))
    }

    func testEventQueryCannotDeleteBeforeInvocationOrAcceptNonPrefixReplacement() {
        var session = CompletionSession()
        expectFalse(session.recordBackspace())
        expectTrue(session.recordTypedText("dit"))
        expectNil(session.insertionSuffix(for: "DITTO"))
        expectNil(session.insertionSuffix(for: "a ditto"))
        expectNil(session.insertionSuffix(for: "ditto\ncommand"))
        expectNil(session.insertionSuffix(for: "ditto\tother"))
        expectNil(session.insertionSuffix(for: "dit" + String(repeating: "x", count: 4096)))
        expectNil(session.insertionSuffix(for: "dit\u{001B}[31m"))
        expectFalse(session.recordTypedText(""))
        expectFalse(session.recordTypedText("\n"))
        expectFalse(session.recordTypedText(String(repeating: "x", count: 513)))
        expectEqual(session.query, "dit")
    }

    func testEventQueryPreservesUnicodeBoundariesAndHandlesNoOpAcceptance() {
        var session = CompletionSession()
        expectTrue(session.recordTypedText("👩🏽‍💻"))
        expectEqual(session.insertionSuffix(for: "👩🏽‍💻 hello"), " hello")
        expectTrue(session.recordBackspace())
        expectEqual(session.query, "")
        expectTrue(session.recordTypedText("e"))
        expectNil(session.insertionSuffix(for: "e\u{301}clair"))
        expectTrue(session.recordBackspace())
        expectTrue(session.recordTypedText("done"))
        expectEqual(session.insertionSuffix(for: "done"), "")
    }

    func testPrefixOutranksNewerSubstringAndRecencyBreaksTies() {
        let entries = [
            ClipboardEntry(id: "a", text: "a local service", copiedAt: Date(timeIntervalSince1970: 30)),
            ClipboardEntry(id: "b", text: "local old", copiedAt: Date(timeIntervalSince1970: 10)),
            ClipboardEntry(id: "c", text: "LOCAL new", copiedAt: Date(timeIntervalSince1970: 20)),
            ClipboardEntry(id: "d", text: "irrelevant")
        ]
        expectEqual(CompletionMatcher.matches(entries, query: "local").map(\.id), ["c", "b", "a"])
        expectEqual(CompletionMatcher.matches(entries, query: "missing"), [])
    }

    func testEmptyQueryUsesRecencyRatherThanPinStatus() {
        let entries = [ClipboardEntry(id: "old", text: "old", copiedAt: .distantPast, pinned: true), ClipboardEntry(id: "new", text: "new")]
        expectEqual(CompletionMatcher.matches(entries, query: "").map(\.id), ["new", "old"])
    }

    func testSessionReplacesOnlyNewQueryAndUnderstandsUTF16Ranges() throws {
        var session = try unwrap(CompletionSession(text: "Hi 👋, end", selection: NSRange(location: 7, length: 0)))
        expectTrue(session.observe(text: "Hi 👋, café🌙end", selection: NSRange(location: 13, length: 0)))
        expectEqual(session.query, "café🌙")
        expectEqual(session.replacementRange, NSRange(location: 7, length: 6))
        expectTrue(session.validates(text: "Hi 👋, café🌙end", selection: NSRange(location: 13, length: 0)))
        expectFalse(session.validates(text: "Hi 👋, otherend", selection: NSRange(location: 12, length: 0)))
    }

    func testBackspaceWithinQueryIsAllowedButMovingCaretOrEditingEarlierTextCancels() throws {
        var session = try unwrap(CompletionSession(text: "Before ", selection: NSRange(location: 7, length: 0)))
        expectTrue(session.observe(text: "Before local", selection: NSRange(location: 12, length: 0)))
        expectTrue(session.observe(text: "Before loc", selection: NSRange(location: 10, length: 0)))
        expectEqual(session.query, "loc")
        expectFalse(session.observe(text: "Before loc", selection: NSRange(location: 9, length: 0)))
        expectFalse(session.observe(text: "Changed loc", selection: NSRange(location: 11, length: 0)))
        expectFalse(session.observe(text: "Before", selection: NSRange(location: 6, length: 0)))
    }

    func testNormalizationChangesOutsideQueryAreRejected() throws {
        var session = try unwrap(CompletionSession(text: "é ", selection: NSRange(location: 2, length: 0)))
        expectFalse(session.observe(text: "e\u{301} loc", selection: NSRange(location: 6, length: 0)))
        expectTrue(session.observe(text: "é loc", selection: NSRange(location: 5, length: 0)))
        var querySession = try unwrap(CompletionSession(text: "", selection: NSRange(location: 0, length: 0)))
        expectTrue(querySession.observe(text: "é", selection: NSRange(location: 1, length: 0)))
        expectFalse(querySession.validates(text: "e\u{301}", selection: NSRange(location: 2, length: 0)))
    }

    func testPreexistingSelectionsAndInvalidRangesAreRejected() {
        expectNil(CompletionSession(text: "text", selection: NSRange(location: 0, length: 4)))
        expectNil(CompletionSession(text: "text", selection: NSRange(location: 9, length: 0)))
        expectNil(CompletionSession(text: "👋", selection: NSRange(location: 1, length: 0)))
    }
}
