import AppKit
import ApplicationServices
import DittoCore

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
    var font: NSFont { nativeView?.font ?? .systemFont(ofSize: 14) }

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
        guard attribute(element, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole else { return nil }
        let role = attribute(element, kAXRoleAttribute) as? String
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role ?? "") else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        let target = TextTarget(element: element, nativeView: nil, pid: pid)
        return target.snapshot() == nil ? nil : target
    }

    var supportsReplacement: Bool {
        if let nativeView { return nativeView.isEditable }
        guard let element else { return false }
        var text = DarwinBoolean(false)
        var range = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &text) == .success && text.boolValue
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
        guard let element, let snapshot = snapshot() else { return nil }
        var range = CFRange(location: snapshot.selection.location, length: 0)
        var bounds: CFTypeRef?
        var rect = CGRect.zero
        if let value = AXValueCreate(.cfRange, &range),
           AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, value, &bounds) == .success,
           let bounds, CFGetTypeID(bounds) == AXValueGetTypeID(),
           AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.height > 0 {
            return rect
        }
        return nil
    }

    func isFocused() -> Bool {
        if let nativeView { return NSApp.isActive && NSApp.keyWindow?.firstResponder === nativeView }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let current = Self.focused(), let currentElement = current.element, let element else { return false }
        return current.pid == pid && CFEqual(currentElement, element)
    }

    func replace(session: CompletionSession, with text: String) -> Bool {
        guard isFocused(), supportsReplacement, let snapshot = snapshot(),
              session.validates(text: snapshot.text, selection: snapshot.selection) else { return false }
        if let nativeView {
            nativeView.breakUndoCoalescing()
            nativeView.insertText(text, replacementRange: session.replacementRange)
            nativeView.breakUndoCoalescing()
            return true
        }
        guard let element else { return false }
        var range = CFRange(location: session.replacementRange.location, length: session.replacementRange.length)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success else { return false }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let current = Self.focused(), let currentElement = current.element, CFEqual(currentElement, element),
              let selected = self.snapshot(), selected.text.utf16.elementsEqual(snapshot.text.utf16),
              selected.selection == session.replacementRange else { return false }
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        if result != .success {
            var original = CFRange(location: snapshot.selection.location, length: snapshot.selection.length)
            if let value = AXValueCreate(.cfRange, &original) {
                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
            }
            return false
        }
        return true
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
