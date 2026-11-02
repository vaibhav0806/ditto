import Foundation
import CoreGraphics
import DittoCore

func testHistoryPlacementStaysOnTheTargetDisplay() {
    for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1600, y: -100, width: 1200, height: 800)] {
        for point in [CGPoint(x: screen.minX + 10, y: screen.minY + 10), CGPoint(x: screen.maxX - 10, y: screen.maxY - 40)] {
            let caret = CGRect(origin: point, size: CGSize(width: 1, height: 20))
            let frame = HistoryPresentation.frame(caret: caret, screen: screen)
            expectTrue(screen.insetBy(dx: 8, dy: 8).contains(frame))
            expectFalse(frame.intersects(caret))
        }
    }
    let caret = CGRect(x: 200, y: 500, width: 1, height: 20)
    expectTrue(HistoryPresentation.frame(caret: caret, screen: CGRect(x: 0, y: 0, width: 1440, height: 900)).maxY < caret.minY)
    let small = CGRect(x: 0, y: 0, width: 640, height: 420)
    expectTrue(small.insetBy(dx: 8, dy: 8).contains(HistoryPresentation.frame(caret: nil, screen: small)))
}

func testHistoryPresentationKeepsUnicodeAndBoundsPreview() {
    expectEqual(HistoryPresentation.rowTitle("\n  \n\t hello   👩🏽‍💻\tworld\nsecond"), "hello 👩🏽‍💻 world second")
    expectEqual(HistoryPresentation.rowTitle("{\n  \"name\": \"ditto\"\n}"), "{ \"name\": \"ditto\" }")
    expectEqual(HistoryPresentation.rowTitle(" \t\n"), "Whitespace")
    let long = String(repeating: "👩🏽‍💻", count: 5_010)
    expectEqual(HistoryPresentation.preview(long).count, 5_000)
    expectTrue(long.hasPrefix(HistoryPresentation.preview(long)))
    expectEqual(HistoryPresentation.preview("  hello\t\nworld  "), "  hello\t\nworld  ")
    expectEqual(HistoryPresentation.selectionIndex(current: 0, delta: -1, count: 3), 0)
    expectEqual(HistoryPresentation.selectionIndex(current: 2, delta: 1, count: 3), 2)
    expectEqual(HistoryPresentation.selectionIndex(current: 2, delta: -1, count: 3), 1)
    expectEqual(HistoryPresentation.selectionIndex(current: 0, delta: 1, count: 0), 0)
}
