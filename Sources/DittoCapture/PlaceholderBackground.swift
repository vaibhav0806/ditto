import AppKit
import ScreenCaptureKit
import DittoCore
import OSLog

public struct PlaceholderBackground: Equatable {
    public let region: CGRect
    public let color: MaskColor

    public init(region: CGRect, color: MaskColor) {
        self.region = region
        self.color = color
    }

    public var ink: NSColor {
        let brightness = 0.2126 * Double(color.red) + 0.7152 * Double(color.green) + 0.0722 * Double(color.blue)
        return (brightness > 140 ? NSColor.black : NSColor.white).withAlphaComponent(0.55)
    }
}

public enum PlaceholderBackgroundSampler {
    private static let logger = Logger(subsystem: "com.vaibhav0806.ditto", category: "Mask")
    public static func capture(region: CGRect, excludingWindows: Set<CGWindowID>, isCurrent: @escaping () -> Bool, completion: @escaping (PlaceholderBackground?) -> Void) {
        guard #available(macOS 14, *), CGPreflightScreenCaptureAccess() else {
            logger.notice("Mask sampling unavailable: OS version or screen permission")
            completion(nil); return
        }
        let scale = NSScreen.screens.first { screen in
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            return screen.frame.contains(NSPoint(x: region.midX, y: top - region.midY))
        }?.backingScaleFactor ?? 1
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
            guard let content, let display = content.displays.first(where: { $0.frame.contains(region) }) else {
                logger.notice("Mask display unavailable; error=\((error as NSError?)?.code ?? 0)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let filter = SCContentFilter(display: display, excludingWindows: content.windows.filter { excludingWindows.contains($0.windowID) })
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = region.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            configuration.width = Int((region.width * scale).rounded(.up))
            configuration.height = Int((region.height * scale).rounded(.up))
            configuration.showsCursor = false
            DispatchQueue.main.async {
                guard isCurrent() else { logger.notice("Mask capture cancelled before sampling: stale target"); completion(nil); return }
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                    DispatchQueue.main.async {
                        guard isCurrent() else { logger.notice("Mask capture discarded: stale target"); completion(nil); return }
                        let color = image.flatMap { classify(image: $0) }
                        logger.notice("Mask sample pixels=\(image?.width ?? 0)x\(image?.height ?? 0) uniform=\(color != nil) error=\((error as NSError?)?.code ?? 0)")
                        completion(color.map { PlaceholderBackground(region: region, color: $0) })
                    }
                }
            }
        }
    }

    public static func classify(image: CGImage) -> MaskColor? {
        let width = image.width
        let height = image.height
        guard width >= 8, height >= 8, width <= 4096, height <= 512 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return rendered ? PlaceholderMask.background(rgba: pixels, width: width, height: height) : nil
    }
}

public final class PlaceholderMaskView: NSView {
    public let background: PlaceholderBackground
    private let caretHole: CGRect

    public init(background: PlaceholderBackground, caret: CGRect) {
        self.background = background
        caretHole = CGRect(x: caret.minX - background.region.minX, y: background.region.maxY - caret.maxY,
                           width: max(1, caret.width), height: caret.height)
        super.init(frame: CGRect(origin: .zero, size: background.region.size))
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let color = background.color
        context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [CGFloat(color.red) / 255, CGFloat(color.green) / 255, CGFloat(color.blue) / 255, 1])!)
        context.fill(bounds)
        context.clear(caretHole)
    }
}
