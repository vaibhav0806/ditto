import AppKit
import ScreenCaptureKit
import DittoCore
import OSLog

public struct PlaceholderBackground: Equatable {
    public let region: CGRect
    public let color: MaskColor
    public let colorSpace: CGColorSpace

    public init(region: CGRect, color: MaskColor, colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) {
        self.region = region
        self.color = color
        self.colorSpace = colorSpace
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.region == rhs.region && lhs.color == rhs.color && CFEqual(lhs.colorSpace, rhs.colorSpace)
    }

    public var ink: NSColor {
        let brightness = 0.2126 * Double(color.red) + 0.7152 * Double(color.green) + 0.0722 * Double(color.blue)
        return (brightness > 140 ? NSColor.black : NSColor.white).withAlphaComponent(0.55)
    }
}

public struct PlaceholderSample {
    public let background: PlaceholderBackground
    public let image: CGImage
    public let scale: CGFloat
}

public enum PlaceholderBackgroundSampler {
    private static let logger = Logger(subsystem: "com.vaibhav0806.ditto", category: "Mask")
    public static func capture(region: CGRect, caret: CGRect? = nil, pid: pid_t, excludingWindows: Set<CGWindowID>, isCurrent: @escaping () -> Bool, completion: @escaping (PlaceholderSample?) -> Void) {
        guard #available(macOS 14, *), CGPreflightScreenCaptureAccess() else {
            logger.notice("Mask sampling unavailable: OS version or screen permission")
            completion(nil); return
        }
        let scale = NSScreen.screens.first { screen in
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            return screen.frame.contains(NSPoint(x: region.midX, y: top - region.midY))
        }?.backingScaleFactor ?? 1
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
            guard let content, let display = content.displays.first(where: { $0.frame.contains(region) }),
                  let application = content.applications.first(where: { $0.processID == pid }) else {
                logger.notice("Mask display unavailable; error=\((error as NSError?)?.code ?? 0)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let filter = SCContentFilter(display: display, including: [application], exceptingWindows: content.windows.filter { excludingWindows.contains($0.windowID) })
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
                        let columns = caret.map { Int(floor(($0.minX - region.minX - 1) * scale))..<Int(ceil(($0.maxX - region.minX + 1) * scale)) }
                        let color = image.flatMap { classify(image: $0, excludingColumns: columns) }
                        logger.notice("Mask sample pixels=\(image?.width ?? 0)x\(image?.height ?? 0) uniform=\(color != nil) error=\((error as NSError?)?.code ?? 0)")
                        completion(image.flatMap { image in
                            guard let color, let space = image.colorSpace else { return nil }
                            return PlaceholderSample(background: PlaceholderBackground(region: region, color: color, colorSpace: space), image: image, scale: scale)
                        })
                    }
                }
            }
        }
    }

    public static func classify(image: CGImage, excludingColumns: Range<Int>? = nil) -> MaskColor? {
        let width = image.width
        let height = image.height
        guard width >= 8, height >= 8, width <= 4096, height <= 512,
              let colorSpace = image.colorSpace, colorSpace.model == .rgb else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return rendered ? PlaceholderMask.background(rgba: pixels, width: width, height: height, excludingColumns: excludingColumns) : nil
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
        context.setFillColor(CGColor(colorSpace: background.colorSpace, components: [CGFloat(color.red) / 255, CGFloat(color.green) / 255, CGFloat(color.blue) / 255, 1])!)
        context.fill(bounds)
        context.clear(caretHole)
    }
}
