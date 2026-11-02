import AppKit
import DittoCore
import DittoCapture

func testRealPasteboardCapture() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = try HistoryStore(url: dir.appendingPathComponent("history.sqlite"))
    let board = NSPasteboard(name: .init("Ditto.Tests.\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    var enabled = true
    let capture = ClipboardCapture(store: store, board: board, enabled: { enabled }, retentionDays: { 7 }, exclusions: { [] }, secureInput: { false }, source: { ("Fixture App", "test.fixture") })
    board.clearContents()
    board.setString("ditto-e2e-one", forType: .string)
    capture.poll()
    expectEqual(try store.entries().map(\.text), ["ditto-e2e-one"])
    expectEqual(try store.entries().first?.source, "Fixture App")
    enabled = false
    board.clearContents()
    board.setString("ditto-paused", forType: .string)
    capture.poll()
    expectEqual(try store.entries().map(\.text), ["ditto-e2e-one"])
    enabled = true
    board.clearContents()
    board.setString("ditto-e2e-two", forType: .string)
    capture.poll()
    expectEqual(try store.entries().map(\.text), ["ditto-e2e-two", "ditto-e2e-one"])
    board.clearContents()
    board.setString("confidential-fixture", forType: .string)
    board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
    capture.poll()
    expectEqual(try store.entries().count, 2)
}

func testCaptureAccessAndInvocationDefaults() {
    expectTrue(InputPolicy.permitsBackgroundRead(access: 0)) // default is not denial
    expectFalse(InputPolicy.permitsBackgroundRead(access: 1)) // ask needs explicit consent
    expectTrue(InputPolicy.permitsBackgroundRead(access: 2))
    expectFalse(InputPolicy.permitsBackgroundRead(access: 3))
    expectTrue(InputPolicy.captureEnabled(saved: nil))
    expectFalse(InputPolicy.captureEnabled(saved: false)) // preserve an explicit pause
    expectEqual(InputPolicy.invocation(explicitHistory: false, canComplete: false), .notice)
    expectEqual(InputPolicy.invocation(explicitHistory: false, canComplete: true), .completion)
    expectEqual(InputPolicy.invocation(explicitHistory: true, canComplete: false), .history)
}

func testPasteboardLeasePreservesNewUserCopiesAndRichTypes() throws {
    let board = NSPasteboard(name: .init("Ditto.Lease.Tests.\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    let rich = Data([1, 2, 3, 4])
    board.clearContents()
    board.setString("original", forType: .string)
    board.setData(rich, forType: .init("test.rich"))
    let lease = try PasteboardLease(board: board)
    lease.write("selected")
    expectEqual(board.string(forType: .string), "selected")
    expectTrue(lease.restoreIfUnchanged())
    expectEqual(board.string(forType: .string), "original")
    expectEqual(board.data(forType: .init("test.rich")), rich)
    let second = try PasteboardLease(board: board)
    second.write("older selection")
    board.clearContents()
    board.setString("new user copy", forType: .string)
    expectFalse(second.restoreIfUnchanged())
    expectEqual(board.string(forType: .string), "new user copy")
}

func testPasteboardChangeBeforeWriteIsNotOverwritten() throws {
    let board = NSPasteboard(name: .init("Ditto.BeforeWrite.Tests.\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    board.clearContents()
    board.setString("original", forType: .string)
    let lease = try PasteboardLease(board: board)
    board.clearContents()
    board.setString("new user copy", forType: .string)
    lease.write("stale selection")
    expectEqual(board.string(forType: .string), "new user copy")
}
