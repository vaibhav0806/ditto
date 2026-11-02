import AppKit
import Combine
import DittoCore

public final class HistoryPanelWindow: NSPanel {
    public var acceptsInput = true
    public override var canBecomeKey: Bool { acceptsInput }
    public override var canBecomeMain: Bool { false }
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if acceptsInput, event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
           event.charactersIgnoringModifiers == "k", let history = contentView as? HistoryPanelView {
            history.showActions()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class HistoryTable: NSTableView {
    override var acceptsFirstResponder: Bool { false }
}

private final class HistorySelection: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
}

private final class HistoryCell: NSTableCellView {
    let icon = NSImageView()
    let title = NSTextField(labelWithString: "")
    let age = NSTextField(labelWithString: "")
    let pin = NSImageView(image: NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)!)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title.font = .systemFont(ofSize: 13)
        title.maximumNumberOfLines = 1
        title.cell?.usesSingleLineMode = true
        title.cell?.truncatesLastVisibleLine = true
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        age.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        age.alignment = .right
        age.setContentCompressionResistancePriority(.required, for: .horizontal)
        pin.contentTintColor = .tertiaryLabelColor
        for view in [icon, title, pin, age] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.setAccessibilityElement(false)
            addSubview(view)
            view.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            pin.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 12), pin.widthAnchor.constraint(equalToConstant: 14), pin.heightAnchor.constraint(equalToConstant: 10),
            age.leadingAnchor.constraint(equalTo: pin.trailingAnchor, constant: 8), age.widthAnchor.constraint(equalToConstant: 36), age.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.cell)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSelected(_ selected: Bool) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        title.attributedStringValue = NSAttributedString(string: title.stringValue, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .regular), .foregroundColor: selected ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor, .paragraphStyle: paragraph])
        age.textColor = selected ? .selectedMenuItemTextColor : .secondaryLabelColor
        pin.contentTintColor = selected ? .selectedMenuItemTextColor : .tertiaryLabelColor
    }
}

public final class HistoryPanelView: NSVisualEffectView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private enum Row { case section(String), clip(Int) }
    private let model: OverlayModel
    private let search = NSTextField()
    private let destination = NSImageView()
    private let escape = NSTextField(labelWithString: "")
    private let table = HistoryTable()
    private let listScroll = NSScrollView()
    private let empty = NSTextField(wrappingLabelWithString: "")
    private let preview = NSTextView()
    private let previewScroll = NSScrollView()
    private let source = NSTextField(labelWithString: "")
    private let copied = NSTextField(labelWithString: "")
    private let size = NSTextField(labelWithString: "")
    private let limit = NSTextField(wrappingLabelWithString: "")
    private let metadata = NSStackView()
    private let context = NSTextField(labelWithString: "")
    private let primary = NSButton(title: "Copy ↵", target: nil, action: nil)
    private let actions = NSPopUpButton(frame: .zero, pullsDown: true)
    private var rows: [Row] = []
    private var displayedEntries: [ClipboardEntry] = []
    private var displayedQuery = ""
    private var previewID: String?
    private var iconCache: [String: NSImage] = [:]
    private var observation: AnyCancellable?
    private var appearanceObserver: NSObjectProtocol?
    private var refreshScheduled = false
    private let copiedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    public init(model: OverlayModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 680, height: 440))
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        build()
        refresh()
        observation = model.objectWillChange.sink { [weak self] in
            guard let self, self.window?.isVisible == true, !self.refreshScheduled else { return }
            self.refreshScheduled = true
            DispatchQueue.main.async { [weak self] in self?.refreshScheduled = false; self?.refresh() }
        }
        appearanceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.updateMaterial() }
        updateMaterial()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let appearanceObserver { NSWorkspace.shared.notificationCenter.removeObserver(appearanceObserver) } }

    private func build() {
        let header = NSView()
        search.identifier = NSUserInterfaceItemIdentifier("DittoHistorySearch")
        search.placeholderString = "Search copied text…"
        search.font = .systemFont(ofSize: 20)
        search.isBezeled = false
        search.drawsBackground = false
        search.focusRingType = .none
        search.delegate = self
        search.setAccessibilityLabel("Search clipboard history")
        escape.font = .systemFont(ofSize: 11)
        escape.textColor = .secondaryLabelColor
        escape.setAccessibilityElement(false)
        escape.setContentCompressionResistancePriority(.required, for: .horizontal)
        let headerStack = NSStackView(views: [destination, search, escape])
        headerStack.spacing = 8
        destination.widthAnchor.constraint(equalToConstant: 16).isActive = true
        destination.heightAnchor.constraint(equalToConstant: 16).isActive = true
        embed(headerStack, in: header, horizontal: 16, vertical: 12)

        let body = NSView()
        let list = NSView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.allowsEmptySelection = true
        table.delegate = self
        table.dataSource = self
        table.setAccessibilityLabel("Clipboard history")
        listScroll.documentView = table
        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = true
        listScroll.autohidesScrollers = true
        listScroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 6, right: 0)
        embed(listScroll, in: list)
        empty.font = .systemFont(ofSize: 13)
        empty.textColor = .secondaryLabelColor
        empty.translatesAutoresizingMaskIntoConstraints = false
        list.addSubview(empty)
        NSLayoutConstraint.activate([empty.topAnchor.constraint(equalTo: list.topAnchor, constant: 28), empty.leadingAnchor.constraint(equalTo: list.leadingAnchor, constant: 18), empty.trailingAnchor.constraint(equalTo: list.trailingAnchor, constant: -18)])

        let detail = NSView()
        preview.isEditable = false
        preview.identifier = NSUserInterfaceItemIdentifier("DittoHistoryPreview")
        preview.isSelectable = true
        preview.drawsBackground = false
        preview.textContainerInset = NSSize(width: 16, height: 12)
        preview.isHorizontallyResizable = false
        preview.autoresizingMask = [.width]
        preview.textContainer?.widthTracksTextView = true
        preview.textContainer?.lineFragmentPadding = 0
        preview.layoutManager?.showsInvisibleCharacters = false
        preview.setAccessibilityLabel("Selected clipboard text preview")
        previewScroll.documentView = preview
        previewScroll.drawsBackground = false
        previewScroll.hasVerticalScroller = true
        previewScroll.autohidesScrollers = true
        metadata.identifier = NSUserInterfaceItemIdentifier("DittoHistoryMetadata")
        let metadataRows: [NSView] = [metadataRow("Source", source), metadataRow("Copied", copied), metadataRow("Size", size), limit]
        metadataRows.forEach { metadata.addArrangedSubview($0) }
        metadata.orientation = .vertical
        metadata.alignment = .leading
        metadata.spacing = 6
        for row in metadata.arrangedSubviews { row.widthAnchor.constraint(equalTo: metadata.widthAnchor).isActive = true }
        for label in [source, copied, size, limit] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
        }
        limit.font = .systemFont(ofSize: 10)
        limit.textColor = .secondaryLabelColor
        let previewRule = separator()
        for view in [previewScroll, previewRule, metadata] { view.translatesAutoresizingMaskIntoConstraints = false; detail.addSubview(view) }
        NSLayoutConstraint.activate([
            previewScroll.topAnchor.constraint(equalTo: detail.topAnchor), previewScroll.leadingAnchor.constraint(equalTo: detail.leadingAnchor), previewScroll.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            previewScroll.bottomAnchor.constraint(equalTo: previewRule.topAnchor, constant: -2),
            previewRule.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 16), previewRule.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -16), previewRule.heightAnchor.constraint(equalToConstant: 1), previewRule.bottomAnchor.constraint(equalTo: metadata.topAnchor, constant: -10),
            metadata.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 16), metadata.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -16), metadata.bottomAnchor.constraint(equalTo: detail.bottomAnchor, constant: -16)
        ])
        let verticalRule = separator()
        for view in [list, verticalRule, detail] { view.translatesAutoresizingMaskIntoConstraints = false; body.addSubview(view) }
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: body.leadingAnchor), list.topAnchor.constraint(equalTo: body.topAnchor), list.bottomAnchor.constraint(equalTo: body.bottomAnchor), list.widthAnchor.constraint(equalTo: body.widthAnchor, multiplier: 0.58),
            verticalRule.leadingAnchor.constraint(equalTo: list.trailingAnchor), verticalRule.widthAnchor.constraint(equalToConstant: 1), verticalRule.topAnchor.constraint(equalTo: body.topAnchor), verticalRule.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            detail.leadingAnchor.constraint(equalTo: verticalRule.trailingAnchor), detail.topAnchor.constraint(equalTo: body.topAnchor), detail.bottomAnchor.constraint(equalTo: body.bottomAnchor), detail.trailingAnchor.constraint(equalTo: body.trailingAnchor)
        ])

        let footer = NSView()
        context.font = .systemFont(ofSize: 11)
        context.textColor = .secondaryLabelColor
        context.lineBreakMode = .byTruncatingTail
        context.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        primary.font = .systemFont(ofSize: 13, weight: .medium)
        primary.isBordered = false
        primary.keyEquivalent = "\r"
        primary.keyEquivalentModifierMask = []
        primary.target = self
        primary.action = #selector(accept)
        actions.isBordered = false
        actions.font = .systemFont(ofSize: 13)
        actions.setAccessibilityLabel("Actions")
        actions.menu = NSMenu()
        actions.menu?.addItem(withTitle: "Actions  ⌘K", action: nil, keyEquivalent: "")
        actions.menu?.item(at: 0)?.attributedTitle = actionTitle("Actions", shortcut: "⌘K", primary: false)
        for (index, item) in [("Copy", "c"), ("Pin", "p"), ("Delete", "\u{8}")].enumerated() {
            let action = NSMenuItem(title: item.0, action: #selector(menuAction(_:)), keyEquivalent: item.1)
            action.keyEquivalentModifierMask = .command
            action.tag = index
            action.target = self
            actions.menu?.addItem(action)
        }
        let footerStack = NSStackView(views: [context, primary, actions])
        footerStack.spacing = 16
        embed(footerStack, in: footer, horizontal: 16, vertical: 5)
        let topRule = separator(), bottomRule = separator()
        for view in [header, topRule, body, bottomRule, footer] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor), header.leadingAnchor.constraint(equalTo: leadingAnchor), header.trailingAnchor.constraint(equalTo: trailingAnchor), header.heightAnchor.constraint(equalToConstant: 52),
            topRule.topAnchor.constraint(equalTo: header.bottomAnchor), topRule.leadingAnchor.constraint(equalTo: leadingAnchor), topRule.trailingAnchor.constraint(equalTo: trailingAnchor), topRule.heightAnchor.constraint(equalToConstant: 1),
            body.topAnchor.constraint(equalTo: topRule.bottomAnchor), body.leadingAnchor.constraint(equalTo: leadingAnchor), body.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomRule.topAnchor.constraint(equalTo: body.bottomAnchor), bottomRule.leadingAnchor.constraint(equalTo: leadingAnchor), bottomRule.trailingAnchor.constraint(equalTo: trailingAnchor), bottomRule.heightAnchor.constraint(equalToConstant: 1),
            footer.topAnchor.constraint(equalTo: bottomRule.bottomAnchor), footer.leadingAnchor.constraint(equalTo: leadingAnchor), footer.trailingAnchor.constraint(equalTo: trailingAnchor), footer.bottomAnchor.constraint(equalTo: bottomAnchor), footer.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func embed(_ child: NSView, in parent: NSView, horizontal: CGFloat = 0, vertical: CGFloat = 0) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: horizontal), child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -horizontal), child.topAnchor.constraint(equalTo: parent.topAnchor, constant: vertical), child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -vertical)])
    }

    private func separator() -> NSBox { let rule = NSBox(); rule.boxType = .separator; return rule }

    private func metadataRow(_ name: String, _ value: NSTextField) -> NSStackView {
        let title = NSTextField(labelWithString: name)
        title.font = .systemFont(ofSize: 11)
        title.textColor = .secondaryLabelColor
        title.widthAnchor.constraint(equalToConstant: 44).isActive = true
        value.lineBreakMode = .byTruncatingMiddle
        value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [title, value]); row.spacing = 10
        return row
    }

    private func updateMaterial() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? NSColor.windowBackgroundColor.cgColor : nil
        }
    }

    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateMaterial() }

    private func actionTitle(_ title: String, shortcut: String, primary: Bool) -> NSAttributedString {
        let value = NSMutableAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: primary ? .medium : .regular), .foregroundColor: primary ? NSColor.labelColor : NSColor.secondaryLabelColor])
        value.append(NSAttributedString(string: "  " + shortcut, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.tertiaryLabelColor]))
        return value
    }

    public func focusSearch() {
        layoutSubtreeIfNeeded()
        refresh()
        window?.makeFirstResponder(search)
        if let editor = search.currentEditor() { editor.selectedRange = NSRange(location: search.stringValue.utf16.count, length: 0) }
    }

    public func showActions() { actions.performClick(nil) }

    private func refresh() {
        if search.stringValue != model.query { search.stringValue = model.query }
        let hint = NSMutableAttributedString(string: "esc  ", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.tertiaryLabelColor])
        hint.append(NSAttributedString(string: model.canReturnToCompletion ? "Back to suggestions" : "Close", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        escape.attributedStringValue = hint
        destination.image = appIcon(model.destinationBundleID)
        destination.setAccessibilityLabel(model.destinationName.isEmpty ? "Clipboard history" : "Destination: \(model.destinationName)")
        let changed = displayedEntries != model.entries || displayedQuery != model.query
        if changed {
            displayedEntries = model.entries
            displayedQuery = model.query
            rows = []
            var section = ""
            for (index, item) in model.entries.enumerated() {
                if model.query.isEmpty {
                    let day = Calendar.current.isDateInToday(item.copiedAt) ? "Today" : Calendar.current.isDateInYesterday(item.copiedAt) ? "Yesterday" : "Earlier"
                    if day != section { rows.append(.section(day)); section = day }
                }
                rows.append(.clip(index))
            }
            table.reloadData()
        }
        let selectedRow = rows.firstIndex { if case .clip(let index) = $0 { return index == model.selectedIndex }; return false }
        if let selectedRow {
            table.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
            if listScroll.contentView.bounds.height > 0 { table.scrollRowToVisible(model.selectedIndex == 0 ? 0 : selectedRow) }
        } else { table.deselectAll(nil) }
        for row in 0..<table.numberOfRows {
            (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? HistoryCell)?.setSelected(row == selectedRow)
        }
        listScroll.isHidden = model.entries.isEmpty
        empty.isHidden = !model.entries.isEmpty
        let emptyTitle = model.query.isEmpty ? "Nothing copied yet" : "No clips match “\(String(model.query.prefix(80)))\(model.query.count > 80 ? "…" : "")”"
        let emptyBody = model.query.isEmpty ? "Copy some text anywhere and it’ll show up here. History stays on this Mac." : "Try a shorter phrase, or press Esc to go back."
        let emptyStyle = NSMutableParagraphStyle(); emptyStyle.paragraphSpacing = 4
        let emptyText = NSMutableAttributedString(string: emptyTitle + "\n" + emptyBody, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: emptyStyle])
        emptyText.addAttributes([.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.labelColor], range: NSRange(location: 0, length: emptyTitle.utf16.count))
        empty.attributedStringValue = emptyText
        let primaryLabel = model.canInsert ? "Paste to \(model.destinationName.isEmpty ? "App" : model.destinationName)" : "Copy"
        primary.attributedTitle = actionTitle(primaryLabel, shortcut: "↵", primary: true)
        primary.setAccessibilityLabel(primaryLabel)
        primary.isEnabled = model.selected != nil
        context.stringValue = model.canInsert ? "" : model.destinationName.isEmpty ? "Copy a clip, then paste with ⌘V" : "Direct paste unavailable in \(model.destinationName)"
        context.toolTip = model.message
        actions.isEnabled = model.selected != nil
        actions.menu?.item(at: 2)?.title = model.selected?.pinned == true ? "Unpin" : "Pin"
        metadata.isHidden = model.selected == nil
        previewScroll.isHidden = model.selected == nil
        if previewID != model.selected?.id || changed {
            previewID = model.selected?.id
            let text = model.selected?.text ?? ""
            preview.string = HistoryPresentation.preview(text)
            let monospaced = text.contains(where: \.isNewline) || text.first?.isWhitespace == true
            preview.font = monospaced ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 13)
            preview.textColor = .labelColor
            let paragraph = NSMutableParagraphStyle()
            if monospaced { paragraph.minimumLineHeight = 16; paragraph.maximumLineHeight = 16 }
            else { paragraph.lineHeightMultiple = 1.45 }
            preview.defaultParagraphStyle = paragraph
            preview.textStorage?.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: preview.string.utf16.count))
            if monospaced, let font = preview.font {
                let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
                (preview.string as NSString).enumerateSubstrings(in: NSRange(location: 0, length: preview.string.utf16.count), options: .byParagraphs) { line, _, range, _ in
                    var columns = 0
                    for character in (line ?? "").prefix(while: { $0 == " " || $0 == "\t" }) { columns += character == "\t" ? 4 - columns % 4 : 1 }
                    let indented = paragraph.mutableCopy() as! NSMutableParagraphStyle
                    indented.headIndent = CGFloat(columns + 2) * spaceWidth
                    indented.tabStops = []
                    indented.defaultTabInterval = spaceWidth * 4
                    self.preview.textStorage?.addAttribute(.paragraphStyle, value: indented, range: range)
                }
            }
            preview.scrollToBeginningOfDocument(nil)
            source.stringValue = model.selected?.source ?? ""
            copied.stringValue = model.selected.map { copiedFormatter.string(from: $0.copiedAt) } ?? ""
            let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
            size.stringValue = model.selected == nil ? "" : "\(text.count.formatted()) characters" + (lines > 1 ? " · \(lines.formatted()) lines" : "")
            limit.stringValue = text.count > 5_000 ? "Showing the first 5,000 of \(text.count.formatted()) characters" : ""
            limit.isHidden = limit.stringValue.isEmpty
        }
    }

    private func appIcon(_ bundleID: String) -> NSImage? {
        if let cached = iconCache[bundleID] { return cached }
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "doc.plaintext", accessibilityDescription: nil)
        if let image { iconCache[bundleID] = image }
        return image
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { if case .section = rows[row] { return 26 }; return 34 }
    public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { if case .clip = rows[row] { return true }; return false }
    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { HistorySelection() }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .section(let name):
            let label = NSTextField(labelWithString: name)
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
            let group = NSView(); embed(label, in: group, horizontal: 16, vertical: 5)
            return group
        case .clip(let index):
            guard model.entries.indices.contains(index) else { return nil }
            let item = model.entries[index]
            let cell = HistoryCell()
            cell.title.stringValue = HistoryPresentation.rowTitle(item.text)
            cell.icon.image = appIcon(item.sourceBundleID)
            let seconds = max(0, Date().timeIntervalSince(item.copiedAt))
            cell.age.stringValue = seconds < 60 ? "now" : seconds < 3600 ? "\(Int(seconds / 60))m" : Calendar.current.isDateInToday(item.copiedAt) ? "\(Int(seconds / 3600))h" : Calendar.current.isDateInYesterday(item.copiedAt) ? "Yest" : item.copiedAt.formatted(.dateTime.month(.abbreviated).day())
            cell.pin.isHidden = !item.pinned
            cell.setSelected(index == model.selectedIndex)
            cell.setAccessibilityLabel("\(cell.title.stringValue), from \(item.source), \(item.copiedAt.formatted(date: .abbreviated, time: .shortened))\(item.pinned ? ", pinned" : "")")
            cell.setAccessibilityValue("\(index + 1) of \(model.entries.count)")
            return cell
        }
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard window?.isVisible == true, rows.indices.contains(table.selectedRow),
              case .clip(let index) = rows[table.selectedRow], index != model.selectedIndex else { return }
        model.onPick?(index)
    }

    public func controlTextDidChange(_ notification: Notification) { model.onQuery?(search.stringValue) }
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        switch NSStringFromSelector(command) {
        case "moveDown:": model.onMove?(1)
        case "moveUp:": model.onMove?(-1)
        case "moveToBeginningOfDocument:": model.onMove?(-model.entries.count)
        case "moveToEndOfDocument:": model.onMove?(model.entries.count)
        case "pageUp:", "scrollPageUp:": model.onMove?(-10)
        case "pageDown:", "scrollPageDown:": model.onMove?(10)
        case "insertNewline:": if model.selected != nil { model.onAccept?() }
        case "cancelOperation:": model.onEscape?()
        default: return false
        }
        return true
    }

    @objc private func accept() { model.onAccept?() }
    @objc private func menuAction(_ item: NSMenuItem) {
        switch item.tag {
        case 0: model.onCopy?()
        case 1: model.onPin?()
        case 2: model.onDelete?()
        default: break
        }
    }
}
