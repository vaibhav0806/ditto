import AppKit

public enum PasteboardLeaseError: Error { case unavailable, changed, tooLarge }

public final class PasteboardLease {
    private let board: NSPasteboard
    private let original: [NSPasteboardItem]
    private var ownedChange: Int?
    private let originalChange: Int
    private let onWrite: (Int) -> Void

    public init(board: NSPasteboard = .general, onWrite: @escaping (Int) -> Void = { _ in }) throws {
        self.board = board
        self.onWrite = onWrite
        let before = board.changeCount
        var items: [NSPasteboardItem] = []
        var total = 0
        for item in board.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type) else { throw PasteboardLeaseError.unavailable }
                total += data.count
                guard total <= 32 * 1_048_576 else { throw PasteboardLeaseError.tooLarge }
                copy.setData(data, forType: type)
            }
            items.append(copy)
        }
        guard board.changeCount == before else { throw PasteboardLeaseError.changed }
        original = items
        originalChange = before
    }

    @discardableResult public func write(_ text: String) -> Bool {
        guard board.changeCount == originalChange else { return false }
        board.clearContents()
        board.setString(text, forType: .string)
        ownedChange = board.changeCount
        onWrite(board.changeCount)
        return true
    }

    @discardableResult public func restoreIfUnchanged() -> Bool {
        guard let ownedChange, board.changeCount == ownedChange else { return false }
        board.clearContents()
        if !original.isEmpty { board.writeObjects(original) }
        self.ownedChange = nil
        onWrite(board.changeCount)
        return true
    }
}
