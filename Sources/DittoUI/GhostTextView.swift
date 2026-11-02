import AppKit
import CoreText

public enum GhostTextMeasurement {
    public struct Baseline {
        public let offset: CGFloat
        public let score: Double
    }

    public static func baseline(image: CGImage, scale: CGFloat, text: String, style: GhostTextStyle, caret: CGRect) -> Baseline? {
        let width = image.width, height = image.height
        guard width >= 8, width <= 1600, height >= 8, height <= 256, scale >= 1, scale <= 4, text.filter({ !$0.isWhitespace }).count >= 4 else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let format = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        var source = [UInt8](repeating: 0, count: width * height * 4)
        guard source.withUnsafeMutableBytes({ data -> Bool in
            guard let context = CGContext(data: data.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: format) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }) else { return nil }
        let corners = [0, (width - 1) * 4, (height - 1) * width * 4, (height * width - 1) * 4]
        let background = (0..<3).map { channel in corners.map { Int(source[$0 + channel]) }.sorted()[2] }
        guard (0..<3).allSatisfy({ channel in corners.allSatisfy { abs(Int(source[$0 + channel]) - background[channel]) <= 8 } }) else { return nil }
        var attributes = style.attributes
        attributes[.foregroundColor] = NSColor.black
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let baseline = style.baselineOffset(lineHeight: caret.height)
        var predicted = [UInt8](repeating: 0, count: source.count)
        guard predicted.withUnsafeMutableBytes({ data -> Bool in
            guard let context = CGContext(data: data.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: format) else { return false }
            context.scaleBy(x: scale, y: scale)
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: caret.minX - advance, y: CGFloat(height) / scale - caret.minY - baseline)
            CTLineDraw(line, context)
            return true
        }) else { return nil }
        let left = max(0, Int(floor((caret.minX - advance - 2) * scale)))
        let right = min(width, Int(ceil(caret.minX * scale)))
        guard right > left else { return nil }
        var actual = [Double](repeating: 0, count: width * height)
        var expected = actual
        var actualNorm = 0.0
        var pixels = 0
        for y in 0..<height {
            for x in left..<right {
                let index = y * width + x, byte = index * 4
                let contrast = (0..<3).map { abs(Double(source[byte + $0]) - Double(background[$0])) / 255 }.max()!
                actual[index] = contrast < 0.06 ? 0 : contrast
                expected[index] = Double(predicted[byte + 3]) / 255
                actualNorm += actual[index] * actual[index]
                if actual[index] > 0 { pixels += 1 }
            }
        }
        guard pixels >= 12, actualNorm > 0 else { return nil }
        var bestScore = 0.0, bestShift = 0
        let limit = Int(6 * scale)
        for shift in -limit...limit {
            var dot = 0.0, norm = 0.0
            for y in max(0, shift)..<min(height, height + shift) {
                for x in left..<right {
                    let value = expected[(y - shift) * width + x]
                    dot += actual[y * width + x] * value
                    norm += value * value
                }
            }
            let score = norm > 0 ? dot / sqrt(actualNorm * norm) : 0
            if score > bestScore { bestScore = score; bestShift = shift }
        }
        guard bestScore >= 0.8, abs(bestShift) < limit else { return nil }
        return Baseline(offset: baseline + CGFloat(bestShift) / scale, score: bestScore)
    }
}

public struct GhostTextStyle {
    public let font: NSFont
    public let reported: Bool
    public let attributes: [NSAttributedString.Key: Any]

    public init(font: NSFont, attributes: [NSAttributedString.Key: Any] = [:], reported: Bool = true) {
        self.font = font
        self.reported = reported
        var values: [NSAttributedString.Key: Any] = [.font: font]
        for key in [NSAttributedString.Key.kern, .ligature, .paragraphStyle, .baselineOffset, .expansion, .obliqueness] {
            values[key] = attributes[key]
        }
        self.attributes = values
    }

    public func baselineOffset(lineHeight: CGFloat) -> CGFloat {
        let storage = NSTextStorage(string: "Hg", attributes: attributes)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 1000, height: 1000))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let line = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        return manager.location(forGlyphAt: 0).y + max(0, lineHeight - line.height)
    }
}

public final class GhostTextView: NSView {
    public let text: String
    public let style: GhostTextStyle
    public var baselineOffsetFromTop: CGFloat { didSet { needsDisplay = true } }
    public var penOffset = CGPoint.zero { didSet { needsDisplay = true } }
    private let line: CTLine

    public init(text: String, style: GhostTextStyle, color: NSColor, lineHeight: CGFloat, maximumWidth: CGFloat, baselineOffset: CGFloat? = nil) {
        self.text = text
        self.style = style
        baselineOffsetFromTop = baselineOffset ?? style.baselineOffset(lineHeight: lineHeight)
        var attributes = style.attributes
        attributes[.foregroundColor] = color
        let full = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let width = max(1, maximumWidth)
        let advance = CGFloat(CTLineGetTypographicBounds(full, nil, nil, nil))
        if advance > width {
            let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
            line = CTLineCreateTruncatedLine(full, Double(width), .end, ellipsis) ?? CTLineCreateWithAttributedString(NSAttributedString(string: ""))
        } else { line = full }
        let drawnWidth = min(width, max(1, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) + 2))
        super.init(frame: CGRect(x: 0, y: 0, width: drawnWidth, height: lineHeight))
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Ditto completion")
        setAccessibilityValue(text)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    public override var isOpaque: Bool { false }

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: penOffset.x, y: bounds.height - baselineOffsetFromTop + penOffset.y)
        CTLineDraw(line, context)
    }
}
