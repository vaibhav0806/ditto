import AppKit
import SwiftUI
import DittoCore

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
        }.padding(18).frame(width: model.history ? 540 : 440, height: model.history ? 560 : 215)
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
    var onResign: (() -> Void)?
    private var observer: NSObjectProtocol?

    init() {
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
        model.history = history
        panel.acceptsInput = history
        panel.ignoresMouseEvents = !history
        let size = NSSize(width: history ? 540 : 440, height: history ? 560 : 215)
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

    func hide() { panel.orderOut(nil) }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
