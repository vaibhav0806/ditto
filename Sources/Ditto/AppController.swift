import AppKit
import SwiftUI
import Carbon
import Combine
import DittoCore

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var store: HistoryStore!
    private let preferences: Preferences
    private let setupModel = SetupModel()
    private let shortcut = GlobalShortcut()
    private let keyboard = KeyboardMonitor()
    private let overlay = OverlayController()
    private var capture: ClipboardCapture!
    private var target: TextTarget?
    private var session: CompletionSession?
    private var candidates: [ClipboardEntry] = []
    private var browsing = false
    private var generation = UUID()
    private var pollTimer: Timer?
    private var invalidSnapshots = 0
    private var setupWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var practiceWindow: NSWindow?
    private var activationObserver: NSObjectProtocol?
    private var lockObserver: NSObjectProtocol?
    private var subscriptions: Set<AnyCancellable> = []
    private let smoke = CommandLine.arguments.contains("--smoke-test")
    private var smokeDirectory: URL?

    override init() {
        preferences = Preferences(defaults: CommandLine.arguments.contains("--smoke-test") ? UserDefaults(suiteName: "Ditto.Smoke.\(UUID().uuidString)")! : .standard)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do {
            let directory: URL
            if smoke {
                directory = FileManager.default.temporaryDirectory.appendingPathComponent("Ditto-Smoke-\(UUID().uuidString)")
                smokeDirectory = directory
            } else {
                directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Ditto", isDirectory: true)
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            store = try HistoryStore(url: directory.appendingPathComponent("history.sqlite"))
            try store.prune(retentionDays: preferences.retentionDays)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Ditto could not open local history"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        installMenu()
        wireOverlay()
        capture = ClipboardCapture(store: store, preferences: preferences)
        capture.onChange = { [weak self] in self?.cancel() }
        capture.onStatus = { [weak self] in self?.setupModel.status = $0 }
        if !smoke { capture.start() }
        shortcut.onInvoke = { [weak self] in self?.invoke() }
        if !smoke && !shortcut.start() { setupModel.status = "⌥⌘V could not be registered. Another app may own this shortcut." }
        keyboard.onKey = { [weak self] in self?.handleKey($0) ?? false }
        keyboard.onClick = { [weak self] in
            guard let self, self.session != nil, !self.browsing else { return }
            DispatchQueue.main.async { self.cancel() }
        }
        keyboard.onDisabled = { [weak self] in DispatchQueue.main.async { self?.cancel() } }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, self.session != nil else { return }
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.processIdentifier != self.target?.pid && app?.processIdentifier != ProcessInfo.processInfo.processIdentifier { self.cancel() }
        }
        lockObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.cancel() }
        preferences.$captureEnabled.dropFirst().sink { [weak self] _ in self?.cancel() }.store(in: &subscriptions)
        preferences.$retentionDays.dropFirst().sink { [weak self] days in
            do { try self?.store.prune(retentionDays: days) } catch { self?.setupModel.status = error.localizedDescription }
        }.store(in: &subscriptions)
        preferences.$excludedApps.dropFirst().sink { [weak self] _ in self?.cancel() }.store(in: &subscriptions)
        if smoke {
            showSetup()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                print("Ditto smoke: launched; menu=ready; setup=\(self?.setupWindow?.isVisible == true); capture=off; accessibility=\(AXIsProcessTrusted())")
                NSApp.terminate(nil)
            }
        } else if !preferences.captureEnabled || !AXIsProcessTrusted() { showSetup() }
    }

    private func installMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Ditto")
        statusItem.button?.toolTip = "Ditto · ⌥⌘V"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: preferences.captureEnabled ? "Ditto · Capture on" : "Ditto · Capture paused", action: nil, keyEquivalent: "")
        menu.addItem(status)
        add("Open History", action: #selector(menuHistory), to: menu)
        add(preferences.captureEnabled ? "Pause Capture" : "Enable Capture…", action: #selector(toggleCapture), to: menu)
        menu.addItem(.separator())
        add("Setup & Permissions…", action: #selector(showSetup), to: menu)
        add("Practice…", action: #selector(showPractice), to: menu)
        add("Settings…", action: #selector(showSettings), to: menu)
        menu.addItem(.separator())
        add("Quit Ditto", action: #selector(quit), to: menu)
    }

    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func menuHistory() { invoke(openList: true) }
    @objc private func toggleCapture() {
        if preferences.captureEnabled { preferences.captureEnabled = false } else { showSetup() }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func invoke(openList: Bool = false) {
        cancel()
        guard !IsSecureEventInputEnabled() else { return }
        guard !preferences.exclusions.contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "") else { return }
        do { try store.prune(retentionDays: preferences.retentionDays); candidates = try store.entries() }
        catch { setupModel.status = error.localizedDescription; showSetup(); return }
        if AXIsProcessTrusted(), let target = TextTarget.focused(), let snapshot = target.snapshot(), target.supportsReplacement,
           let session = CompletionSession(text: snapshot.text, selection: snapshot.selection) {
            self.target = target
            self.session = session
        }
        if openList || session == nil {
            expandHistory()
            return
        }
        guard keyboard.start() else {
            cancel()
            setupModel.status = "Session keyboard access is unavailable. Check Accessibility / Input Monitoring, then retry."
            showSetup()
            return
        }
        overlay.model.canInsert = true
        overlay.model.message = ""
        updateResults(query: "")
        overlay.show(history: false, caret: target?.caret)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in self?.refreshSession() }
    }

    private func handleKey(_ event: CGEvent) -> Bool {
        guard session != nil, !browsing else { return false }
        let flags = event.flags
        let action = InputPolicy.key(code: Int(event.getIntegerValueField(.keyboardEventKeycode)), command: flags.contains(.maskCommand), option: flags.contains(.maskAlternate), control: flags.contains(.maskControl), shift: flags.contains(.maskShift), hasCandidate: overlay.model.selected != nil)
        // Do not make AX calls or perform a text mutation from the event-tap callback.
        let token = generation
        switch action {
        case .accept:
            DispatchQueue.main.async { [weak self] in if self?.generation == token { self?.accept() } }
            return true
        case .move(let delta):
            DispatchQueue.main.async { [weak self] in if self?.generation == token { self?.move(delta) } }
            return true
        case .history:
            DispatchQueue.main.async { [weak self] in if self?.generation == token { self?.expandHistory() } }
            return true
        case .dismiss, .cancelAndPass:
            DispatchQueue.main.async { [weak self] in if self?.generation == token { self?.cancel() } }
            return action == .dismiss
        case .typeNormally:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in if self?.generation == token { self?.refreshSession() } }
            return false
        }
    }

    @discardableResult
    private func refreshSession() -> Bool {
        guard !browsing, var session, let target else { return false }
        guard !IsSecureEventInputEnabled(), target.isFocused() else { cancel(); return false }
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(), let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) {
            let type = Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
            if type == kTISTypeKeyboardInputMode as String { cancel(); return false }
        }
        guard let snapshot = target.snapshot(), session.observe(text: snapshot.text, selection: snapshot.selection) else {
            invalidSnapshots += 1
            if invalidSnapshots >= 2 { cancel() }
            return false
        }
        invalidSnapshots = 0
        if session.query != self.session?.query {
            self.session = session
            updateResults(query: session.query)
        }
        return true
    }

    private func updateResults(query: String) {
        let oldID = query == overlay.model.query ? overlay.model.selected?.id : nil
        overlay.model.query = query
        overlay.model.entries = CompletionMatcher.matches(candidates, query: query)
        overlay.model.selectedIndex = overlay.model.entries.firstIndex(where: { $0.id == oldID }) ?? 0
    }

    private func move(_ delta: Int) {
        let count = overlay.model.entries.count
        guard count > 0 else { return }
        overlay.model.selectedIndex = (overlay.model.selectedIndex + delta + count) % count
    }

    private func expandHistory() {
        if session != nil, !refreshSession() { cancel(); return }
        if let session {
            guard let target, target.isFocused(), let snapshot = target.snapshot(),
                  session.validates(text: snapshot.text, selection: snapshot.selection) else { cancel(); return }
        }
        browsing = true
        keyboard.stop()
        pollTimer?.invalidate()
        pollTimer = nil
        overlay.model.canInsert = session != nil
        overlay.model.message = session == nil ? "This field does not expose safe text replacement. Copy an item, then paste it with ⌘V." : "Typing here filters history; your destination text stays unchanged."
        updateResults(query: session?.query ?? "")
        overlay.show(history: true, caret: target?.caret)
    }

    private func accept() {
        if !browsing, !refreshSession() { cancel(); return }
        guard let item = overlay.model.selected else { return }
        guard let session, let target else { copySelected(); return }
        let wasBrowsing = browsing
        cancel()
        let token = generation
        if wasBrowsing {
            guard let app = NSRunningApplication(processIdentifier: target.pid) else { return }
            app.activate(options: [.activateIgnoringOtherApps])
            finishInsertion(item: item, target: target, session: session, token: token, attempts: 8)
        } else {
            if !target.replace(session: session, with: item.text) { insertionFailed() }
        }
    }

    private func finishInsertion(item: ClipboardEntry, target: TextTarget, session: CompletionSession, token: UUID, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self, self.generation == token else { return }
            if target.isFocused() {
                if !target.replace(session: session, with: item.text) { self.insertionFailed() }
            } else if attempts > 0 {
                self.finishInsertion(item: item, target: target, session: session, token: token, attempts: attempts - 1)
            } else { self.insertionFailed() }
        }
    }

    private func insertionFailed() {
        setupModel.status = "Paste cancelled: the destination changed or did not allow replacement. Open History and use Copy instead."
        showSetup()
    }

    private func copySelected() {
        guard let item = overlay.model.selected else { return }
        cancel()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
    }

    private func escapeHistory() {
        guard browsing else { cancel(); return }
        guard session != nil, let target else { cancel(); return }
        browsing = false
        overlay.hide()
        NSRunningApplication(processIdentifier: target.pid)?.activate(options: [.activateIgnoringOtherApps])
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.generation == token, let session = self.session,
                  target.isFocused(), let snapshot = target.snapshot(), session.validates(text: snapshot.text, selection: snapshot.selection), self.keyboard.start() else { self?.cancel(); return }
            self.overlay.model.message = ""
            self.updateResults(query: session.query)
            self.overlay.show(history: false, caret: target.caret)
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in self?.refreshSession() }
        }
    }

    private func wireOverlay() {
        overlay.model.onQuery = { [weak self] in self?.updateResults(query: $0) }
        overlay.model.onMove = { [weak self] in self?.move($0) }
        overlay.model.onAccept = { [weak self] in self?.accept() }
        overlay.model.onEscape = { [weak self] in self?.escapeHistory() }
        overlay.model.onPick = { [weak self] index in self?.overlay.model.selectedIndex = index }
        overlay.model.onCopy = { [weak self] in self?.copySelected() }
        overlay.model.onPin = { [weak self] in
            guard let self, let item = self.overlay.model.selected else { return }
            self.modifyHistory { try self.store.setPinned(id: item.id, pinned: !item.pinned) }
        }
        overlay.model.onDelete = { [weak self] in
            guard let self, let item = self.overlay.model.selected else { return }
            self.modifyHistory { try self.store.delete(id: item.id) }
        }
        overlay.onResign = { [weak self] in if self?.browsing == true { self?.cancel() } }
    }

    private func modifyHistory(_ mutation: () throws -> Void) {
        do {
            try mutation()
            candidates = try store.entries()
            updateResults(query: overlay.model.query)
        } catch { overlay.model.message = error.localizedDescription }
    }

    private func cancel() {
        generation = UUID()
        browsing = false
        session = nil
        target = nil
        candidates = []
        pollTimer?.invalidate()
        pollTimer = nil
        keyboard.stop()
        overlay.hide()
        invalidSnapshots = 0
    }

    @objc private func showSetup() {
        cancel()
        setupModel.refresh()
        if setupWindow == nil {
            setupWindow = window(title: "Ditto · Setup", view: SetupView(model: setupModel, preferences: preferences, enableCapture: { [weak self] in self?.capture.enableByUser() }, openPractice: { [weak self] in self?.showPractice() }, openHistory: { [weak self] in self?.menuHistory() }))
        }
        present(setupWindow!)
    }

    @objc private func showSettings() {
        cancel()
        if settingsWindow == nil {
            settingsWindow = window(title: "Ditto · Settings", view: SettingsView(preferences: preferences, onClear: { [weak self] in self?.clearHistory() }))
        }
        present(settingsWindow!)
    }

    private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear all clipboard history?"
        alert.informativeText = "This removes saved and pinned items from Ditto. Your current clipboard stays unchanged."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Clear History")
        if alert.runModal() == .alertSecondButtonReturn {
            do { try store.clear() } catch { setupModel.status = error.localizedDescription }
        }
    }

    @objc private func showPractice() {
        cancel()
        if practiceWindow == nil {
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 300))
            let text = NSTextView(frame: scroll.bounds)
            text.isRichText = false
            text.isEditable = true
            text.allowsUndo = true
            text.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
            text.textContainerInset = NSSize(width: 24, height: 24)
            text.string = "Ditto practice\n\nCopy some text, put your cursor below, and press ⌥⌘V.\nType to filter, Tab to paste, Esc to close.\n\n"
            text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0))
            scroll.documentView = text
            scroll.hasVerticalScroller = true
            let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Ditto · Practice"
            window.contentView = scroll
            window.isReleasedWhenClosed = false
            practiceWindow = window
            window.makeFirstResponder(text)
        }
        present(practiceWindow!)
    }

    private func window<V: View>(title: String, view: V) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = title
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(window.contentView!.fittingSize)
        window.isReleasedWhenClosed = false
        return window
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        cancel()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        if let lockObserver { NSWorkspace.shared.notificationCenter.removeObserver(lockObserver) }
        if let smokeDirectory { try? FileManager.default.removeItem(at: smokeDirectory) }
    }
}
