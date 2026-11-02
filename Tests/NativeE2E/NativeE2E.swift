import AppKit
import ApplicationServices
import Carbon
import ScreenCaptureKit
import DittoCore
import DittoCapture

private final class MaskFixtureEditor: NSTextView {
    var fill = NSColor(srgbRed: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 1)
    var textured = false

    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        bounds.fill()
        if textured {
            NSColor.gray.setFill()
            for x in stride(from: 0, to: Int(bounds.width), by: 8) { NSRect(x: x, y: 0, width: 4, height: Int(bounds.height)).fill() }
        }
        super.draw(dirtyRect)
        if string.isEmpty {
            let placeholder = "Ask anything, @tag files/folders, use skills, or / for commands"
            placeholder.draw(at: textContainerOrigin, withAttributes: [.font: font!, .foregroundColor: NSColor.gray])
        }
    }

    override func didChangeText() { super.didChangeText(); needsDisplay = true }
}

// Opt-in developer runner: actual WindowServer events, no simulated completion calls.
public final class NativeE2E {
    private let output: URL
    private let appID: String
    private var results: [[String: String]] = []
    private var fixture: AXUIElement?
    private var expectedPID: pid_t = 0
    private let token: String
    private var finished = false
    private var destinationWindow: NSWindow?
    private var checkedMaskEscape = false
    private var checkedMaskAcceptance = false
    private var chatRegion: CGRect?
    private var chatField: CGRect?

    public init(output: URL, appID: String = "com.apple.TextEdit") {
        self.output = output
        self.appID = appID
        if let index = CommandLine.arguments.firstIndex(of: "--e2e-fixture"), CommandLine.arguments.indices.contains(index + 1),
           CommandLine.arguments[index + 1].range(of: "^ditto-e2e-[0-9a-f]{8}$", options: .regularExpression) != nil {
            token = CommandLine.arguments[index + 1]
        } else { token = "ditto-e2e-" + UUID().uuidString.prefix(8).lowercased() }
    }

    public func start() {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { finish(error: "Ditto's OS event permissions are unavailable"); return }
        if appID == "com.vaibhav0806.ditto" {
            if CommandLine.arguments.contains("--e2e-mask-permission") {
                results.append(["scenario": "screen capture access", "allowed": String(CGPreflightScreenCaptureAccess())])
                finish()
                return
            }
            guard CGPreflightScreenCaptureAccess() else { finish(error: "Screen Recording permission is required for the live mask test"); return }
            runMaskFixture()
            return
        }
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

    private func runMaskFixture() {
        let editor = MaskFixtureEditor(frame: NSRect(x: 0, y: 0, width: 720, height: 230))
        editor.identifier = NSUserInterfaceItemIdentifier("DittoPracticeEditor")
        editor.drawsBackground = false
        editor.isRichText = false
        editor.allowsUndo = true
        editor.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        editor.textContainerInset = NSSize(width: 24, height: 24)
        let window = NSWindow(contentRect: editor.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Ditto background-matching fixture"
        window.contentView = editor
        window.isReleasedWhenClosed = false
        destinationWindow = window
        expectedPID = ProcessInfo.processInfo.processIdentifier
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        after(0.5) {
            guard self.type(self.token), self.key(0, flags: .maskCommand), self.key(8, flags: .maskCommand) else { return }
            self.after(0.4) {
                guard self.key(0, flags: .maskCommand), self.key(51) else { return }
                self.after(0.4) { self.maskCase(editor, index: 0) }
            }
        }
    }

    private func maskCase(_ editor: MaskFixtureEditor, index: Int) {
        let colors = [NSColor(srgbRed: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 1), .white,
                      NSColor(srgbRed: 34 / 255, green: 37 / 255, blue: 41 / 255, alpha: 1)]
        guard index < 4 else { finish(); return }
        editor.fill = colors[min(index, 2)]
        editor.textured = index == 3
        editor.insertionPointColor = index == 1 ? .black : .white
        editor.textColor = editor.insertionPointColor
        editor.needsDisplay = true
        after(0.3) {
            let top = NSScreen.screens.first!.frame.maxY
            let nativeCaret = editor.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
            let nativeField = editor.window!.convertToScreen(editor.convert(editor.bounds, to: nil))
            let caret = CGRect(x: nativeCaret.minX, y: top - nativeCaret.maxY, width: nativeCaret.width, height: nativeCaret.height)
            let field = CGRect(x: nativeField.minX, y: top - nativeField.maxY, width: nativeField.width, height: nativeField.height)
            guard let region = PlaceholderMask.region(field: field, caret: caret) else { self.finish(error: "Fixture has no valid mask region"); return }
            self.captureRegion(region) { before in
                guard let before else { return }
                self.results.append(["scenario": "source sample case \(index)", "uniform": String(PlaceholderBackgroundSampler.classify(image: before) != nil), "width": String(before.width), "height": String(before.height)])
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == self.expectedPID {
                    let png = NSBitmapImageRep(cgImage: before).representation(using: .png, properties: [:])
                    try? png?.write(to: self.output.deletingPathExtension().appendingPathExtension("source-\(index).png"))
                }
                guard self.key(9, flags: [.maskCommand, .maskAlternate]) else { return }
                self.awaitMask(editor, index: index, region: region, before: before, attempts: 20)
            }
        }
    }

    private func awaitMask(_ editor: MaskFixtureEditor, index: Int, region: CGRect, before: CGImage, attempts: Int) {
        after(0.1) {
            let mask = NSApp.windows.first { $0.title == "Ditto placeholder mask" && $0.isVisible }

            let ghost = NSApp.windows.first { $0.title == "Ditto completion" && $0.isVisible }
            if index == 3 {
                guard attempts == 1 else { self.awaitMask(editor, index: index, region: region, before: before, attempts: attempts - 1); return }
                self.record("textured background refuses masking", passed: mask == nil)
                let top = NSScreen.screens.first!.frame.maxY
                self.record("textured preview avoids placeholder line", passed: ghost != nil && ghost!.frame.maxY < top - region.maxY + 4)
                guard self.key(53) else { return }
                self.finish()
                return
            }
            guard let mask else {
                if attempts > 1 { self.awaitMask(editor, index: index, region: region, before: before, attempts: attempts - 1) }
                else { self.finish(error: "Solid background mask did not appear: case \(index)") }
                return
            }
            self.record("mask case \(index) leaves draft empty", passed: editor.string.isEmpty)
            self.record("mask case \(index) does not take focus", passed: !mask.canBecomeKey && mask.ignoresMouseEvents)
            self.captureRegion(region) { after in
                guard let after else { return }
                self.checkMaskPixels(before: before, after: after, index: index)
                if index == 0 && !self.checkedMaskEscape {
                    self.checkedMaskEscape = true
                    guard self.key(53) else { return }
                    self.after(0.2) {
                        self.record("Esc removes mask without changing draft", passed: !mask.isVisible && editor.string.isEmpty)
                        guard self.key(9, flags: [.maskCommand, .maskAlternate]) else { return }
                        self.awaitMask(editor, index: index, region: region, before: before, attempts: 20)
                    }
                    return
                }
                if index == 1 && !self.checkedMaskAcceptance {
                    self.checkedMaskAcceptance = true
                    guard self.key(48) else { return }
                    self.after(0.2) {
                        self.record("Tab accepts from masked empty field", passed: !mask.isVisible && editor.string == self.token)
                        guard self.key(6, flags: .maskCommand) else { return }
                        self.after(0.2) {
                            self.record("masked acceptance undo restores empty field", passed: editor.string.isEmpty)
                            guard self.key(9, flags: [.maskCommand, .maskAlternate]) else { return }
                            self.awaitMask(editor, index: index, region: region, before: before, attempts: 20)
                        }
                    }
                    return
                }
                guard self.type("di") else { return }
                self.after(0.25) {
                    self.record("mask case \(index) disappears on typing", passed: !mask.isVisible && editor.string == "di")
                    guard self.key(48) else { return }
                    self.after(0.25) {
                        self.record("mask case \(index) keeps completion active after typing", passed: editor.string == self.token)
                        guard !self.finished, self.key(0, flags: .maskCommand), self.key(51) else { return }
                        self.after(0.25) { self.maskCase(editor, index: index + 1) }
                    }
                }
            }
        }
    }

    private func captureRegion(_ region: CGRect, completion: @escaping (CGImage?) -> Void) {
        guard #available(macOS 14, *) else { finish(error: "Mask fixture screenshot requires macOS 14"); return }
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, _ in
            guard let display = content?.displays.first(where: { $0.frame.contains(region) }) else {
                DispatchQueue.main.async { self.finish(error: "Fixture display not found") }
                return
            }
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = region.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            let scale = self.destinationWindow?.backingScaleFactor ?? 2
            configuration.width = Int((region.width * scale).rounded(.up))
            configuration.height = Int((region.height * scale).rounded(.up))
            configuration.showsCursor = false
            let filter = SCContentFilter(display: display, excludingWindows: [])
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, _ in
                DispatchQueue.main.async {
                    guard image != nil else { self.finish(error: "Fixture screenshot failed"); return }
                    completion(image)
                }
            }
        }
    }

    private func checkMaskPixels(before: CGImage, after: CGImage, index: Int) {
        let source = NSBitmapImageRep(cgImage: before)
        let masked = NSBitmapImageRep(cgImage: after)
        func rgb(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) -> [Int]? {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return nil }
            return [color.redComponent, color.greenComponent, color.blueComponent].map { Int(($0 * 255).rounded()) }
        }
        guard source.pixelsWide == masked.pixelsWide, source.pixelsHigh == masked.pixelsHigh else {
            finish(error: "Fixture screenshot dimensions changed"); return
        }
        var backgroundCounts: [[Int]: Int] = [:]
        for y in 0..<2 {
            for x in 0..<source.pixelsWide {
                if let color = rgb(source, x, y) { backgroundCounts[color, default: 0] += 1 }
            }
        }
        guard let reference = backgroundCounts.max(by: { $0.value < $1.value })?.key else { finish(error: "Source background reference missing"); return }
        var originalInk = 0
        var remainingInk = 0
        var maximumError = 0
        for y in 4..<(source.pixelsHigh - 4) {
            for x in (source.pixelsWide / 2)..<(source.pixelsWide - 8) {
                let beforeError = zip(rgb(source, x, y) ?? [0, 0, 0], reference).map { abs($0 - $1) }.max() ?? 255
                let afterError = zip(rgb(masked, x, y) ?? [0, 0, 0], reference).map { abs($0 - $1) }.max() ?? 255
                if beforeError > 1 { originalInk += 1 }
                if afterError > 1 { remainingInk += 1 }
                maximumError = max(maximumError, afterError)
            }
        }
        results.append(["scenario": "live pixel measurement case \(index)", "maxChannelError": String(maximumError), "originalPlaceholderPixels": String(originalInk), "remainingPixelsAboveDither": String(remainingInk)])
        record("mask case \(index) removes placeholder within measured capture dithering", passed: originalInk > 20 && remainingInk == 0)
        let png = NSBitmapImageRep(cgImage: after).representation(using: .png, properties: [:])
        try? png?.write(to: output.deletingPathExtension().appendingPathExtension("mask-\(index).png"))
    }

    private func beginWhenActive(attempts: Int = 20) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else {
            guard attempts > 0 else { finish(error: "Destination did not become foreground"); return }
            after(0.1) { self.beginWhenActive(attempts: attempts - 1) }
            return
        }
        if appID == "com.google.Chrome" { runBrowser() }
        else if appID == "com.mitchellh.ghostty" { runTerminal() }
        else if isChatComposer { runChatComposer() }
        else { runEditor() }
    }

    private var isChatComposer: Bool { ["com.t3tools.t3code", "com.tinyspeck.slackmacgap"].contains(appID) }

    private func runChatComposer() {
        guard let element = focused(), let initial = read(element), InputPolicy.isVisuallyBlank(initial),
              attribute(element, kAXRoleAttribute) as? String == kAXTextAreaRole,
              (attribute(element, kAXDescriptionAttribute) as? String)?.lowercased().contains("message") == true,
              NSPasteboard.general.string(forType: .string) == token else {
            finish(error: "Focus an empty message composer; clipboard must contain the generated mask fixture")
            return
        }
        fixture = element
        results.append(["scenario": "initial empty paragraph", "utf16Length": String(initial.utf16.count), "selection": selection(element).map(NSStringFromRange) ?? "unavailable"])
        recordCapabilities(element)
        guard key(9, flags: [.maskCommand, .maskAlternate]) else { return }
        after(1.2) {
            self.captureGhost(expectedPointSize: nil)
            guard !self.finished else { return }
            self.record("invocation leaves actual draft unchanged", passed: self.read(element) == initial)
            let mask = NSApp.windows.first { $0.title == "Ditto placeholder mask" && $0.isVisible }
            if mask == nil, let region = self.chatRegion {
                self.captureRegion(CGRect(x: region.minX, y: region.minY, width: region.width, height: region.height + 16)) { image in
                    if let image, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                        try? png.write(to: self.output.deletingPathExtension().appendingPathExtension("chat-sample.png"))
                    }
                }
            }
            self.results.append(["scenario": "actual placeholder presentation", "maskVisible": String(mask != nil)])
            let ghost = NSApp.windows.first { $0.title == "Ditto completion" && $0.isVisible }
            let top = NSScreen.screens.first!.frame.maxY
            self.record("actual blank composer avoids overlapping placeholder", passed: mask != nil || ((self.chatRegion ?? self.chatField).map { region in ghost.map { $0.frame.maxY < top - region.maxY + 4 || $0.frame.minY > top - region.minY } ?? false } ?? false))
            guard !self.finished, self.key(53) else { return }
            self.after(0.2) {
                self.record("Esc restores empty actual composer", passed: self.read(element) == initial && mask?.isVisible != true)
                guard !self.finished, self.key(9, flags: [.maskCommand, .maskAlternate]) else { return }
                self.after(0.8) {
                    guard self.type("ditto-e2e-") else { return }
                    self.after(0.3) {
                        let query = self.read(element) ?? ""
                        self.results.append(["scenario": "typed paragraph shape", "utf16Length": String(query.utf16.count), "selection": self.selection(element).map(NSStringFromRange) ?? "unavailable", "trailingNewline": String(query.hasSuffix("\n"))])
                        self.record("actual draft receives query and mask disappears", passed: self.read(element)?.trimmingCharacters(in: .newlines) == "ditto-e2e-" && mask?.isVisible != true)
                        guard !self.finished, self.key(48) else { return }
                        self.after(0.6) {
                            self.record("Tab completes actual composer", passed: self.read(element)?.trimmingCharacters(in: .newlines) == self.token)
                            self.record("actual completion preserves clipboard", passed: NSPasteboard.general.string(forType: .string) == self.token)
                            guard !self.finished, self.key(6, flags: .maskCommand) else { return }
                            self.after(0.3) {
                                let undo = self.read(element)
                                self.results.append(["scenario": "host undo state", "queryRestored": String(undo?.trimmingCharacters(in: .newlines) == "ditto-e2e-"), "empty": String(undo.map(InputPolicy.isVisuallyBlank) == true), "readable": String(undo != nil), "sameFocusedElement": String(self.focused().map { CFEqual($0, element) } == true)])
                                self.record("actual composer acceptance undo", passed: self.read(element)?.trimmingCharacters(in: .newlines) == "ditto-e2e-")
                                guard !self.finished, self.key(53), self.key(0, flags: .maskCommand), self.key(51) else { return }
                                self.after(0.3) {
                                    self.record("test draft cleaned without sending", passed: self.read(element).map(InputPolicy.isVisuallyBlank) == true)
                                    self.finish()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
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
        results.append(["scenario": "ghost dimensions", "width": String(Double(window.frame.width)), "height": String(Double(window.frame.height))])
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
        var ancestor = element
        for level in 0..<3 {
            var geometry: [String: String] = ["scenario": "field hierarchy", "level": String(level)]
            if let position = attribute(ancestor, kAXPositionAttribute), let size = attribute(ancestor, kAXSizeAttribute),
               CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
                var point = CGPoint.zero
                var dimensions = CGSize.zero
                AXValueGetValue(position as! AXValue, .cgPoint, &point)
                AXValueGetValue(size as! AXValue, .cgSize, &dimensions)
                geometry["rect"] = NSStringFromRect(CGRect(origin: point, size: dimensions))
                if level == 0 { chatField = CGRect(origin: point, size: dimensions) }
            }
            if let children = attribute(ancestor, kAXChildrenAttribute) as? [AXUIElement] {
                geometry["childRoles"] = children.prefix(16).map { attribute($0, kAXRoleAttribute) as? String ?? "unknown" }.joined(separator: ",")
            }
            results.append(geometry)
            guard let parent = attribute(ancestor, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            ancestor = parent as! AXUIElement
        }
        if let placeholder = attribute(element, kAXPlaceholderValueAttribute) as? String,
           let rawParent = attribute(element, kAXParentAttribute), CFGetTypeID(rawParent) == AXUIElementGetTypeID(),
           let siblings = attribute(rawParent as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement], siblings.count <= 32 {
            var pending = siblings
            var visited = 0
            while !pending.isEmpty && visited < 32 {
                let sibling = pending.removeFirst()
                visited += 1
                if let children = attribute(sibling, kAXChildrenAttribute) as? [AXUIElement], children.count <= 32 { pending.append(contentsOf: children) }
                guard attribute(sibling, kAXValueAttribute) as? String == placeholder else { continue }
                if let position = attribute(sibling, kAXPositionAttribute), let size = attribute(sibling, kAXSizeAttribute),
                   CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
                    var point = CGPoint.zero
                    var dimensions = CGSize.zero
                    AXValueGetValue(position as! AXValue, .cgPoint, &point)
                    AXValueGetValue(size as! AXValue, .cgSize, &dimensions)
                    results.append(["scenario": "placeholder geometry", "rect": NSStringFromRect(CGRect(origin: point, size: dimensions))])
                    if attribute(sibling, kAXRoleAttribute) as? String == kAXStaticTextRole,
                       let fieldPosition = attribute(element, kAXPositionAttribute), let fieldSize = attribute(element, kAXSizeAttribute) {
                        var origin = CGPoint.zero
                        var extent = CGSize.zero
                        AXValueGetValue(fieldPosition as! AXValue, .cgPoint, &origin)
                        AXValueGetValue(fieldSize as! AXValue, .cgSize, &extent)
                        chatRegion = PlaceholderMask.region(field: CGRect(origin: origin, size: extent), caret: CGRect(x: point.x, y: point.y, width: 1, height: dimensions.height))
                    }
                }
            }
        }
        for length in [0, 1] {
            var range = CFRange(location: 0, length: length)
            var bounds: CFTypeRef?
            if let parameter = AXValueCreate(.cfRange, &range),
               AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &bounds) == .success,
               let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() {
                var rect = CGRect.zero
                if AXValueGetValue(bounds as! AXValue, .cgRect, &rect) {
                    results.append(["scenario": "empty range geometry", "length": String(length), "rect": NSStringFromRect(rect)])
                }
            }
        }
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
        if isChatComposer, let fixture {
            guard let current = focused(), CFEqual(current, fixture) else { finish(error: "Stopped: composer lost focus"); return false }
        }
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
        if isChatComposer, let fixture {
            guard let current = focused(), CFEqual(current, fixture) else { finish(error: "Stopped: composer lost focus"); return false }
        }
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
