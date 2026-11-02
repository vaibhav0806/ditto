import AppKit
import DittoCapture
import OSLog

final class PasteTransaction {
    private let logger = Logger(subsystem: "com.vaibhav0806.ditto", category: "Paste")
    private let target: TextTarget
    private let expectedPrefix: String
    private let expectedSuffix: String
    private let lease: PasteboardLease
    private let completion: (Bool) -> Void
    private let deadline = Date().addingTimeInterval(1.5)

    init(target: TextTarget, text: String, before: TextSnapshot, range: NSRange, onWrite: @escaping (Int) -> Void, completion: @escaping (Bool) -> Void) throws {
        self.target = target
        let value = before.text as NSString
        expectedPrefix = value.substring(to: range.location) + text
        expectedSuffix = value.substring(from: range.location + range.length)
        lease = try PasteboardLease(onWrite: onWrite)
        self.completion = completion
    }

    func start(text: String, before: TextSnapshot, selection: NSRange) {
        guard target.isFocused(), let snapshot = target.snapshot(),
              snapshot.text.utf16.elementsEqual(before.text.utf16), snapshot.selection == selection,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { completion(false); return }
        guard lease.write(text) else { completion(false); return }
        down.flags = .maskCommand
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        logger.notice("Paste dispatched")
        observeReceipt()
    }

    private func observeReceipt() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            if let snapshot = self.target.snapshot(),
               snapshot.text.utf16.count >= self.expectedPrefix.utf16.count + self.expectedSuffix.utf16.count,
               snapshot.text.utf16.starts(with: self.expectedPrefix.utf16),
               snapshot.text.utf16.suffix(self.expectedSuffix.utf16.count).elementsEqual(self.expectedSuffix.utf16) {
                let restored = self.lease.restoreIfUnchanged()
                self.logger.notice("Paste acknowledged; original clipboard restored=\(restored)")
                self.completion(true)
            } else if Date() < self.deadline {
                self.observeReceipt()
            } else {
                // No receipt: leave the chosen item available for manual paste. Never replay a mutation.
                self.logger.notice("Paste acknowledgement timed out; not replaying input")
                self.completion(false)
            }
        }
    }
}
