import AppKit
import ApplicationServices
import Carbon
import DittoCore
import OSLog

struct TextSnapshot {
    let text: String
    let selection: NSRange
}

struct TextTarget {
    private let element: AXUIElement?
    private let nativeView: NSTextView?
    let pid: pid_t
    var isNative: Bool { nativeView != nil }
    var caret: CGRect? { caretBounds() }
    var placeholderRegion: CGRect? {
        guard snapshot()?.text.isEmpty == true, let caret else { return nil }
        let frame: CGRect
        if let nativeView, let window = nativeView.window {
            let rect = window.convertToScreen(nativeView.convert(nativeView.bounds, to: nil))
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            frame = CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
        } else if let element, let position = Self.attribute(element, kAXPositionAttribute), let size = Self.attribute(element, kAXSizeAttribute),
                  CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
            var point = CGPoint.zero
            var dimensions = CGSize.zero
            guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
            frame = CGRect(origin: point, size: dimensions)
        } else { return nil }
        return PlaceholderMask.region(field: frame, caret: caret)
    }
    var font: NSFont {
        if let font = nativeView?.font { return font }
        if let element, let snapshot = snapshot(), !snapshot.text.isEmpty,
           let caret = Range(NSRange(location: snapshot.selection.location, length: 0), in: snapshot.text)?.lowerBound {
            let start = caret == snapshot.text.startIndex ? caret : snapshot.text.index(before: caret)
            let end = caret == snapshot.text.startIndex ? snapshot.text.index(after: start) : caret
            let range = NSRange(start..<end, in: snapshot.text)
            var cfRange = CFRange(location: range.location, length: range.length)
            var value: CFTypeRef?
            if let parameter = AXValueCreate(.cfRange, &cfRange),
               AXUIElementCopyParameterizedAttributeValue(element, kAXAttributedStringForRangeParameterizedAttribute as CFString, parameter, &value) == .success,
               let attributed = value as? NSAttributedString, attributed.length > 0 {
                if let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont { return font }
                let key = NSAttributedString.Key(kAXFontTextAttribute.takeUnretainedValue() as String)
                if let info = attributed.attribute(key, at: 0, effectiveRange: nil) as? [String: Any],
                   let name = info[kAXFontNameKey.takeUnretainedValue() as String] as? String,
                   let size = info[kAXFontSizeKey.takeUnretainedValue() as String] as? NSNumber,
                   let font = NSFont(name: name, size: CGFloat(size.doubleValue)) { return font }
            }
        }
        return .systemFont(ofSize: 14)
    }

    static func focused() -> TextTarget? {
        if NSApp.isActive, let text = NSApp.keyWindow?.firstResponder as? NSTextView,
           text.identifier?.rawValue == "DittoPracticeEditor" {
            return TextTarget(element: nil, nativeView: text, pid: ProcessInfo.processInfo.processIdentifier)
        }
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        guard let value = attribute(system, kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)
        guard attribute(element, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
              attribute(element, kAXRoleAttribute) as? String != kAXSecureTextFieldSubrole else { return nil }
        let role = attribute(element, kAXRoleAttribute) as? String
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role ?? "") else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return TextTarget(element: element, nativeView: nil, pid: pid)
    }

    var supportsReplacement: Bool {
        if let nativeView { return nativeView.isEditable }
        guard let element else { return false }
        var range = DarwinBoolean(false)
        return CGPreflightPostEventAccess()
            && AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success && range.boolValue
    }

    func snapshot() -> TextSnapshot? {
        if let nativeView { return TextSnapshot(text: nativeView.string, selection: nativeView.selectedRange()) }
        guard let element, let text = Self.attribute(element, kAXValueAttribute) as? String,
              text.utf16.count <= 100_000,
              let raw = Self.attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return TextSnapshot(text: text, selection: NSRange(location: range.location, length: range.length))
    }

    func caretBounds() -> CGRect? {
        if let nativeView {
            let rect = nativeView.firstRect(forCharacterRange: nativeView.selectedRange(), actualRange: nil)
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            return CGRect(x: rect.minX, y: top - rect.maxY, width: max(1, rect.width), height: rect.height)
        }
        guard let element else { return nil }
        var range = CFRange(location: snapshot()?.selection.location ?? 0, length: 0)
        var bounds: CFTypeRef?
        var rect = CGRect.zero
        if let value = AXValueCreate(.cfRange, &range),
           AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, value, &bounds) == .success,
           let bounds, CFGetTypeID(bounds) == AXValueGetTypeID(),
           AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.height > 0 {
            return rect
        }
        if let marker = Self.attribute(element, "AXSelectedTextMarkerRange"),
           AXUIElementCopyParameterizedAttributeValue(element, "AXBoundsForTextMarkerRange" as CFString, marker, &bounds) == .success,
           let bounds, CFGetTypeID(bounds) == AXValueGetTypeID(),
           AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.height > 0 {
            return rect
        }
        if range.location > 0 {
            range.location -= 1
            range.length = 1
            if let value = AXValueCreate(.cfRange, &range),
               AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, value, &bounds) == .success,
               let bounds, CFGetTypeID(bounds) == AXValueGetTypeID(),
               AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.height > 0 {
                return CGRect(x: rect.maxX, y: rect.minY, width: 0, height: rect.height)
            }
        }
        return nil
    }

    func isFocused() -> Bool {
        if let nativeView { return NSApp.isActive && NSApp.keyWindow?.firstResponder === nativeView }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let current = Self.focused(), let currentElement = current.element, let element else { return false }
        return current.pid == pid && CFEqual(currentElement, element)
    }

    func replace(session: CompletionSession, with text: String, onClipboardWrite: @escaping (Int) -> Void, completion: @escaping (Bool) -> Void) {
        if session.isKeystrokeTracked {
            guard isFocused(), !IsSecureEventInputEnabled(), CGPreflightPostEventAccess(),
                  let suffix = session.insertionSuffix(for: text) else { completion(false); return }
            if suffix.isEmpty { completion(true); return }
            if let snapshot = snapshot(), snapshot.selection.length == 0,
               snapshot.selection.location > 0 || snapshot.text.isEmpty,
               snapshot.selection.location >= session.query.utf16.count,
               let queryRange = Range(NSRange(location: snapshot.selection.location - session.query.utf16.count, length: session.query.utf16.count), in: snapshot.text),
               snapshot.text[queryRange].utf16.elementsEqual(session.query.utf16) {
                do {
                    let transaction = try PasteTransaction(target: self, text: suffix, before: snapshot, range: snapshot.selection, onWrite: onClipboardWrite, completion: completion)
                    transaction.start(text: suffix, before: snapshot, selection: snapshot.selection)
                } catch { completion(false) }
                return
            }
            guard let events = SyntheticInput.events(for: suffix) else { completion(false); return }
            for event in events { event.post(tap: .cghidEventTap) }
            completion(true)
            return
        }
        guard isFocused(), supportsReplacement, let snapshot = snapshot(),
              session.validates(text: snapshot.text, selection: snapshot.selection) else { completion(false); return }
        if text.utf16.elementsEqual(session.query.utf16) { completion(true); return }
        if let nativeView {
            nativeView.breakUndoCoalescing()
            nativeView.insertText(text, replacementRange: session.replacementRange)
            nativeView.breakUndoCoalescing()
            completion(true)
            return
        }
        guard let element else { completion(false); return }
        var range = CFRange(location: session.replacementRange.location, length: session.replacementRange.length)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success else { completion(false); return }
        awaitSelection(before: snapshot, range: session.replacementRange, deadline: Date().addingTimeInterval(0.6)) { ready in
            guard ready else { completion(false); return }
            do {
                let transaction = try PasteTransaction(target: self, text: text, before: snapshot, range: session.replacementRange, onWrite: onClipboardWrite, completion: completion)
                transaction.start(text: text, before: snapshot, selection: session.replacementRange)
            } catch {
                Logger(subsystem: "com.vaibhav0806.ditto", category: "Paste").notice("Clipboard snapshot failed: \(String(describing: error), privacy: .public)")
                completion(false)
            }
        }
    }

    private func awaitSelection(before: TextSnapshot, range: NSRange, deadline: Date, completion: @escaping (Bool) -> Void) {
        guard isFocused(), let current = snapshot(), current.text.utf16.elementsEqual(before.text.utf16) else {
            completion(false)
            return
        }
        if current.selection == range {
            completion(true)
        } else if Date() < deadline {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                self.awaitSelection(before: before, range: range, deadline: deadline, completion: completion)
            }
        } else {
            Logger(subsystem: "com.vaibhav0806.ditto", category: "Paste").notice("Selection was not acknowledged; cancelling before paste")
            completion(false)
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
