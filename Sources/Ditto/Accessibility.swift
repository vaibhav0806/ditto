import AppKit
import ApplicationServices
import DittoCore

struct TextSnapshot {
    let text: String
    let selection: NSRange
}

struct TextTarget {
    let element: AXUIElement
    let pid: pid_t
    let caret: CGRect?

    static func focused() -> TextTarget? {
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
        let target = TextTarget(element: element, pid: pid, caret: nil)
        guard let snapshot = target.snapshot() else { return nil }
        var range = CFRange(location: snapshot.selection.location, length: 0)
        var bounds: CFTypeRef?
        var rect = CGRect.zero
        if let value = AXValueCreate(.cfRange, &range),
           AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, value, &bounds) == .success,
           let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() {
            AXValueGetValue(bounds as! AXValue, .cgRect, &rect)
        }
        return TextTarget(element: element, pid: pid, caret: rect.isEmpty ? nil : rect)
    }

    var supportsReplacement: Bool {
        var text = DarwinBoolean(false)
        var range = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &text) == .success && text.boolValue
            && AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success && range.boolValue
    }

    func snapshot() -> TextSnapshot? {
        guard let text = Self.attribute(element, kAXValueAttribute) as? String,
              text.utf16.count <= 100_000,
              let raw = Self.attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return TextSnapshot(text: text, selection: NSRange(location: range.location, length: range.length))
    }

    func isFocused() -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let current = Self.focused() else { return false }
        return current.pid == pid && CFEqual(current.element, element)
    }

    func replace(session: CompletionSession, with text: String) -> Bool {
        guard isFocused(), supportsReplacement, let snapshot = snapshot(),
              session.validates(text: snapshot.text, selection: snapshot.selection) else { return false }
        var range = CFRange(location: session.replacementRange.location, length: session.replacementRange.length)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success else { return false }
        // Validate the newly selected range and unchanged text before the one mutating write.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let current = Self.focused(), CFEqual(current.element, element),
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
