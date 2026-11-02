import AppKit
import Carbon

enum SyntheticInput {
    static let marker: Int64 = 0x444954544F

    static func events(for text: String) -> [CGEvent]? {
        guard text.utf16.count <= 4096 else { return nil }
        var events: [CGEvent] = []
        let source = CGEventSource(stateID: .privateState)
        for character in text {
            let units = Array(String(character).utf16)
            guard units.count <= 20 else { return nil }
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { return nil }
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: marker)
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                events.append(event)
            }
        }
        return events
    }

    static func text(from event: CGEvent) -> String {
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        var units = [UniChar](repeating: 0, count: length)
        event.keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &length, unicodeString: &units)
        return String(utf16CodeUnits: units, count: length)
    }
}

final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onInvoke: (() -> Void)?

    func start() -> Bool {
        guard hotKey == nil else { return true }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, pointer in
            guard let pointer else { return OSStatus(eventNotHandledErr) }
            Unmanaged<GlobalShortcut>.fromOpaque(pointer).takeUnretainedValue().onInvoke?()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return false }
        let id = EventHotKeyID(signature: 0x4454544F, id: 1)
        return RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

final class KeyboardMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var onKey: ((CGEvent) -> Bool)?
    var onClick: (() -> Void)?
    var onDisabled: (() -> Void)?

    func start() -> Bool {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true); return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(pointer).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                monitor.onDisabled?()
                if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else if type == .keyDown {
                if event.getIntegerValueField(.eventSourceUserData) == SyntheticInput.marker { return Unmanaged.passUnretained(event) }
                if monitor.onKey?(event) == true { return nil }
            } else {
                monitor.onClick?()
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    deinit { stop() }
}
