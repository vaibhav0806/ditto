import AppKit
import Carbon
import ScreenCaptureKit
import DittoCore
import DittoUI

private final class SampleWorkspace: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        for row in 0..<28 {
            let rect = NSRect(x: 28, y: CGFloat(row * 24 + 16), width: bounds.width - 56, height: 22)
            (row.isMultiple(of: 3) ? NSColor.systemBlue.withAlphaComponent(0.22) : NSColor.systemPurple.withAlphaComponent(0.12)).setFill()
            rect.fill()
            let text = "sample workspace   \(row + 1)   const clipboard = { local: true, preview: 'sample only' };"
            text.draw(at: NSPoint(x: 36, y: rect.minY + 2), withAttributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
        }
    }
}

final class HistoryLiveCheck {
    private let output: URL
    private let onCheck: (String, Bool) -> Void
    private let onComplete: (String?) -> Void
    private let key: (CGKeyCode, CGEventFlags) -> Bool
    private let type: (String) -> Bool
    private let model = OverlayModel()
    private var clips: [ClipboardEntry] = []
    private var window: HistoryPanelWindow!
    private var backdrop: NSWindow!
    private var previousApp: NSRunningApplication?
    private var accepted = 0
    private var escaped = 0
    private var stopped = false

    init(output: URL, onCheck: @escaping (String, Bool) -> Void, onComplete: @escaping (String?) -> Void, key: @escaping (CGKeyCode, CGEventFlags) -> Bool, type: @escaping (String) -> Bool) {
        self.output = output
        self.onCheck = onCheck
        self.onComplete = onComplete
        self.key = key
        self.type = type
    }

    func start() {
        guard !IsSecureEventInputEnabled(), CGPreflightScreenCaptureAccess() else { finish("Live history check requires event access and Screen Recording without Secure Input"); return }
        previousApp = NSWorkspace.shared.frontmostApplication
        backdrop = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        backdrop.isReleasedWhenClosed = false
        backdrop.title = "Ditto controlled sample workspace"
        backdrop.contentView = SampleWorkspace()
        backdrop.center()
        backdrop.orderFront(nil)
        let screen = backdrop.screen ?? NSScreen.main!
        let frame = CGRect(x: backdrop.frame.midX - 340, y: backdrop.frame.midY - 220, width: 680, height: 440)
        window = HistoryPanelWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "Ditto live search fixture"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        model.history = true
        model.canReturnToCompletion = true
        model.canInsert = true
        model.destinationName = "Sample editor"
        model.destinationBundleID = "com.apple.TextEdit"
        model.query = "sample"
        clips = [ClipboardEntry(text: "{\n  \"sample\": \"clipboard\",\n  \"local\": true,\n  \"preview\": \"original text stays unchanged\"\n}", source: "TextEdit", sourceBundleID: "com.apple.TextEdit")]
        for index in 1...12 {
            let text = index == 1 ? "https://example.com/sample/very/long/path/to/a/copied/resource?query=original-text-stays-unchanged&local=true" : index == 2 ? "👩🏽‍💻\t sample command --keep-original-whitespace --preview-only" : "sample clip \(index)"
            clips.append(ClipboardEntry(text: text, copiedAt: Date().addingTimeInterval(Double(-60 * index)), source: "Safari", sourceBundleID: "com.apple.Safari", pinned: index == 2))
        }
        model.entries = clips
        model.onMove = { [weak self] delta in
            guard let self else { return }
            self.model.selectedIndex = HistoryPresentation.selectionIndex(current: self.model.selectedIndex, delta: delta, count: self.model.entries.count)
        }
        model.onPick = { [weak self] in self?.model.selectedIndex = $0 }
        model.onQuery = { [weak self] query in
            guard let self else { return }
            self.model.query = query
            self.model.entries = CompletionMatcher.matches(self.clips, query: query)
            self.model.selectedIndex = 0
        }
        model.onAccept = { [weak self] in self?.accepted += 1 }
        model.onEscape = { [weak self] in self?.escaped += 1; self?.window.orderOut(nil) }
        window.contentView = HistoryPanelView(model: model)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        (window.contentView as? HistoryPanelView)?.focusSearch()
        guard check("history fixture stays within the display", screen.visibleFrame.contains(window.frame)) else { return }
        capture(appearance: .darkAqua, name: "dark") {
            self.capture(appearance: .aqua, name: "light") {
                self.capture(appearance: .accessibilityHighContrastDarkAqua, name: "high-contrast") { self.keyboardScenario() }
            }
        }
    }

    private func capture(appearance: NSAppearance.Name, name: String, done: @escaping () -> Void) {
        window.appearance = NSAppearance(named: appearance)
        backdrop.appearance = NSAppearance(named: appearance)
        backdrop.contentView?.needsDisplay = true
        after(0.25) {
            guard #available(macOS 15.2, *) else { self.finish("Live fixture capture needs macOS 15.2"); return }
            let top = NSScreen.screens.first!.frame.maxY
            let rect = self.window.frame
            let region = CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
            SCScreenshotManager.captureImage(in: region) { image, _ in
                DispatchQueue.main.async {
                    guard !self.stopped, let image, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { self.finish("Live fixture screenshot failed"); return }
                    do { try png.write(to: self.output.deletingPathExtension().appendingPathExtension("history-\(name).png")) }
                    catch { self.finish("Could not write controlled fixture screenshot"); return }
                    guard self.check("live history \(name) capture", image.width >= 680 && image.height >= 440) else { return }
                    done()
                }
            }
        }
    }

    private func keyboardScenario() {
        guard key(125, []) else { finish("Destination lost foreground focus"); return }
        after(0.2) {
            guard self.check("OS Down selects the next history clip", self.model.selectedIndex == 1), self.key(36, []) else { return }
            self.after(0.2) {
                guard self.check("OS Return invokes history acceptance once", self.accepted == 1), self.key(40, .maskCommand) else { return }
                self.after(0.25) {
                    guard self.key(53, []) else { return }
                    self.after(0.2) {
                        guard self.check("OS Escape closes Actions without leaving history", self.escaped == 0 && self.window.isVisible), self.type("-no-match") else { return }
                        self.after(0.25) {
                            guard self.check("OS typing filters history in its own field", self.model.query == "sample-no-match" && self.model.entries.isEmpty), self.key(36, []) else { return }
                            self.after(0.2) {
                                guard self.check("OS Return with no results is a no-op", self.accepted == 1 && self.window.isVisible), self.key(53, []) else { return }
                                self.after(0.2) {
                                    guard self.check("OS Escape returns from history", self.escaped == 1 && !self.window.isVisible) else { return }
                                    self.finish(nil)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func check(_ name: String, _ value: Bool) -> Bool {
        onCheck(name, value)
        if !value { finish("Live history check failed: " + name) }
        return value
    }

    private func after(_ delay: Double, _ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { if !self.stopped { body() } }
    }

    private func finish(_ error: String?) {
        guard !stopped else { return }
        stopped = true
        window?.close()
        backdrop?.close()
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier { previousApp?.activate(options: [.activateIgnoringOtherApps]) }
        onComplete(error)
    }
}
