import Combine
import DittoCore

public final class OverlayModel: ObservableObject {
    @Published public var history = false
    @Published public var query = ""
    @Published public var entries: [ClipboardEntry] = []
    @Published public var selectedIndex = 0
    @Published public var message = ""
    @Published public var canInsert = false
    @Published public var canReturnToCompletion = false
    @Published public var destinationName = ""
    @Published public var destinationBundleID = ""
    public var selected: ClipboardEntry? { entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil }
    public var onQuery: ((String) -> Void)?
    public var onMove: ((Int) -> Void)?
    public var onAccept: (() -> Void)?
    public var onEscape: (() -> Void)?
    public var onPick: ((Int) -> Void)?
    public var onPin: (() -> Void)?
    public var onDelete: (() -> Void)?
    public var onCopy: (() -> Void)?
    public init() {}
}

