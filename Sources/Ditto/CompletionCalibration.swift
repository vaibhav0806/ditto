import AppKit
import Carbon
import CoreText
import ScreenCaptureKit
import DittoUI

final class CompletionCalibration {
    private var values: [String: CGFloat] = [:]
    private var attempted: Set<String> = []
    private var order: [String] = []
    private var running = false

    private func key(_ target: TextTarget, _ style: GhostTextStyle, _ caret: CGRect) -> String {
        "\(target.calibrationIdentity):\(style.font.fontName):\(style.font.pointSize):\((style.attributes[.kern] as? NSNumber)?.doubleValue ?? 0):\((style.attributes[.paragraphStyle] as? NSParagraphStyle)?.hash ?? 0):\((style.attributes[.baselineOffset] as? NSNumber)?.doubleValue ?? 0):\(caret.minY):\(caret.height)"
    }

    func offset(target: TextTarget, style: GhostTextStyle, caret: CGRect) -> CGFloat? {
        values[key(target, style, caret)]
    }

    func measure(target: TextTarget, style: GhostTextStyle, caret: CGRect, excluded: Set<CGWindowID>, isCurrent: @escaping () -> Bool, completion: @escaping () -> Void) {
        guard #available(macOS 14, *), !running, style.reported, CGPreflightScreenCaptureAccess(), !IsSecureEventInputEnabled(), isCurrent(),
              let snapshot = target.snapshot(), snapshot.selection.length == 0, let selection = Range(snapshot.selection, in: snapshot.text),
              let field = target.fieldBounds else { return }
        let id = key(target, style, caret)
        guard !attempted.contains(id) else { return }
        var text = String(snapshot.text[..<selection.lowerBound].split(separator: "\n", omittingEmptySubsequences: false).last ?? "").suffix(48)
        func advance(_ text: Substring) -> CGFloat {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(text), attributes: style.attributes))
            return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }
        let available = min(240, caret.minX - field.minX - 4)
        while !text.isEmpty && advance(text) > available { text.removeFirst() }
        guard text.filter({ !$0.isWhitespace }).count >= 4 else { return }
        let width = advance(text)
        let region = CGRect(x: caret.minX - width - 4, y: caret.minY - 8, width: width + 3, height: caret.height + 16).intersection(field)
        guard region.width >= 12, region.height >= caret.height else { return }
        attempted.insert(id)
        order.append(id)
        if order.count > 24 { let old = order.removeFirst(); values.removeValue(forKey: old); attempted.remove(old) }
        running = true
        let sampleText = String(text)
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let scale = NSScreen.screens.first { $0.frame.contains(CGPoint(x: caret.minX, y: top - caret.midY)) }?.backingScaleFactor ?? 1
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, _ in
            guard let content, let display = content.displays.first(where: { $0.frame.contains(region) }) else {
                DispatchQueue.main.async { self.running = false }
                return
            }
            DispatchQueue.main.async {
                guard isCurrent(), !IsSecureEventInputEnabled(), target.isFocused(), target.caret == caret else { self.running = false; return }
                let config = SCStreamConfiguration()
                config.sourceRect = region.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
                config.width = Int((region.width * scale).rounded(.up))
                config.height = Int((region.height * scale).rounded(.up))
                config.showsCursor = false
                let filter = SCContentFilter(display: display, excludingWindows: content.windows.filter { excluded.contains($0.windowID) })
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, _ in
                    DispatchQueue.main.async {
                        self.running = false
                        guard isCurrent(), !IsSecureEventInputEnabled(), target.isFocused(), target.caret == caret, let image else { return }
                        let relative = CGRect(x: caret.minX - region.minX, y: caret.minY - region.minY, width: 0, height: caret.height)
                        if let result = GhostTextMeasurement.baseline(image: image, scale: scale, text: sampleText, style: style, caret: relative) {
                            self.values[id] = result.offset
                            completion()
                        }
                    }
                }
            }
        }
    }
}
