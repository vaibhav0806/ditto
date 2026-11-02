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
