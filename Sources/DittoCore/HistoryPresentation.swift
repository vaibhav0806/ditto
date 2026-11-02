import Foundation
import CoreGraphics

public enum HistoryPresentation {
    public static func frame(caret: CGRect?, screen: CGRect) -> CGRect {
        let bounds = screen.insetBy(dx: 8, dy: 8)
        let size = CGSize(width: min(680, bounds.width), height: min(440, bounds.height))
        var origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - bounds.height / 3 - size.height / 2)
        if let caret {
            origin.x = caret.minX
            let below = caret.minY - 8 - size.height
            origin.y = below >= bounds.minY ? below : caret.maxY + 8
        }
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }

    public static func rowTitle(_ text: String) -> String {
        let title = text.split(whereSeparator: \.isWhitespace).prefix(100).joined(separator: " ")
        return title.isEmpty ? "Whitespace" : String(title.prefix(500))
    }

    public static func preview(_ text: String) -> String { String(text.prefix(5_000)) }

    public static func selectionIndex(current: Int, delta: Int, count: Int) -> Int {
        min(max(current + delta, 0), max(count - 1, 0))
    }
}
