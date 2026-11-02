import AppKit
import ApplicationServices
import Carbon
import ScreenCaptureKit
import DittoCore
import DittoCapture
import DittoUI

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
    private var chatPlaceholder: CGRect?
    private var historyLiveCheck: HistoryLiveCheck?

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
            if CommandLine.arguments.contains("--e2e-history-ui") {
                expectedPID = ProcessInfo.processInfo.processIdentifier
                historyLiveCheck = HistoryLiveCheck(output: output, onCheck: { [weak self] in self?.record($0, passed: $1) }, onComplete: { [weak self] in self?.finish(error: $0) }, key: { [weak self] in self?.key($0, flags: $1) ?? false }, type: { [weak self] in self?.type($0) ?? false })
                historyLiveCheck?.start()
                return
            }
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
                self.after(0.4) {
                    if CommandLine.arguments.contains("--e2e-prefilled") { self.prefilledCase(editor, index: 0) }
                    else { self.maskCase(editor, index: 0) }
                }
            }
        }
    }

    private func prefilledCase(_ editor: MaskFixtureEditor, index: Int) {
        let drafts = [("Existing draft ", ""), ("First line\nExisting draft ", ""), ("Existing draft ", "\nFollowing line"), (String(repeating: "x", count: 60) + " ", "")]
        guard index < drafts.count else { finish(); return }
        let (before, afterCaret) = drafts[index]
        let original = before + afterCaret
        editor.string = original
        editor.setSelectedRange(NSRange(location: before.utf16.count, length: 0))
        editor.undoManager?.removeAllActions()
        guard key(9, flags: [.maskCommand, .maskAlternate]) else { return }
        after(0.3) {
            guard let ghost = NSApp.windows.first(where: { $0.title == "Ditto completion" && $0.isVisible }),
                  let label = ghost.contentView as? GhostTextView else { self.record("prefilled case \(index) shows suggestion", passed: false); return }
            let caret = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
            let labelRect = ghost.convertToScreen(label.convert(label.bounds, to: nil))
            let field = editor.window!.convertToScreen(editor.convert(editor.bounds, to: nil))
            if let layout = editor.layoutManager, before.utf16.count > 0 {
                let glyph = layout.glyphIndexForCharacter(at: before.utf16.count - 1)
                let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let baseline = editor.window!.convertPoint(toScreen: editor.convert(NSPoint(x: 0, y: editor.textContainerOrigin.y + line.minY + layout.location(forGlyphAt: glyph).y), to: nil)).y
                let labelBaseline = labelRect.maxY - label.baselineOffsetFromTop + label.penOffset.y
                self.results.append(["scenario": "prefilled case \(index) baseline", "offset": String(Double(labelBaseline - baseline)), "labelHeight": String(Double(labelRect.height)), "caretHeight": String(Double(caret.height))])
                self.record("prefilled case \(index) matches the host baseline", passed: abs(labelBaseline - baseline) <= 1)
            }
            self.results.append(["scenario": "prefilled case \(index) geometry", "verticalOffset": String(Double(labelRect.midY - caret.midY))])
            self.record("prefilled case \(index) shares caret line inside field", passed: abs(labelRect.midY - caret.midY) <= 4 && abs(labelRect.minX - caret.minX) <= 1 && field.contains(labelRect))
            self.record("prefilled case \(index) keeps existing text untouched", passed: editor.string == original)
            self.record("prefilled case \(index) needs no placeholder mask", passed: !NSApp.windows.contains { $0.title == "Ditto placeholder mask" && $0.isVisible })
            guard !self.finished else { return }
            let top = NSScreen.screens.first!.frame.maxY
            self.captureRegion(CGRect(x: field.minX, y: top - field.maxY, width: field.width, height: field.height)) { image in
                guard !self.finished, NSWorkspace.shared.frontmostApplication?.processIdentifier == self.expectedPID else { self.finish(error: "Prefilled fixture lost focus"); return }
                if let image, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) { try? png.write(to: self.output.deletingPathExtension().appendingPathExtension("prefilled-\(index).png")) }
                guard self.key(53) else { return }
                self.after(0.15) {
                    self.record("prefilled case \(index) Escape preserves draft", passed: editor.string == original && !ghost.isVisible)
                    guard self.key(9, flags: [.maskCommand, .maskAlternate]) else { return }
                    self.after(0.25) {
                        guard self.key(48) else { return }
                        self.after(0.25) {
                            self.record("prefilled case \(index) inserts at caret without replacing existing text", passed: editor.string == before + self.token + afterCaret)
                            self.prefilledCase(editor, index: index + 1)
                        }
                    }
                }
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
        if CommandLine.arguments.contains("--e2e-composer-typography") { emptyComposerTypography(element); return }
        guard key(9, flags: [.maskCommand, .maskAlternate]) else { return }
        after(1.2) {
            self.captureGhost(expectedPointSize: nil)
            guard !self.finished else { return }
            let emptyStyle = (NSApp.windows.first { $0.title == "Ditto completion" && $0.isVisible }?.contentView as? GhostTextView)?.style
            if let emptyStyle { self.results.append(["scenario": "empty composer typography", "font": emptyStyle.font.fontName, "size": String(Double(emptyStyle.font.pointSize)), "reported": String(emptyStyle.reported)]) }
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
                        let filledStyle = (NSApp.windows.first { $0.title == "Ditto completion" && $0.isVisible }?.contentView as? GhostTextView)?.style
                        if let filledStyle { self.results.append(["scenario": "filled composer typography", "font": filledStyle.font.fontName, "size": String(Double(filledStyle.font.pointSize)), "reported": String(filledStyle.reported)]) }
                        self.record("empty and filled composer use the same font and size", passed: emptyStyle != nil && filledStyle != nil && emptyStyle!.font.fontName == filledStyle!.font.fontName && abs(emptyStyle!.font.pointSize - filledStyle!.font.pointSize) < 0.1)
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
                                let restored = self.appID == "com.tinyspeck.slackmacgap"
                                    ? undo.map(InputPolicy.isVisuallyBlank) == true
                                    : undo?.trimmingCharacters(in: .newlines) == "ditto-e2e-"
                                self.record("actual composer native undo", passed: restored && self.focused().map { CFEqual($0, element) } == true)
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

    private func emptyComposerTypography(_ element: AXUIElement) {
        guard let field = elementBounds(element), field.height >= 34 else { finish(error: "Composer geometry unavailable"); return }
        let left = (chatPlaceholder?.minX ?? field.minX) + 2
        let region = CGRect(x: left, y: field.minY + 2, width: min(700, field.maxX - left - 2), height: 30)
        captureRegion(region) { original in
            guard let original, self.read(element).map(InputPolicy.isVisuallyBlank) == true else { self.finish(error: "Empty composer changed before invocation"); return }
            try? NSBitmapImageRep(cgImage: original).representation(using: .png, properties: [:])?.write(to: self.output.deletingPathExtension().appendingPathExtension("placeholder.png"))
            guard self.key(9, flags: [.maskCommand, .maskAlternate]) else { return }
            self.after(1.2) {
                guard let ghost = NSApp.windows.first(where: { $0.title == "Ditto completion" && $0.isVisible }), let view = ghost.contentView as? GhostTextView else { self.finish(error: "No empty composer suggestion"); return }
                let top = NSScreen.screens.first!.frame.maxY
                self.results.append(["scenario": "empty composer geometry", "ghost": NSStringFromRect(CGRect(x: ghost.frame.minX, y: top - ghost.frame.maxY, width: ghost.frame.width, height: ghost.frame.height)), "font": view.style.font.fontName, "size": String(Double(view.style.font.pointSize)), "baseline": String(Double(view.baselineOffsetFromTop)), "maskVisible": String(NSApp.windows.contains { $0.title == "Ditto placeholder mask" && $0.isVisible })])
                self.captureRegion(region) { before in
                    guard let before, self.key(48) else { return }
                    self.after(0.4) {
                        self.record("empty composer acceptance", passed: self.read(element)?.trimmingCharacters(in: .newlines) == self.token)
                        guard !self.finished, self.key(123, flags: .maskCommand) else { return }
                        self.after(0.15) {
                            self.captureRegion(region) { accepted in
                                guard let accepted else { return }
                                for (kind, image) in [("ghost", before), ("accepted", accepted)] { try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: self.output.deletingPathExtension().appendingPathExtension("case-0-\(kind).png")) }
                                guard self.key(0, flags: .maskCommand), self.key(51) else { return }
                                self.after(0.2) {
                                    self.record("empty composer typography draft cleaned without sending", passed: self.read(element).map(InputPolicy.isVisuallyBlank) == true)
                                    guard !self.finished else { return }
                                    self.compareTypography(before, accepted, index: 0, host: self.appID)
                                    if !self.finished { self.finish() }
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
        guard key(45, flags: .maskCommand) else { return }
        after(0.1) { self.prepareEditor(attempts: 20) }
    }

    private func prepareEditor(attempts: Int) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else { finish(error: "Destination lost foreground before fixture preparation"); return }
        guard let element = focused(), read(element) == "" else {
            if attempts > 0 { after(0.1) { self.prepareEditor(attempts: attempts - 1) } }
            else { finish(error: "New document is not an empty fixture") }
            return
        }
        self.fixture = element
        guard self.type(self.token), self.key(0, flags: .maskCommand), self.key(8, flags: .maskCommand) else { return }
        self.after(0.6) {
            if CommandLine.arguments.contains("--e2e-typography") {
                self.record("typography fixture copied through the real clipboard", passed: NSPasteboard.general.string(forType: .string) == self.token)
                self.typographyCase(index: 0)
                return
            }
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

    private func typographyCase(index: Int) {
        let drafts = ["Existing text ", "Previous line\n", ""]
        guard index < drafts.count else { finish(); return }
        let draft = drafts[index]
        resetField(draft)
        if draft.isEmpty { key(51) }
        after(0.3) {
            guard self.check("typography case \(index) draft acknowledged", expected: draft), self.key(9, flags: [.maskCommand, .maskAlternate]) else { return }
            self.after(0.6) {
                guard let ghost = NSApp.windows.first(where: { $0.title == "Ditto completion" && $0.isVisible }), let view = ghost.contentView as? GhostTextView,
                      view.text == self.token, let fixture = self.fixture, let field = self.elementBounds(fixture), let selected = self.selection(fixture) else { self.finish(error: "Typography fixture has no readable ghost/field"); return }
                var range = CFRange(location: selected.location, length: 0)
                var value: CFTypeRef?
                var caret = CGRect.zero
                guard let parameter = AXValueCreate(.cfRange, &range), AXUIElementCopyParameterizedAttributeValue(fixture, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &value) == .success,
                      let value, CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetValue(value as! AXValue, .cgRect, &caret) else { self.finish(error: "Typography caret bounds unavailable"); return }
                let top = NSScreen.screens.first!.frame.maxY
                if selected.location > 0 {
                    var previous = CFRange(location: selected.location - 1, length: 1)
                    var raw: CFTypeRef?
                    var rect = CGRect.zero
                    if let p = AXValueCreate(.cfRange, &previous), AXUIElementCopyParameterizedAttributeValue(fixture, kAXBoundsForRangeParameterizedAttribute as CFString, p, &raw) == .success, let raw, CFGetTypeID(raw) == AXValueGetTypeID(), AXValueGetValue(raw as! AXValue, .cgRect, &rect) { self.results.append(["scenario": "typography case \(index) previous glyph bounds", "rect": NSStringFromRect(rect)]) }
                }
                if let marker = self.attribute(fixture, "AXSelectedTextMarkerRange") {
                    var raw: CFTypeRef?
                    var rect = CGRect.zero
                    if AXUIElementCopyParameterizedAttributeValue(fixture, "AXBoundsForTextMarkerRange" as CFString, marker, &raw) == .success, let raw, CFGetTypeID(raw) == AXValueGetTypeID(), AXValueGetValue(raw as! AXValue, .cgRect, &rect) { self.results.append(["scenario": "typography case \(index) marker bounds", "rect": NSStringFromRect(rect)]) }
                }
                let drawn = CGRect(x: ghost.frame.minX, y: top - ghost.frame.maxY, width: ghost.frame.width, height: ghost.frame.height)
                let region = CGRect(x: drawn.minX + 2, y: drawn.minY, width: min(drawn.width, field.maxX - drawn.minX - 4), height: drawn.height).intersection(field)
                self.results.append(["scenario": "typography case \(index) capture geometry", "caret": NSStringFromRect(caret), "ghost": NSStringFromRect(drawn), "field": NSStringFromRect(field), "region": NSStringFromRect(region)])
                self.record("typography case \(index) stays inside the text field", passed: field.contains(drawn))
                guard !self.finished else { return }
                self.results.append(["scenario": "typography case \(index) style", "font": view.style.font.fontName, "size": String(Double(view.style.font.pointSize)), "baseline": String(Double(view.baselineOffsetFromTop))])
                self.captureRegion(region) { before in
                    guard !self.finished, NSWorkspace.shared.frontmostApplication?.processIdentifier == self.expectedPID, self.focused().map({ CFEqual($0, fixture) }) == true, let before else { self.finish(error: "Typography capture lost fixture focus"); return }
                    guard self.key(48) else { return }
                    self.after(0.4) {
                        guard self.check("typography case \(index) accepts the same words", expected: draft + self.token) else { return }
                        guard self.key(123, flags: .maskCommand) else { return }
                        self.after(0.15) {
                            self.captureRegion(region) { accepted in
                                guard !self.finished, NSWorkspace.shared.frontmostApplication?.processIdentifier == self.expectedPID, self.focused().map({ CFEqual($0, fixture) }) == true, let accepted else { self.finish(error: "Typography reference lost fixture focus"); return }
                                for (kind, image) in [("ghost", before), ("accepted", accepted)] { try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: self.output.deletingPathExtension().appendingPathExtension("case-\(index)-\(kind).png")) }
                                self.compareTypography(before, accepted, index: index)
                                self.typographyCase(index: index + 1)
                            }
                        }
                    }
                }
            }
        }
    }

    private func elementBounds(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let extent = attribute(element, kAXSizeAttribute), CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(extent) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(extent as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func compareTypography(_ ghost: CGImage, _ accepted: CGImage, index: Int, host: String = "TextEdit") {
        func ink(_ image: CGImage) -> (CGRect, CGPoint)? {
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let bg = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) else { return nil }
            var samples: [(Int, Int, Double)] = []
            var peak = 0.0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), max(color.redComponent, color.greenComponent, color.blueComponent) - min(color.redComponent, color.greenComponent, color.blueComponent) < 0.15 else { continue }
                    let contrast = abs((color.redComponent + color.greenComponent + color.blueComponent - bg.redComponent - bg.greenComponent - bg.blueComponent) / 3)
                    peak = max(peak, contrast)
                    samples.append((x, y, contrast))
                }
            }
            guard peak > 0.1 else { return nil }
            let body = samples.filter { $0.2 > peak * 0.2 }
            guard let left = body.map(\.0).min(), let right = body.map(\.0).max(), let top = body.map(\.1).min(), let bottom = body.map(\.1).max() else { return nil }
            let mass = body.reduce(0) { $0 + $1.2 }
            return (CGRect(x: left, y: top, width: right - left, height: bottom - top), CGPoint(x: body.reduce(0) { $0 + Double($1.0) * $1.2 } / mass, y: body.reduce(0) { $0 + Double($1.1) * $1.2 } / mass))
        }
        guard let (before, first) = ink(ghost), let (after, second) = ink(accepted) else { record("typography case \(index) has measurable letter ink", passed: false); return }
        let dx = first.x - second.x, dy = first.y - second.y
        results.append(["scenario": "typography case \(index) actual ink", "dxPixels": String(Double(dx)), "dyPixels": String(Double(dy)), "widthDeltaPixels": String(Double(before.width - after.width)), "heightDeltaPixels": String(Double(before.height - after.height))])
        record("typography case \(index) matches \(host)'s accepted glyphs", passed: abs(dx) <= 0.5 && abs(dy) <= 0.5 && abs(before.width - after.width) <= 1 && abs(before.height - after.height) <= 1)
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
        if CommandLine.arguments.contains("--e2e-history-textedit") {
            historyEditorScenarios()
            return
        }
        let eventQuery = CommandLine.arguments.contains("--e2e-event-query")
        let steps: [() -> Void] = [
            { self.record("completion preserves clipboard", passed: NSPasteboard.general.string(forType: .string) == self.token); self.resetField("Fast ") },
            { self.key(9, flags: [.maskCommand, .maskAlternate]) },
            { self.type("dit"); self.key(48) },
            { _ = self.check("immediate Tab accepts current query", expected: "Fast " + self.token); self.resetField(self.token + "-first") },
            { guard self.check("first copy fixture acknowledged", expected: self.token + "-first") else { return }; self.key(0, flags: .maskCommand) },
            { self.results.append(["scenario": "first selection diagnostic", "selection": self.fixture.flatMap(self.selection).map(NSStringFromRange) ?? "unavailable", "focusedFixture": String(self.focused().map { current in self.fixture.map { CFEqual(current, $0) } ?? false } ?? false)]); self.record("first copy selection acknowledged", passed: self.fixture.flatMap(self.selection) == NSRange(location: 0, length: (self.token + "-first").utf16.count)); self.key(8, flags: .maskCommand) },
            { self.record("first copy reached clipboard", passed: NSPasteboard.general.string(forType: .string) == self.token + "-first"); self.resetField(self.token + "-second") },
            { guard self.check("second copy fixture acknowledged", expected: self.token + "-second") else { return }; self.key(0, flags: .maskCommand) },
            { self.record("second copy selection acknowledged", passed: self.fixture.flatMap(self.selection) == NSRange(location: 0, length: (self.token + "-second").utf16.count)); self.key(8, flags: .maskCommand) },
            { self.record("second copy reached clipboard", passed: NSPasteboard.general.string(forType: .string) == self.token + "-second"); self.resetField("Cycle ") },
            { self.key(9, flags: [.maskCommand, .maskAlternate]) },
            { self.type(self.token) },
            { self.key(125) },
            { self.key(48) },
            { _ = self.check("cycle chooses older matching item", expected: "Cycle " + self.token + "-first"); self.record("cycling preserves clipboard", passed: NSPasteboard.general.string(forType: .string) == self.token + "-second"); self.resetField("History ") },
            { self.key(9, flags: [.maskCommand, .maskAlternate]) },
            { self.type("dit") },
            { self.key(37, flags: .maskCommand) },
            { self.type("no-such-history-filter") },
            { self.key(53) },
            { _ = self.check("history Escape preserves original host query", expected: "History dit"); self.key(48) },
            { _ = self.check("autocomplete resumes after discarded history filter", expected: "History " + self.token + "-second"); self.resetField("History ") },
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

    private func historyEditorScenarios() {
        let steps: [() -> Void] = [
            { self.resetField("History ") },
            { guard self.check("history host fixture acknowledged", expected: "History ") else { return }; self.key(9, flags: [.maskCommand, .maskAlternate]) },
            { self.type("dit") },
            { self.key(37, flags: .maskCommand) },
            { self.record("redesigned history opens explicitly", passed: NSApp.windows.contains { $0.isVisible && $0.level == .floating && $0.canBecomeKey }); self.type("-no-such-filter") },
            { self.key(36) },
            { guard self.check("no-result Return leaves host unchanged", expected: "History dit") else { return }; self.key(53) },
            { guard self.check("history Escape preserves host query", expected: "History dit") else { return }; self.key(48) },
            { guard self.check("autocomplete resumes for original host query", expected: "History " + self.token) else { return }; self.resetField("History ") },
            { self.key(9, flags: [.maskCommand, .maskAlternate]) },
            { self.type("dit") },
            { self.key(37, flags: .maskCommand) },
            { self.type(String(self.token.dropFirst(3))) },
            { self.key(36) },
            { guard self.check("redesigned history pastes into TextEdit", expected: "History " + self.token) else { return }; self.key(6, flags: .maskCommand) },
            { _ = self.check("history paste preserves one-step undo", expected: "History dit") }
        ]
        runSteps(steps) { self.finish() }
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
        record("inline ghost has nonzero compact size", passed: window.frame.height > 0 && window.frame.height < 80 && window.frame.width > 20)
        let texts = (content as? GhostTextView).map { [$0.text] } ?? []
        guard texts.first == token else { record("ghost suggests fresh clipboard item", passed: false); return }
        record("ghost suggests fresh clipboard item", passed: true)
        if appID == "com.apple.TextEdit", let fixture, read(fixture) == "External ",
           let label = content as? GhostTextView, let selection = selection(fixture) {
            var range = CFRange(location: selection.location - 1, length: 1)
            var value: CFTypeRef?
            var caret = CGRect.zero
            guard let parameter = AXValueCreate(.cfRange, &range),
                  AXUIElementCopyParameterizedAttributeValue(fixture, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &value) == .success,
                  let value, CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetValue(value as! AXValue, .cgRect, &caret), caret.height > 0 else {
                record("populated field exposes adjacent glyph bounds", passed: false); return
            }
            let labelRect = window.convertToScreen(label.convert(label.bounds, to: nil))
            let top = NSScreen.screens.first!.frame.maxY
            let offset = labelRect.midY - (top - caret.midY)
            results.append(["scenario": "populated-field adjacent-glyph geometry", "verticalOffset": String(Double(offset)), "caretHeight": String(Double(caret.height))])
            record("initial populated-field suggestion shares the preceding glyph line", passed: abs(offset) <= 4)
            guard !finished else { return }
        }
        let font = (content as? GhostTextView)?.style.font
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
                    results.append(["scenario": "placeholder geometry", "role": attribute(sibling, kAXRoleAttribute) as? String ?? "unknown", "rect": NSStringFromRect(CGRect(origin: point, size: dimensions))])
                    if attribute(sibling, kAXRoleAttribute) as? String == kAXStaticTextRole,
                       let fieldPosition = attribute(element, kAXPositionAttribute), let fieldSize = attribute(element, kAXSizeAttribute) {
                        var origin = CGPoint.zero
                        var extent = CGSize.zero
                        AXValueGetValue(fieldPosition as! AXValue, .cgPoint, &origin)
                        AXValueGetValue(fieldSize as! AXValue, .cgSize, &extent)
                        chatPlaceholder = CGRect(origin: point, size: dimensions)
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
                guard self.type("di") else { return }
                self.after(0.2) {
                    guard self.check("typed query acknowledged before Escape", expected: "Keep di"), self.key(53) else { return }
                    self.after(0.2) {
                        guard self.check("Escape leaves typed query unchanged", expected: "Keep di"), self.key(48) else { return }
                        self.after(0.2) { self.finishEscapeScenario() }
                    }
                }
            }
        }
    }

    private func finishEscapeScenario() {
        guard check("escape preserves typing", expected: "Keep di\t") else { return }
        resetField("Switch ")
        after(0.2) {
            guard self.key(9, flags: [.maskCommand, .maskAlternate]) else { return }
            self.after(0.2) {
                guard self.type("dit") else { return }
                self.after(0.2) { self.switchAppScenario(expectedSource: "Switch dit") }
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
        if isChatComposer || CommandLine.arguments.contains("--e2e-typography"), let fixture {
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
        if isChatComposer || CommandLine.arguments.contains("--e2e-typography"), let fixture {
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
