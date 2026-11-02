import AppKit
import Carbon
import DittoCore

final class ClipboardCapture {
    private let store: HistoryStore
    private let preferences: Preferences
    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount
    private var lastPrune = Date.distantPast
    var onChange: (() -> Void)?
    var onStatus: ((String) -> Void)?

    init(store: HistoryStore, preferences: Preferences) {
        self.store = store
        self.preferences = preferences
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.poll() }
    }

    func enableByUser() {
        preferences.captureEnabled = true
        // This read is explicitly requested by the onboarding button, not a background permission prompt.
        let board = NSPasteboard.general
        if #available(macOS 15.4, *), board.accessBehavior == .alwaysDeny {
            onStatus?("Clipboard access is denied. Allow Ditto in System Settings to enable capture.")
            return
        }
        _ = board.string(forType: .string)
        lastChange = board.changeCount - 1
        poll()
    }

    func poll() {
        let board = NSPasteboard.general
        let changed = board.changeCount != lastChange
        if changed { lastChange = board.changeCount; onChange?() }
        if Date().timeIntervalSince(lastPrune) > 60 {
            do { try store.prune(retentionDays: preferences.retentionDays); lastPrune = Date() }
            catch { onStatus?("History cleanup failed: \(error.localizedDescription)") }
        }
        guard preferences.captureEnabled else { return }
        if #available(macOS 15.4, *), board.accessBehavior != .alwaysAllow {
            lastChange = board.changeCount
            onStatus?("Allow background clipboard access for Ditto in System Settings, then enable capture in Setup.")
            return
        }
        guard changed else { return }
        guard !IsSecureEventInputEnabled() else { return }
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier ?? ""
        let types = Set((board.types ?? []).map(\.rawValue))
        guard InputPolicy.allowsCapture(types: types, bundleID: bundleID, excluded: preferences.exclusions, paused: false),
              let text = board.string(forType: .string) else { return }
        do {
            try store.capture(text: text, source: app?.localizedName ?? "Unknown", bundleID: bundleID)
            try store.prune(retentionDays: preferences.retentionDays)
            onStatus?("Clipboard capture is on")
        } catch { onStatus?("Could not save clipboard item: \(error.localizedDescription)") }
    }

    deinit { timer?.invalidate() }
}
