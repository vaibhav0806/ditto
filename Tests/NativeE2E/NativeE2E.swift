import AppKit
import ApplicationServices
import Carbon

// Opt-in developer runner: actual WindowServer events, no simulated completion calls.
public final class NativeE2E {
    private let output: URL
    private let appID: String
    private var results: [[String: String]] = []
    private var fixture: AXUIElement?
    private var expectedPID: pid_t = 0
    private let token = "ditto-e2e-" + UUID().uuidString.prefix(8).lowercased()
    private var finished = false
    private var destinationWindow: NSWindow?

    public init(output: URL, appID: String = "com.apple.TextEdit") {
        self.output = output
        self.appID = appID
    }

    public func start() {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { finish(error: "Ditto's OS event permissions are unavailable"); return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appID) else { finish(error: "Test app is not installed"); return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            DispatchQueue.main.async {
                guard let app, error == nil else { self.finish(error: "Could not activate test app"); return }
                self.expectedPID = app.processIdentifier
                app.activate(options: [.activateIgnoringOtherApps])
                self.after(0.6) { self.beginWhenActive() }
            }
        }
    }

    private func beginWhenActive(attempts: Int = 20) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else {
            guard attempts > 0 else { finish(error: "Destination did not become foreground"); return }
            after(0.1) { self.beginWhenActive(attempts: attempts - 1) }
            return
        }
        if appID == "com.google.Chrome" { runBrowser() }
        else if appID == "com.mitchellh.ghostty" { runTerminal() }
        else { runEditor() }
    }

    private func runEditor() {
        guard appID == "com.apple.TextEdit" else { finish(error: "No scenario for this app"); return }
        guard key(45, flags: .maskCommand) else { return } // new disposable document
        after(0.5) {
            guard let element = self.focused(), self.read(element) == "" else { self.finish(error: "New document is not an empty fixture"); return }
            self.fixture = element
            guard self.type(self.token), self.key(0, flags: .maskCommand), self.key(8, flags: .maskCommand) else { return }
            self.after(0.6) {
                guard self.key(0, flags: .maskCommand), self.type("External ") else { return }
                self.after(0.3) {
                    guard self.check("fixture prepared", expected: "External ") else { return }
                    guard self.key(9, flags: [.maskCommand, .maskAlternate]) else { return }
                    self.after(0.3) {
                        self.captureGhost(expectedPointSize: nil)
                        guard self.type("dit") else { return }
                        self.after(0.3) {
                            guard self.key(48) else { return }
                            self.after(0.4) {
                                guard self.check("external completion", expected: "External " + self.token) else { return }
                                guard self.key(6, flags: .maskCommand) else { return }
                                self.after(0.3) {
                                    guard self.check("one-step undo", expected: "External dit") else { return }
                                    self.editorScenarios()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func runBrowser() {
        guard key(45, flags: .maskCommand) else { return }
        after(0.5) {
            guard self.key(37, flags: .maskCommand), self.type("http://127.0.0.1:8766/editor.html"), self.key(36) else { return }
            self.after(1.2) {
                guard let element = self.focused(), self.read(element) == "Browser " else {
                    self.finish(error: "Browser fixture did not load and focus its textarea")
                    return
                }
                self.fixture = element
                self.recordCapabilities(element)
                var clipboardBeforeNoOp = 0
                let unicode = "café👋-" + self.token + "\nsecond line"
                let steps: [() -> Void] = [
                    { self.resetField(self.token); self.key(0, flags: .maskCommand); self.key(8, flags: .maskCommand) },
                    { self.resetField("Browser ") },
                    { self.key(9, flags: [.maskCommand, .maskAlternate]) },
                    { self.captureGhost(); self.type("dit") },
                    { self.key(48) },
                    { _ = self.check("browser completion from fresh capture", expected: "Browser " + self.token); self.key(6, flags: .maskCommand) },
                    { _ = self.check("browser undo", expected: "Browser dit"); self.resetField("No-op ") },
                    { self.key(9, flags: [.maskCommand, .maskAlternate]) },
                    { self.type(self.token) },
                    { clipboardBeforeNoOp = NSPasteboard.general.changeCount; self.key(48) },
                    { _ = self.check("already complete text", expected: "No-op " + self.token); self.record("no-op leaves clipboard untouched", passed: NSPasteboard.general.changeCount == clipboardBeforeNoOp); self.resetField("Stale ") },
                    { self.key(9, flags: [.maskCommand, .maskAlternate]) },
                    { self.type("dit") },
                    { self.key(123); self.key(48) },
                    { _ = self.check("cursor move cancels completion", expected: "Stale dit"); self.fixture = self.focused(); self.resetField("Input ") },
                    { self.key(9, flags: [.maskCommand, .maskAlternate]) },
                    { self.type("dit") },
                    { self.key(48) },
                    { _ = self.check("single-line input completion", expected: "Input " + self.token); self.key(48) },
                    { self.fixture = self.focused(); self.resetField("Rich ") },
                    { self.key(9, flags: [.maskCommand, .maskAlternate]) },
                    { self.type("dit") },
                    { self.key(48) },
                    { _ = self.check("contenteditable completion", expected: "Rich " + self.token); self.key(48) },
                    { self.key(9, flags: [.maskCommand, .maskAlternate]) },
                    { self.record("secure input shows no suggestions", passed: !NSApp.windows.contains { $0.isVisible && $0.level == .floating }); self.key(48, flags: .maskShift); self.key(48, flags: .maskShift); self.key(48, flags: .maskShift) },
                    { self.fixture = self.focused(); self.resetField(unicode); self.key(0, flags: .maskCommand); self.key(8, flags: .maskCommand) },
                    { self.resetField("Multiline ") },
                    { self.key(9, flags: [.maskCommand, .maskAlternate]) },
                    { self.type("café👋") },
                    { self.key(48) },
                    { _ = self.check("Unicode query and multiline paste", expected: "Multiline " + unicode); self.resetField("Enter ") },
                    { self.key(9, flags: [.maskCommand, .maskAlternate]) },
                    { self.type("café") },
                    { self.key(36) },
                    { _ = self.check("Enter does not accept completion", expected: "Enter café\n"); self.resetField("Switch ") },
                    { self.key(9, flags: [.maskCommand, .maskAlternate]) },
                    { self.type("café") }
                ]
                self.runSteps(steps) { self.switchAppScenario() }
            }
        }
    }

    private func editorScenarios() {
        let eventQuery = CommandLine.arguments.contains("--e2e-event-query")
        let steps: [() -> Void] = [
            { self.record("completion preserves clipboard", passed: NSPasteboard.general.string(forType: .string) == self.token); self.resetField("Fast ") },
            { self.key(9, flags: [.maskCommand, .maskAlternate]) },
            { self.type("dit"); self.key(48) },
            { _ = self.check("immediate Tab accepts current query", expected: "Fast " + self.token); self.resetField(self.token + "-first"); self.key(0, flags: .maskCommand); self.key(8, flags: .maskCommand) },
            { self.resetField(self.token + "-second"); self.key(0, flags: .maskCommand); self.key(8, flags: .maskCommand) },
            { self.resetField("Cycle ") },
            { self.key(9, flags: [.maskCommand, .maskAlternate]) },
            { self.type(self.token) },
            { self.key(125) },
            { self.key(48) },
            { _ = self.check("cycle chooses older matching item", expected: "Cycle " + self.token + "-first"); self.record("cycling preserves clipboard", passed: NSPasteboard.general.string(forType: .string) == self.token + "-second"); self.resetField("History ") },
            { self.key(9, flags: [.maskCommand, .maskAlternate]) },
            { self.type(self.token) },
            { self.key(37, flags: .maskCommand) },
            { self.record("history opens only on explicit command", passed: NSApp.windows.contains { $0.isVisible && $0.level == .floating && $0.canBecomeKey }); self.type("-second") },
            { self.key(36) },
            { _ = self.check("history action preserves destination contract", expected: "History " + self.token + (eventQuery ? "" : "-second")); if eventQuery { self.record("fallback history copies full selection", passed: NSPasteboard.general.string(forType: .string) == self.token + "-second") } }
        ]
        runSteps(steps) { self.escapeScenario() }
    }

    private func resetField(_ text: String) {
        guard !finished, key(0, flags: .maskCommand) else { return }
        _ = type(text)
    }

    private func runSteps(_ steps: [() -> Void], index: Int = 0, done: @escaping () -> Void) {
        guard !finished else { return }
        guard index < steps.count else { done(); return }
        steps[index]()
        after(0.35) { self.runSteps(steps, index: index + 1, done: done) }
    }

    private func captureGhost(expectedPointSize: CGFloat? = 16) {
        guard let window = NSApp.windows.first(where: { $0.title == "Ditto completion" && $0.isVisible }),
              let content = window.contentView else { record("inline ghost visible", passed: false); return }
        record("inline ghost does not take focus", passed: !window.canBecomeKey)
        record("inline ghost has nonzero compact size", passed: window.frame.height >= 20 && window.frame.height < 80 && window.frame.width > 20)
        let texts = content.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        guard texts.first == token else { record("ghost suggests fresh clipboard item", passed: false); return }
        record("ghost suggests fresh clipboard item", passed: true)
        let font = (content.subviews.first as? NSTextField)?.font
        results.append(["scenario": "rendered font", "name": font?.fontName ?? "none", "size": String(Double(font?.pointSize ?? 0)), "fixedPitch": String(font?.isFixedPitch ?? false)])
        if let expectedPointSize {
            record("ghost matches destination font", passed: font?.isFixedPitch == true && abs((font?.pointSize ?? 0) - expectedPointSize) < 0.1)
        }
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            record("ghost renders nonempty pixels", passed: false)
            return
        }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            record("ghost renders nonempty pixels", passed: false)
            return
        }
        do {
            try png.write(to: output.deletingPathExtension().appendingPathExtension("ghost.png"))
            let hasInk = (0..<rep.pixelsWide).contains { x in
                (0..<rep.pixelsHigh).contains { y in (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 }
            }
            record("ghost renders nonempty pixels", passed: hasInk)
        } catch { record("ghost snapshot written", passed: false) }
    }

    private func switchAppScenario(expectedSource: String = "Switch café") {
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 160))
        text.isRichText = false
        let window = NSWindow(contentRect: text.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Ditto E2E destination"
        window.contentView = text
        window.isReleasedWhenClosed = false
        destinationWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(text)
        expectedPID = ProcessInfo.processInfo.processIdentifier
        after(0.3) {
            guard self.key(48) else { return }
            self.after(0.3) {
                _ = self.check("app switch preserves source text", expected: expectedSource)
                self.record("app switch restores normal destination typing", passed: text.string == "\t")
                if !self.finished { self.finish() }
            }
        }
    }

    private func record(_ name: String, passed: Bool) {
        guard !finished else { return }
        results.append(["scenario": name, "result": passed ? "pass" : "fail"])
        write()
        if !passed { finish(error: "Fixture assertion failed: " + name) }
    }

    private func runTerminal() {
        guard key(45, flags: .maskCommand) else { return }
        after(1) {
            guard let element = self.focused() else { self.finish(error: "Terminal has no focused accessible element"); return }
            self.fixture = element
            self.recordCapabilities(element)
            let beforeText = self.read(element) ?? ""
            let beforeRange = self.selection(element)
            guard self.type("dit") else { return }
            self.after(0.3) {
                let afterText = self.read(element) ?? ""
                let afterRange = self.selection(element)
                self.results.append(["scenario": "terminal query tracking", "textGrowth": String(afterText.utf16.count - beforeText.utf16.count), "cursorBefore": String(beforeRange?.location ?? -1), "cursorAfter": String(afterRange?.location ?? -1)])
                guard self.key(9, flags: [.maskCommand, .maskAlternate]) else { return }
                self.after(0.3) {
                    let noHistory = !NSApp.windows.contains { $0.isVisible && $0.level == .floating && $0.canBecomeKey }
                    self.results.append(["scenario": "terminal invocation does not open history", "result": noHistory ? "pass" : "fail"])
                    _ = self.key(32, flags: .maskControl)
                    self.finish(error: "Terminal completion requires an adapter; current generic insertion path is not verified")
                }
            }
        }
    }

    private func selection(_ element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private func recordCapabilities(_ element: AXUIElement) {
        var selected = DarwinBoolean(false)
        var range = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &selected)
        AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &range)
        results.append(["scenario": "field capabilities", "selectedTextWritable": String(selected.boolValue), "selectionWritable": String(range.boolValue)])
        write()
    }

    private func escapeScenario() {
        guard key(0, flags: .maskCommand), type("Keep ") else { return }
        after(0.2) {
            guard self.key(9, flags: [.maskCommand, .maskAlternate]) else { return }
            self.after(0.2) {
                guard self.type("di"), self.key(53), self.key(48) else { return }
                self.after(0.3) {
                    guard self.check("escape preserves typing", expected: "Keep di\t") else { return }
                    self.resetField("Switch ")
                    self.after(0.2) {
                        guard self.key(9, flags: [.maskCommand, .maskAlternate]) else { return }
                        self.after(0.2) {
                            guard self.type("dit") else { return }
                            self.after(0.2) { self.switchAppScenario(expectedSource: "Switch dit") }
                        }
                    }
                }
            }
        }
    }

    private func focused() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func read(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func check(_ name: String, expected: String) -> Bool {
        let passed = fixture.flatMap(read) == expected
        results.append(["scenario": name, "result": passed ? "pass" : "fail"])
        write()
        if !passed { finish(error: "Fixture assertion failed: \(name)") }
        return passed
    }

    @discardableResult private func key(_ code: CGKeyCode, flags: CGEventFlags = []) -> Bool {
        guard !finished, NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else {
            finish(error: "Stopped: destination lost foreground focus")
            return false
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { finish(error: "Could not create event"); return false }
            event.flags = down ? flags : []
            event.post(tap: .cghidEventTap)
        }
        return true
    }

    @discardableResult private func type(_ text: String) -> Bool {
        guard !finished, NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else { finish(error: "Aborted: foreground app changed"); return false }
        let source = CGEventSource(stateID: .hidSystemState)
        for character in text {
            guard !finished, NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else { finish(error: "Foreground changed while typing fixture"); return false }
            let units = Array(String(character).utf16)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { return false }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.post(tap: .cghidEventTap)
            }
        }
        return true
    }

    private func after(_ delay: Double, _ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { if !self.finished { body() } }
    }

    private func write() {
        let value: [String: Any] = ["app": appID, "fixture": token, "queryTracking": CommandLine.arguments.contains("--e2e-event-query") ? "forced event query" : "automatic", "scenarios": results]
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: output, options: .atomic) }
    }

    private func finish(error: String? = nil) {
        guard !finished else { return }
        finished = true
        destinationWindow?.close()
        if let error { results.append(["scenario": "runner", "result": "fail", "reason": error, "frontmostBundleID": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"]) }
        else { results.append(["scenario": "runner", "result": "pass"]) }
        write()
    }
}
