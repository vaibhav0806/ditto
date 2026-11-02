import AppKit
import ApplicationServices
import Carbon
import DittoCore
import DittoUI
import OSLog

struct TextSnapshot {
    let text: String
    let selection: NSRange
}

struct TextTarget {
    private static var rememberedStyles: [Int: GhostTextStyle] = [:]
    private let element: AXUIElement?
    private let nativeView: NSTextView?
    let pid: pid_t
    var isNative: Bool { nativeView != nil }
    var calibrationIdentity: Int { nativeView.map { ObjectIdentifier($0).hashValue } ?? element.map { Int(CFHash($0)) } ?? Int(pid) }
    var caret: CGRect? { caretBounds() }
    var fieldBounds: CGRect? {
        if let nativeView, let window = nativeView.window {
            let rect = window.convertToScreen(nativeView.convert(nativeView.bounds, to: nil))
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
        } else if let element, let position = Self.attribute(element, kAXPositionAttribute), let size = Self.attribute(element, kAXSizeAttribute),
                  CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
            var point = CGPoint.zero
            var dimensions = CGSize.zero
            guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
            return CGRect(origin: point, size: dimensions)
        } else { return nil }
    }
    var placeholderRegion: CGRect? {
        guard let snapshot = snapshot(), InputPolicy.isVisuallyBlank(snapshot.text), let caret, let frame = fieldBounds else { return nil }
        return PlaceholderMask.region(field: frame, caret: caret)
    }
    var textStyle: GhostTextStyle {
        func remember(_ style: GhostTextStyle) -> GhostTextStyle {
            if Self.rememberedStyles.count >= 16 { Self.rememberedStyles.removeAll() }
            Self.rememberedStyles[calibrationIdentity] = style
            return style
        }
        if let nativeView {
            let attributes = nativeView.typingAttributes
            if let font = attributes[.font] as? NSFont ?? nativeView.font { return remember(GhostTextStyle(font: font, attributes: attributes)) }
        }
        if let element, let snapshot = rawSnapshot(), !snapshot.text.isEmpty,
           let caret = Range(NSRange(location: snapshot.selection.location, length: 0), in: snapshot.text)?.lowerBound {
            let start = caret == snapshot.text.startIndex ? caret : snapshot.text.index(before: caret)
            let end = caret == snapshot.text.startIndex ? snapshot.text.index(after: start) : caret
            let range = NSRange(start..<end, in: snapshot.text)
            if let style = readStyle(element, range: CFRange(location: range.location, length: range.length)) { return style.reported ? remember(style) : style }
        }
        if let placeholder = placeholderElement(), let style = readStyle(placeholder, range: CFRange(location: 0, length: 1)) { return style.reported ? remember(style) : style }
        if let remembered = Self.rememberedStyles[calibrationIdentity] { return remembered }
        return GhostTextStyle(font: .systemFont(ofSize: NSFont.systemFontSize), reported: false)
    }

    private func readStyle(_ element: AXUIElement, range: CFRange) -> GhostTextStyle? {
        var range = range
        var value: CFTypeRef?
        guard let parameter = AXValueCreate(.cfRange, &range), AXUIElementCopyParameterizedAttributeValue(element, kAXAttributedStringForRangeParameterizedAttribute as CFString, parameter, &value) == .success,
              let attributed = value as? NSAttributedString, attributed.length > 0 else { return nil }
        let attributes = attributed.attributes(at: 0, effectiveRange: nil)
        if let font = attributes[.font] as? NSFont { return GhostTextStyle(font: font, attributes: attributes) }
        let key = NSAttributedString.Key(kAXFontTextAttribute.takeUnretainedValue() as String)
        guard let info = attributes[key] as? [String: Any], let size = info[kAXFontSizeKey.takeUnretainedValue() as String] as? NSNumber else { return nil }
        for key in [kAXFontNameKey.takeUnretainedValue() as String, kAXFontFamilyKey.takeUnretainedValue() as String] {
            if let name = info[key] as? String, let font = NSFont(name: name, size: CGFloat(size.doubleValue)) { return GhostTextStyle(font: font, attributes: attributes) }
        }
        return GhostTextStyle(font: .systemFont(ofSize: CGFloat(size.doubleValue)), attributes: attributes, reported: false)
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
        guard let snapshot = rawSnapshot() else { return nil }
        if snapshot.text == "\n", snapshot.selection == NSRange(location: 0, length: 0),
           placeholderElement(for: snapshot) != nil || emptyParagraphBounds(for: snapshot) != nil {
            return TextSnapshot(text: "", selection: snapshot.selection)
        }
        return snapshot
    }

    private func rawSnapshot() -> TextSnapshot? {
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
        if let snapshot = rawSnapshot(), let paragraph = emptyParagraphBounds(for: snapshot) { return paragraph }
        if let placeholder = placeholderElement(), let rect = Self.bounds(placeholder), rect.height > 0, rect.height <= 64 {
            return CGRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height)
        }
        let collapsed = boundsForCharacters(NSRange(location: rawSnapshot()?.selection.location ?? 0, length: 0))
        if let snapshot = rawSnapshot(), snapshot.selection.length == 0, let selected = Range(snapshot.selection, in: snapshot.text) {
            if selected.lowerBound < snapshot.text.endIndex, !snapshot.text[selected.lowerBound].isNewline,
               let next = boundsForCharacters(NSRange(selected.lowerBound..<snapshot.text.index(after: selected.lowerBound), in: snapshot.text)) {
                return CGRect(x: collapsed?.minX ?? next.minX, y: next.minY, width: 0, height: next.height)
            }
            if selected.lowerBound > snapshot.text.startIndex {
                let previousIndex = snapshot.text.index(before: selected.lowerBound)
                if let previous = boundsForCharacters(NSRange(previousIndex..<selected.lowerBound, in: snapshot.text), allowWide: snapshot.text[previousIndex].isNewline) {
                    if !snapshot.text[previousIndex].isNewline {
                        return CGRect(x: collapsed?.minX ?? previous.maxX, y: previous.minY, width: 0, height: previous.height)
                    }
                    let prefix = snapshot.text[..<previousIndex]
                    let paragraphStart = prefix.lastIndex(where: \.isNewline).map { snapshot.text.index(after: $0) } ?? snapshot.text.startIndex
                    if paragraphStart < previousIndex, let first = boundsForCharacters(NSRange(paragraphStart..<snapshot.text.index(after: paragraphStart), in: snapshot.text)) {
                        let y = collapsed.flatMap { $0.minY >= previous.maxY - 0.5 ? $0.minY : nil } ?? previous.maxY
                        return CGRect(x: collapsed?.minX ?? first.minX, y: y, width: 0, height: previous.height)
                    }
                }
            }
        }
        var range = CFRange(location: snapshot()?.selection.location ?? 0, length: 0)
        var bounds: CFTypeRef?
        var rect = CGRect.zero
        if let value = AXValueCreate(.cfRange, &range),
           AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, value, &bounds) == .success,
           let bounds, CFGetTypeID(bounds) == AXValueGetTypeID(),
           AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.height > 0, rect.height <= 64 {
            if let field = fieldBounds, rect.maxY <= field.minY, rawSnapshot()?.text.isEmpty == true {
                return CGRect(x: rect.minX, y: field.minY, width: 0, height: rect.height)
            }
            if fieldBounds.map({ $0.intersects(rect.insetBy(dx: -0.5, dy: 0)) }) ?? true { return rect }
        }
        if let marker = Self.attribute(element, "AXSelectedTextMarkerRange"),
           AXUIElementCopyParameterizedAttributeValue(element, "AXBoundsForTextMarkerRange" as CFString, marker, &bounds) == .success,
           let bounds, CFGetTypeID(bounds) == AXValueGetTypeID(),
           AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.height > 0, rect.height <= 64 {
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

    private func boundsForCharacters(_ range: NSRange, allowWide: Bool = false) -> CGRect? {
        guard let element else { return nil }
        var characters = CFRange(location: range.location, length: range.length)
        var value: CFTypeRef?
        var rect = CGRect.zero
        guard let parameter = AXValueCreate(.cfRange, &characters), AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.height > 0, rect.height <= 64, allowWide || rect.width <= max(24, rect.height * 4),
              fieldBounds.map({ $0.intersects(rect.insetBy(dx: -0.5, dy: 0)) }) ?? true else { return nil }
        return rect
    }

    private func placeholderElement() -> AXUIElement? {
        guard let snapshot = rawSnapshot() else { return nil }
        return placeholderElement(for: snapshot)
    }

    private func emptyParagraphBounds(for snapshot: TextSnapshot) -> CGRect? {
        guard let element, snapshot.text == "\n", snapshot.selection == NSRange(location: 0, length: 0),
              let children = Self.attribute(element, kAXChildrenAttribute) as? [AXUIElement], children.count == 1,
              Self.attribute(children[0], kAXRoleAttribute) as? String == kAXGroupRole,
              let field = Self.bounds(element), let line = Self.bounds(children[0]), field.contains(line),
              line.height > 0, line.height <= 64, line.height < field.height else { return nil }
        return CGRect(x: line.minX, y: line.minY, width: 1, height: line.height)
    }

    private func placeholderElement(for snapshot: TextSnapshot) -> AXUIElement? {
        guard let element, InputPolicy.isVisuallyBlank(snapshot.text),
              let placeholder = Self.attribute(element, kAXPlaceholderValueAttribute) as? String, !placeholder.isEmpty,
              let parent = Self.attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID(),
              let siblings = Self.attribute(parent as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement], siblings.count <= 32 else { return nil }
        var pending = siblings
        var visited = 0
        while !pending.isEmpty && visited < 32 {
            let candidate = pending.removeFirst()
            visited += 1
            if Self.attribute(candidate, kAXRoleAttribute) as? String == kAXStaticTextRole,
               Self.attribute(candidate, kAXValueAttribute) as? String == placeholder { return candidate }
            if let children = Self.attribute(candidate, kAXChildrenAttribute) as? [AXUIElement], children.count <= 32 {
                pending.append(contentsOf: children)
            }
        }
        return nil
    }

    private static func bounds(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
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
