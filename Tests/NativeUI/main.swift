import AppKit
import DittoCore
import DittoUI

var failures: [String] = []
var checks = 0
func check(_ name: String, _ passed: Bool) {
    checks += 1
    if !passed { failures.append(name) }
    print("\(passed ? "PASS" : "FAIL") \(name)")
}
func pump() { RunLoop.current.run(until: Date().addingTimeInterval(0.08)) }
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.finishLaunching()
let previousApp = NSWorkspace.shared.frontmostApplication
let model = OverlayModel()
let now = Date()
var clips = [
    ClipboardEntry(text: "{\n  \"name\": \"ditto\",\n  \"private\": true,\n  \"scripts\": {\n    \"dev\": \"pnpm dev --port 3000\"\n  }\n}", copiedAt: now, source: "Ghostty", sourceBundleID: "com.mitchellh.ghostty"),
    ClipboardEntry(text: "https://github.com/vaibhav0806/ditto", copiedAt: now.addingTimeInterval(-120), source: "Safari", sourceBundleID: "com.apple.Safari", pinned: true),
    ClipboardEntry(text: "Keep the interaction simple. Copy once, find it where you need it, and get back to what you were doing.", copiedAt: now.addingTimeInterval(-300), source: "Notes", sourceBundleID: "com.apple.Notes")
]
for index in 0..<12 { clips.append(ClipboardEntry(text: "Sample clipboard item \(index + 1)", copiedAt: now.addingTimeInterval(Double(-600 - index * 60)), source: "TextEdit", sourceBundleID: "com.apple.TextEdit")) }
model.history = true
model.canInsert = true
model.canReturnToCompletion = true
model.destinationName = "T3 Code"
model.destinationBundleID = "com.t3tools.t3code"
model.entries = clips
var accepted = 0, copied = 0, pinned = 0
var escapedQuery: String?
model.onQuery = { query in
    model.query = query
    model.entries = CompletionMatcher.matches(clips, query: query)
    model.selectedIndex = 0
}
model.onMove = { model.selectedIndex = HistoryPresentation.selectionIndex(current: model.selectedIndex, delta: $0, count: model.entries.count) }
model.onPick = { model.selectedIndex = $0 }
model.onAccept = { accepted += 1 }
model.onCopy = { copied += 1 }
model.onPin = { pinned += 1 }
model.onEscape = { escapedQuery = model.query }
let window = HistoryPanelWindow(contentRect: CGRect(x: 100, y: 200, width: 680, height: 440), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
window.title = "Ditto design verification — sample clips"
window.hasShadow = true
window.backgroundColor = .clear
window.isOpaque = false
let view = HistoryPanelView(model: model)
window.contentView = view
app.activate(ignoringOtherApps: true)
window.makeKeyAndOrderFront(nil)
view.focusSearch()
pump()
let outputIndex = CommandLine.arguments.firstIndex(of: "--output-directory")
let output = outputIndex.flatMap { CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil } ?? ".build/history-ui"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func snapshot(_ name: String, appearance: NSAppearance.Name) {
    window.appearance = NSAppearance(named: appearance)
    view.needsDisplay = true
    view.layoutSubtreeIfNeeded()
    pump()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { check("\(name) bitmap", false); return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { check("\(name) PNG", false); return }
    do { try png.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png")) }
    catch { check("\(name) write", false) }
    check("\(name) renders panel-sized image", bitmap.pixelsWide >= 680 && bitmap.pixelsHigh >= 440)
}

snapshot("history-dark", appearance: .darkAqua)
snapshot("history-light", appearance: .aqua)
check("panel remains 680 by 440", view.bounds.size == CGSize(width: 680, height: 440))
let all = descendants(view)
let search = all.compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "DittoHistorySearch" }!
let table = all.compactMap { $0 as? NSTableView }.first!
let text = all.compactMap { $0 as? NSTextView }.first { $0.identifier?.rawValue == "DittoHistoryPreview" }!
let menuButton = all.compactMap { $0 as? NSPopUpButton }.first!
let editor = search.currentEditor() as! NSTextView
check("search receives initial keyboard focus", window.firstResponder === editor)
check("native table has accessible row semantics", table.accessibilityRole() == .table && (0..<table.numberOfRows).filter { table.delegate?.tableView?(table, shouldSelectRow: $0) == true }.count == clips.count)
check("results are dense 34 point rows", table.rect(ofRow: 1).height == 34)
check("preview retains original selectable text", text.string == clips[0].text && text.isSelectable && !text.isEditable)
func key(_ code: UInt16, _ characters: String, flags: NSEvent.ModifierFlags = []) {
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    editor.keyDown(with: event)
    pump()
}
key(125, "\u{f701}")
check("Down selects next clip and keeps search focus", model.selectedIndex == 1 && window.firstResponder === editor)
key(126, "\u{f700}")
key(126, "\u{f700}")
check("Up stops at first clip", model.selectedIndex == 0)
key(36, "\r")
check("Return dispatches acceptance once", accepted == 1)
model.query = "clipboard"
model.onQuery?(model.query)
view.focusSearch()
pump()
check("carried query is not selected", editor.selectedRange() == NSRange(location: 9, length: 0))
editor.insertText(" item 1", replacementRange: editor.selectedRange())
pump()
check("native field editing filters through real matcher", model.query == "clipboard item 1" && model.entries.count == 4)
key(53, "\u{1b}")
check("Escape dispatches original filter without clearing it", escapedQuery == "clipboard item 1" && model.query == "clipboard item 1")
menuButton.menu?.performActionForItem(at: 1)
menuButton.menu?.performActionForItem(at: 2)
check("Actions dispatch Copy and Pin callbacks", copied == 1 && pinned == 1)
let openActions = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!
let cancelMenu = Timer(timeInterval: 0.15, repeats: false) { _ in menuButton.menu?.cancelTrackingWithoutAnimation() }
RunLoop.main.add(cancelMenu, forMode: .common)
check("Command K opens native Actions menu", window.performKeyEquivalent(with: openActions))
check("Actions returns keyboard focus to search", window.firstResponder === search.currentEditor())
model.onQuery?("no matching sample")
pump()
check("no results clears selection and keeps panel size", model.entries.isEmpty && table.selectedRow == -1 && view.bounds.size == CGSize(width: 680, height: 440))
key(36, "\r")
check("Return with no results leaves search open", accepted == 1 && model.query == "no matching sample" && window.isVisible)
snapshot("history-no-results", appearance: .darkAqua)
model.entries = []
model.query = ""
pump()
snapshot("history-empty", appearance: .aqua)
model.entries = [ClipboardEntry(text: String(repeating: "👩🏽‍💻 sample line\n", count: 600), source: "TextEdit")]
model.selectedIndex = 0
pump()
check("long preview is bounded without splitting emoji", text.string.count == 5_000 && model.entries[0].text.hasPrefix(text.string))
snapshot("history-long", appearance: .darkAqua)
model.canInsert = false
pump()
check("unsupported destination labels Copy fallback", descendants(view).compactMap { $0 as? NSButton }.contains { $0.title == "Copy  ↵" })
snapshot("history-copy", appearance: .aqua)
model.onQuery?("")
pump()
window.orderOut(nil)
table.selectRowIndexes(IndexSet(integer: 3), byExtendingSelection: false)
pump()
check("hidden rows cannot change an autocomplete candidate", model.selectedIndex == 0)
model.query = "background autocomplete query"
pump()
check("hidden history does not rebuild during autocomplete", search.stringValue.isEmpty)
window.makeKeyAndOrderFront(nil)
view.focusSearch()
pump()
check("reopening history refreshes the current query", search.stringValue == model.query)
let report: [String: Any] = ["checks": checks, "failures": failures, "result": failures.isEmpty ? "pass" : "fail", "scope": "Native AppKit view/control dispatch with sample data; no host text, pasteboard writes, or global shortcut"]
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output).appendingPathComponent("results.json"))
window.orderOut(nil)
if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier { previousApp?.activate(options: [.activateIgnoringOtherApps]) }
print("\(checks) native UI checks, \(failures.count) failures")
exit(failures.isEmpty ? 0 : 1)
