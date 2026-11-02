import AppKit
import DittoCore
import DittoCapture
import DittoUI

final class SuggestionPanel: NSPanel {
    var acceptsInput = false
    override var canBecomeKey: Bool { acceptsInput }
    override var canBecomeMain: Bool { false }
}

final class OverlayController {
    let model = OverlayModel()
    private let panel: HistoryPanelWindow
    private let ghost = SuggestionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let mask = SuggestionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var appliedBackground: PlaceholderBackground?
    var excludedWindowIDs: Set<CGWindowID> { Set([ghost, mask, panel].filter { $0.windowNumber > 0 }.map { CGWindowID($0.windowNumber) }) }
    var onResign: (() -> Void)?
    private var observer: NSObjectProtocol?

    init() {
        mask.level = .floating
        mask.isFloatingPanel = true
        mask.hidesOnDeactivate = false
        mask.isOpaque = false
        mask.backgroundColor = .clear
        mask.hasShadow = false
        mask.ignoresMouseEvents = true
        mask.title = "Ditto placeholder mask"
        ghost.level = .floating
        ghost.isFloatingPanel = true
        ghost.hidesOnDeactivate = false
        ghost.isOpaque = false
        ghost.backgroundColor = .clear
        ghost.hasShadow = false
        ghost.ignoresMouseEvents = true
        ghost.title = "Ditto completion"
        panel = HistoryPanelWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovable = false
        panel.contentView = HistoryPanelView(model: model)
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 12
        panel.contentView?.layer?.masksToBounds = true
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in self?.onResign?() }
    }

    func show(history: Bool, caret: CGRect? = nil) {
        mask.orderOut(nil)
        model.history = history
        panel.acceptsInput = history
        panel.ignoresMouseEvents = !history
        ghost.orderOut(nil)
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let nativeCaret = caret.map { CGRect(x: $0.minX, y: primaryTop - $0.maxY, width: $0.width, height: $0.height) }
        let point = nativeCaret.map { NSPoint(x: $0.minX, y: $0.midY) } ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0]
        panel.setFrame(HistoryPresentation.frame(caret: nativeCaret, screen: screen.visibleFrame), display: true)
        if history {
            panel.makeKeyAndOrderFront(nil)
            (panel.contentView as? HistoryPanelView)?.focusSearch()
        } else { panel.orderFrontRegardless() }
    }

    func showCompletion(caret: CGRect?, font: NSFont, background: PlaceholderBackground? = nil, inline: Bool = true, hasExistingText: Bool = false, field: CGRect? = nil) {
        panel.orderOut(nil)
        guard let caret else { showNotice("Cursor position unavailable · ⌘L for history"); return }
        guard let selected = model.selected else {
            showNotice(model.query.isEmpty ? "No copied text yet · copy something to start" : "No clipboard matches · Esc to close", caret: caret)
            return
        }
        let range = model.query.isEmpty ? selected.text.startIndex..<selected.text.startIndex : selected.text.range(of: model.query, options: [.caseInsensitive, .diacriticInsensitive])
        let isPrefix = range?.lowerBound == selected.text.startIndex
        if let background {
            if appliedBackground != background || !mask.isVisible {
                let top = NSScreen.screens.first?.frame.maxY ?? 0
                let rect = background.region
                mask.contentView = PlaceholderMaskView(background: background, caret: caret)
                mask.setFrame(CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height), display: true)
                mask.orderFrontRegardless()
                appliedBackground = background
            }
        } else { mask.orderOut(nil); appliedBackground = nil }
        let completion = isPrefix ? String(selected.text[(range?.upperBound ?? selected.text.startIndex)...]) : selected.text
        let firstLine = completion.components(separatedBy: .newlines).first ?? ""
        let value = firstLine + (completion.contains("\n") ? " …" : "")
        let label = NSTextField(labelWithString: value.isEmpty ? "⇥" : value)
        label.font = font
        label.textColor = background?.ink ?? .secondaryLabelColor
        label.maximumNumberOfLines = 1
        label.cell?.usesSingleLineMode = true
        label.cell?.truncatesLastVisibleLine = true
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityLabel("Ditto completion")
        label.sizeToFit()
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let point = NSPoint(x: caret.minX, y: top - caret.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0]
        let right = min(field?.maxX ?? screen.visibleFrame.maxX, screen.visibleFrame.maxX)
        let width = min(max(label.frame.width + 4, 24), 600, max(1, right - caret.minX - 4))
        let lineHeight = caret.height
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: lineHeight))
        label.frame = content.bounds
        content.addSubview(label)
        let size = content.frame.size
        ghost.contentView = content
        placeGhost(size: size, caret: caret, inline: isPrefix && inline && InputPolicy.allowsInlineCompletion(query: model.query, hasMask: background != nil, hasExistingText: hasExistingText))
    }

    func showNotice(_ message: String, caret: CGRect? = nil) {
        mask.orderOut(nil)
        panel.orderOut(nil)
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.sizeToFit()
        let width = min(label.frame.width + 24, 440)
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: 32))
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true
        label.frame = NSRect(x: 12, y: 8, width: width - 24, height: 16)
        effect.addSubview(label)
        let size = effect.frame.size
        ghost.contentView = effect
        placeGhost(size: size, caret: caret, inline: false)
    }

    private func placeGhost(size: NSSize, caret: CGRect?, inline: Bool) {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let point = caret.map { NSPoint(x: $0.minX, y: top - $0.maxY) } ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0]
        let bounds = screen.visibleFrame
        let below = point.y - size.height - 5
        let above = caret.map { top - $0.minY + 5 } ?? point.y + 5
        let y = inline ? point.y : (below >= bounds.minY + 4 ? below : above)
        let origin = NSPoint(x: inline ? point.x : min(max(point.x, bounds.minX + 4), bounds.maxX - size.width - 4), y: min(max(y, bounds.minY + 4), bounds.maxY - size.height - 4))
        ghost.setFrame(NSRect(origin: origin, size: size), display: true)
        ghost.orderFrontRegardless()
    }

    func hideForTyping() { mask.orderOut(nil); ghost.orderOut(nil); appliedBackground = nil }
    func hide() { panel.orderOut(nil); hideForTyping() }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
