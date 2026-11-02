import AppKit
import CoreText
import DittoUI

private struct InkExtent {
    var left = Int.max, right = 0, top = Int.max, bottom = 0
    var x = 0.0, y = 0.0, mass = 0.0
}

func runGhostTextChecks(output: String) {
    let tall = NSMutableParagraphStyle()
    tall.minimumLineHeight = 30
    let spaced = NSMutableParagraphStyle()
    spaced.lineHeightMultiple = 1.6
    let cases: [(String, NSFont, String, NSParagraphStyle?, CGFloat?)] = [
        ("helvetica12", NSFont(name: "Helvetica", size: 12)!, "Existing text ", nil, nil),
        ("helvetica16", NSFont(name: "Helvetica", size: 16)!, "Existing text ", nil, nil),
        ("helvetica24", NSFont(name: "Helvetica", size: 24)!, "Existing text ", nil, nil),
        ("menlo14", NSFont(name: "Menlo", size: 14)!, "Existing text ", nil, nil),
        ("georgia18", NSFont(name: "Georgia", size: 18)!, "Existing text ", nil, nil),
        ("system13", .systemFont(ofSize: 13), "Existing text ", nil, nil),
        ("system17", .systemFont(ofSize: 17), "Existing text ", nil, nil),
        ("mono16", .monospacedSystemFont(ofSize: 16, weight: .regular), "Existing text ", nil, nil),
        ("italic16", NSFont(name: "Helvetica-Oblique", size: 16)!, "Existing text ", nil, nil),
        ("empty12", NSFont(name: "Helvetica", size: 12)!, "", nil, nil),
        ("newline12", NSFont(name: "Helvetica", size: 12)!, "First line\n", nil, nil),
        ("tracking16", .systemFont(ofSize: 16), "Existing text ", nil, 1.25),
        ("tall12", NSFont(name: "Helvetica", size: 12)!, "Existing text ", tall, nil),
        ("spacing16", .systemFont(ofSize: 16), "Existing text ", spaced, nil),
        ("bold16", NSFont(name: "Helvetica-Bold", size: 16)!, "Existing text ", nil, nil),
        ("ligature16", NSFont(name: "Helvetica", size: 16)!, "Existing text ", nil, nil)
    ]
    for scale in [1, 2] {
        for (name, font, prefix, paragraph, kern) in cases {
            let suffix = name == "ligature16" ? "café office ffi" : "glyphs gypq Hj"
            let bounds = CGRect(x: 0, y: 0, width: 620, height: 100)
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            if let paragraph { attributes[.paragraphStyle] = paragraph }
            if let kern { attributes[.kern] = kern }
            func native(_ string: String) -> NSTextView {
                let text = NSTextView(frame: bounds)
                text.appearance = NSAppearance(named: .aqua)
                text.textContainerInset = .zero
                text.textContainer?.lineFragmentPadding = 0
                text.backgroundColor = .white
                text.isEditable = false
                text.textStorage?.setAttributedString(NSAttributedString(string: string, attributes: attributes))
                text.layoutManager?.ensureLayout(for: text.textContainer!)
                return text
            }
            let reference = native(prefix + suffix)
            let layout = reference.layoutManager!
            let glyph = layout.glyphIndexForCharacter(at: prefix.utf16.count)
            let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let position = layout.location(forGlyphAt: glyph)
            let caret = CGRect(x: line.minX + position.x, y: bounds.height - line.maxY, width: 0, height: line.height)
            let container = NSView(frame: bounds)
            container.appearance = NSAppearance(named: .aqua)
            container.addSubview(native(prefix))
            let ghost = GhostTextView(text: suffix, style: GhostTextStyle(font: font, attributes: attributes), color: .black, lineHeight: caret.height, maximumWidth: 300)
            ghost.setFrameOrigin(caret.origin)
            container.addSubview(ghost)
            func bitmap(_ view: NSView) -> NSBitmapImageRep {
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width) * scale, pixelsHigh: Int(bounds.height) * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                bitmap.size = bounds.size
                view.cacheDisplay(in: bounds, to: bitmap)
                return bitmap
            }
            func ink(_ bitmap: NSBitmapImageRep) -> InkExtent {
                var result = InkExtent()
                for y in 0..<bitmap.pixelsHigh {
                    for x in max(0, Int((caret.minX * CGFloat(scale)).rounded(.up)))..<min(bitmap.pixelsWide, Int((caret.minX + 280) * CGFloat(scale))) {
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                        let weight = (1 - (color.redComponent + color.greenComponent + color.blueComponent) / 3) * color.alphaComponent
                        if weight > 0.2 {
                            result.left = min(result.left, x); result.right = max(result.right, x)
                            result.top = min(result.top, y); result.bottom = max(result.bottom, y)
                            result.x += Double(x) * weight; result.y += Double(y) * weight; result.mass += weight
                        }
                    }
                }
                return result
            }
            let expectedBitmap = bitmap(reference), actualBitmap = bitmap(container)
            let expected = ink(expectedBitmap), actual = ink(actualBitmap)
            let deltaX = actual.mass > 0 && expected.mass > 0 ? actual.x / actual.mass - expected.x / expected.mass : .infinity
            let deltaY = actual.mass > 0 && expected.mass > 0 ? actual.y / actual.mass - expected.y / expected.mass : .infinity
            let matches = expected.mass > 0 && actual.mass > 0 && abs(deltaX) <= 0.5 && abs(deltaY) <= 0.5 && abs(actual.left - expected.left) <= 1 && abs(actual.right - expected.right) <= 1 && abs(actual.top - expected.top) <= 1 && abs(actual.bottom - expected.bottom) <= 1
            check("native glyphs \(name) at \(scale)x (dx \(String(format: "%.2f", deltaX)), dy \(String(format: "%.2f", deltaY)) pixels)", matches)
            if !matches {
                for (kind, bitmap) in [("native", expectedBitmap), ("ghost", actualBitmap)] {
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output).appendingPathComponent("glyph-\(name)-\(scale)x-\(kind).png"))
                }
            }
            if name == "helvetica16" {
                let sampleView = native(prefix)
                sampleView.textContainerInset = NSSize(width: 0, height: 8)
                let sample = bitmap(sampleView)
                let measured = GhostTextMeasurement.baseline(image: sample.cgImage!, scale: CGFloat(scale), text: prefix, style: GhostTextStyle(font: font), caret: CGRect(x: caret.minX, y: line.minY + 5, width: 0, height: caret.height))
                let desired = GhostTextStyle(font: font).baselineOffset(lineHeight: caret.height) + 3
                check("measured host ink corrects a displaced caret at \(scale)x", measured.map { abs($0.offset - desired) <= 0.5 / CGFloat(scale) } == true)
                let blank = bitmap(native(""))
                check("empty pixels cannot claim a measured baseline at \(scale)x", GhostTextMeasurement.baseline(image: blank.cgImage!, scale: CGFloat(scale), text: prefix, style: GhostTextStyle(font: font), caret: CGRect(x: caret.minX, y: 0, width: 0, height: caret.height)) == nil)
            }
        }
    }
}
