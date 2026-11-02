import Foundation
import CoreGraphics
import DittoCore
import DittoCapture
import AppKit

func testUniformBackgroundPreservesExactColor() {
    for color in [MaskColor(red: 17, green: 17, blue: 17), MaskColor(red: 255, green: 255, blue: 255), MaskColor(red: 34, green: 37, blue: 41)] {
        var pixels: [UInt8] = Array(repeating: [color.red, color.green, color.blue, UInt8(255)], count: 40 * 24).flatMap { $0 }
        for y in 6..<18 {
            for x in 5..<25 {
                let i = (y * 40 + x) * 4
                pixels[i] = 150; pixels[i + 1] = 150; pixels[i + 2] = 150
            }
        }
        expectEqual(PlaceholderMask.background(rgba: pixels, width: 40, height: 24), color)
    }
}

func testRenderedMaskUsesExactSampleAndPreservesCaretTransparency() throws {
    for scale in [1, 2] {
        for color in [MaskColor(red: 17, green: 17, blue: 17), MaskColor(red: 255, green: 255, blue: 255), MaskColor(red: 34, green: 37, blue: 41)] {
            let width = 40 * scale
            let height = 24 * scale
            let space = try unwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            let source = try unwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: info))
            source.setFillColor(try unwrap(CGColor(colorSpace: space, components: [CGFloat(color.red) / 255, CGFloat(color.green) / 255, CGFloat(color.blue) / 255, 1])))
            source.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let sampled = try unwrap(PlaceholderBackgroundSampler.classify(image: try unwrap(source.makeImage())))
            expectEqual(sampled, color)
            let background = PlaceholderBackground(region: CGRect(x: 0, y: 0, width: 40, height: 24), color: sampled)
            let view = PlaceholderMaskView(background: background, caret: CGRect(x: 2, y: 4, width: 1, height: 16))
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            pixels.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: info)!
                context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                view.draw(view.bounds)
                NSGraphicsContext.restoreGraphicsState()
            }
            var exact = true
            for y in 0..<height {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    if x >= 2 * scale && x < 3 * scale && y >= 4 * scale && y < 20 * scale {
                        exact = exact && pixels[i + 3] == 0
                    } else {
                        exact = exact && pixels[i] == color.red && pixels[i + 1] == color.green && pixels[i + 2] == color.blue && pixels[i + 3] == 255
                    }
                }
            }
            expectTrue(exact)
        }
    }
}

func testAmbiguousBackgroundIsNotReplacedWithAnAverage() {
    let gradient = (0..<(40 * 24)).flatMap { i -> [UInt8] in [UInt8(i % 40), 20, 30, 255] }
    expectNil(PlaceholderMask.background(rgba: gradient, width: 40, height: 24))
    let texture = (0..<(40 * 24)).flatMap { i -> [UInt8] in [i.isMultiple(of: 2) ? 20 : 21, 20, 20, 255] }
    expectNil(PlaceholderMask.background(rgba: texture, width: 40, height: 24))
    expectNil(PlaceholderMask.background(rgba: Array(repeating: 0, count: 40 * 24 * 4), width: 40, height: 24))
    expectNil(PlaceholderMask.background(rgba: [255], width: 40, height: 24))
}

func testMaskStaysInsideTheInputAndCoversThePlaceholderLine() {
    let field = CGRect(x: 10, y: 20, width: 400, height: 100)
    let caret = CGRect(x: 26, y: 36, width: 0, height: 18)
    guard let region = PlaceholderMask.region(field: field, caret: caret) else { expectTrue(false); return }
    expectTrue(field.contains(region))
    expectTrue(region.minX <= caret.minX)
    expectTrue(region.minY < caret.minY)
    expectTrue(region.maxY > caret.maxY)
    expectTrue(region.maxX > caret.maxX + 300)
    expectNil(PlaceholderMask.region(field: field, caret: CGRect(x: 26, y: 36, width: 0, height: 0)))
    expectNil(PlaceholderMask.region(field: field, caret: CGRect(x: 500, y: 36, width: 1, height: 18)))
    expectNil(PlaceholderMask.region(field: field, caret: CGRect(x: 26, y: 20, width: 1, height: 18)))
}
