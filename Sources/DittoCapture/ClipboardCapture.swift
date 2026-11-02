import AppKit
import Carbon
import DittoCore

public final class ClipboardCapture {
    private let store: HistoryStore
    private let board: NSPasteboard
    private let enabled: () -> Bool
    private let retentionDays: () -> Int
    private let exclusions: () -> Set<String>
    private let secureInput: () -> Bool
    private let source: () -> (String, String)
    private var timer: Timer?
    private var lastChange: Int
    private var lastPrune = Date.distantPast
    private var ignoredChanges: Set<Int> = []
    public var onChange: (() -> Void)?
    public var onStatus: ((String) -> Void)?

    public init(store: HistoryStore, board: NSPasteboard = .general, enabled: @escaping () -> Bool,
                retentionDays: @escaping () -> Int, exclusions: @escaping () -> Set<String>,
                secureInput: @escaping () -> Bool = { IsSecureEventInputEnabled() },
                source: @escaping () -> (String, String) = {
                    let app = NSWorkspace.shared.frontmostApplication
                    return (app?.localizedName ?? "Unknown", app?.bundleIdentifier ?? "")
                }) {
        self.store = store
        self.board = board
        self.enabled = enabled
        self.retentionDays = retentionDays
        self.exclusions = exclusions
        self.secureInput = secureInput
        self.source = source
        lastChange = board.changeCount
    }

    public func start() {
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.poll() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    public func enableByUser() {
        // This read is explicitly requested by the onboarding button, not a background permission prompt.
        if #available(macOS 15.4, *), board.accessBehavior == .alwaysDeny {
            onStatus?("Clipboard access is denied. Allow Ditto in System Settings to enable capture.")
            return
        }
        _ = board.string(forType: .string)
        lastChange = board.changeCount - 1
        poll()
    }

    public func ignore(changeCount: Int) { ignoredChanges.insert(changeCount) }

    public func poll() {
        let changed = board.changeCount != lastChange
        if changed {
            lastChange = board.changeCount
            let ownWrite = ignoredChanges.contains(lastChange)
            ignoredChanges = Set(ignoredChanges.filter { $0 > lastChange })
            if ownWrite { return }
            onChange?()
        }
        if Date().timeIntervalSince(lastPrune) > 60 {
            do { try store.prune(retentionDays: retentionDays()); lastPrune = Date() }
            catch { onStatus?("History cleanup failed: \(error.localizedDescription)") }
        }
        guard enabled() else { return }
        if #available(macOS 15.4, *), !InputPolicy.permitsBackgroundRead(access: board.accessBehavior.rawValue) {
            lastChange = board.changeCount
            onStatus?("Allow background clipboard access for Ditto in System Settings, then enable capture in Setup.")
            return
        }
        guard changed else { return }
        guard !secureInput() else { return }
        let (sourceName, bundleID) = source()
        let types = Set((board.types ?? []).map(\.rawValue))
        guard InputPolicy.allowsCapture(types: types, bundleID: bundleID, excluded: exclusions(), paused: false),
              let text = board.string(forType: .string) else { return }
        do {
            try store.capture(text: text, source: sourceName, bundleID: bundleID)
            try store.prune(retentionDays: retentionDays())
            onStatus?("Clipboard capture is on")
        } catch { onStatus?("Could not save clipboard item: \(error.localizedDescription)") }
    }

    deinit { timer?.invalidate() }
}
