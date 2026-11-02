import AppKit
import SwiftUI
import DittoCore
import DittoCapture

final class OverlayModel: ObservableObject {
    @Published var history = false
    @Published var query = ""
    @Published var entries: [ClipboardEntry] = []
    @Published var selectedIndex = 0
    @Published var message = ""
    @Published var canInsert = false
    var selected: ClipboardEntry? { entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil }
    var onQuery: ((String) -> Void)?
    var onMove: ((Int) -> Void)?
    var onAccept: (() -> Void)?
    var onEscape: (() -> Void)?
    var onPick: ((Int) -> Void)?
    var onPin: (() -> Void)?
    var onDelete: (() -> Void)?
    var onCopy: (() -> Void)?
}

private struct HistorySearch: NSViewRepresentable {
    @ObservedObject var model: OverlayModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Filter clipboard history…"
        field.delegate = context.coordinator
        field.stringValue = model.query
        field.focusRingType = .none
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != model.query { field.stringValue = model.query }
    }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        let model: OverlayModel
        init(_ model: OverlayModel) { self.model = model }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            model.onQuery?(field.stringValue)
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            switch command {
            case #selector(NSResponder.moveDown(_:)): model.onMove?(1)
            case #selector(NSResponder.moveUp(_:)): model.onMove?(-1)
            case #selector(NSResponder.insertNewline(_:)): model.onAccept?()
            case #selector(NSResponder.cancelOperation(_:)): model.onEscape?()
            default: return false
            }
            return true
        }
    }
}

private struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.on.clipboard").foregroundStyle(.secondary)
                Text(model.history ? "Ditto · History" : "Ditto").font(.headline)
                Spacer()
                if !model.entries.isEmpty { Text("\(model.selectedIndex + 1) / \(model.entries.count)").font(.caption).foregroundStyle(.secondary) }
            }
            if model.history {
                HistorySearch(model: model).frame(height: 28)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, item in
                                Button { model.onPick?(index) } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: item.pinned ? "pin.fill" : "text.alignleft").frame(width: 16)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.text.replacingOccurrences(of: "\n", with: " ")).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                            Text("\(item.source) · \(item.copiedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }.padding(9).contentShape(Rectangle())
                                }.buttonStyle(.plain).background(index == model.selectedIndex ? Color.accentColor.opacity(0.2) : Color.clear).clipShape(RoundedRectangle(cornerRadius: 7)).id(item.id)
                            }
                        }
                    }.onChange(of: model.selectedIndex) { _ in
                        if let item = model.selected { proxy.scrollTo(item.id, anchor: .center) }
                    }
                }.frame(maxHeight: .infinity)
                if let selected = model.selected {
                    Divider()
                    ScrollView { Text(selected.text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 80)
                    HStack {
                        Button(selected.pinned ? "Unpin" : "Pin") { model.onPin?() }
                        Button("Delete", role: .destructive) { model.onDelete?() }
                        Spacer()
                        Button("Copy") { model.onCopy?() }
                        if model.canInsert { Button("Paste ↵") { model.onAccept?() }.buttonStyle(.borderedProminent) }
                    }.controlSize(.small)
                }
            } else if let selected = model.selected {
                Text(selected.text).font(.system(.body, design: .monospaced)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                Text("\(selected.source) · Paste full item · \(selected.text.count) characters").font(.caption).foregroundStyle(.secondary)
            }
            if model.entries.isEmpty {
                Text(model.query.isEmpty ? "No clipboard history yet. Enable capture, then copy some text." : "No matching clipboard items.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.secondary) }
            Divider()
            Text(model.history ? (model.canInsert ? "↑↓ select · Enter paste · Esc back" : "↑↓ select · Enter copy · Esc close") : "Tab paste · ↑↓ next · ⌘L history · Esc close").font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(width: 540, height: model.entries.isEmpty ? 215 : 560)
    }
}

final class SuggestionPanel: NSPanel {
    var acceptsInput = false
    override var canBecomeKey: Bool { acceptsInput }
    override var canBecomeMain: Bool { false }
}

final class OverlayController {
    let model = OverlayModel()
    private let panel: SuggestionPanel
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
        panel = SuggestionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .windowBackgroundColor
        panel.isMovable = false
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
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
        let size = NSSize(width: 540, height: model.entries.isEmpty ? 215 : 560)
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let point = caret.map { NSPoint(x: $0.minX, y: primaryTop - $0.maxY) }
        let screen = point.flatMap { p in NSScreen.screens.first { $0.frame.contains(p) } } ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.visibleFrame
        var origin = point.map { NSPoint(x: $0.x, y: $0.y - size.height - 8) } ?? NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        origin.x = min(max(origin.x, frame.minX + 8), frame.maxX - size.width - 8)
        origin.y = min(max(origin.y, frame.minY + 8), frame.maxY - size.height - 8)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if history { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
    }

    func showCompletion(caret: CGRect?, font: NSFont, background: PlaceholderBackground? = nil, inline: Bool = true) {
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
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityLabel("Ditto completion")
        label.sizeToFit()
        let width = min(max(label.frame.width + 4, 24), 600)
        let lineHeight = max(caret.height, font.ascender - font.descender + font.leading + 4)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: lineHeight + 16))
        label.frame = NSRect(x: 0, y: 16, width: width, height: lineHeight)
        let hint = NSTextField(labelWithString: "⇥ accept   ↑↓   \(model.selectedIndex + 1)/\(model.entries.count)   ⌘L history")
        hint.font = .systemFont(ofSize: 9)
        hint.textColor = .tertiaryLabelColor
        hint.frame = NSRect(x: 1, y: 0, width: max(width, 240), height: 14)
        content.addSubview(label)
        content.addSubview(hint)
        content.setFrameSize(NSSize(width: max(width, 240), height: lineHeight + 16))
        let size = content.frame.size
        ghost.contentView = content
        placeGhost(size: size, caret: caret, inline: isPrefix && inline && InputPolicy.allowsInlineCompletion(query: model.query, hasMask: background != nil))
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
        let y = inline ? point.y - 16 : (below >= bounds.minY + 4 ? below : above)
        let origin = NSPoint(x: min(max(point.x, bounds.minX + 4), bounds.maxX - size.width - 4), y: min(max(y, bounds.minY + 4), bounds.maxY - size.height - 4))
        ghost.setFrame(NSRect(origin: origin, size: size), display: true)
        ghost.orderFrontRegardless()
    }

    func hideForTyping() { mask.orderOut(nil); ghost.orderOut(nil); appliedBackground = nil }
    func hide() { panel.orderOut(nil); hideForTyping() }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
