import Foundation
import CoreGraphics

public struct MaskColor: Equatable, Hashable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public enum PlaceholderMask {
    public static func region(field: CGRect, caret: CGRect) -> CGRect? {
        guard [field.minX, field.minY, field.width, field.height, caret.minX, caret.minY, caret.width, caret.height].allSatisfy(\.isFinite),
              caret.height > 0, caret.height <= 64, caret.minX >= field.minX, caret.maxX <= field.maxX,
              caret.minY - 4 >= field.minY, caret.maxY + 4 <= field.maxY else { return nil }
        let x = max(field.minX, caret.minX - 4)
        let width = field.maxX - 6 - x
        guard width >= 40, width <= 1800 else { return nil }
        return CGRect(x: x, y: caret.minY - 4, width: width, height: caret.height + 8)
    }

    public static func background(rgba: [UInt8], width: Int, height: Int) -> MaskColor? {
        guard width >= 8, height >= 8, width <= 4096, height <= 512,
              rgba.count == width * height * 4 else { return nil }
        var counts: [MaskColor: Int] = [:]
        var minimum = [255, 255, 255]
        var maximum = [0, 0, 0]
        var total = 0
        for y in 0..<height {
            for x in 0..<width where y < 2 || y >= height - 2 || x >= width - 2 {
                let i = (y * width + x) * 4
                guard rgba[i + 3] == 255 else { return nil }
                for channel in 0..<3 {
                    minimum[channel] = min(minimum[channel], Int(rgba[i + channel]))
                    maximum[channel] = max(maximum[channel], Int(rgba[i + channel]))
                    guard maximum[channel] - minimum[channel] <= 2 else { return nil }
                }
                counts[MaskColor(red: rgba[i], green: rgba[i + 1], blue: rgba[i + 2]), default: 0] += 1
                total += 1
            }
        }
        let ranked = counts.sorted { $0.value > $1.value }
        guard let dominant = ranked.first,
              ranked.count < 2 || ranked[1].value * 100 <= total * 25 else { return nil }
        for color in counts.keys {
            guard abs(Int(color.red) - Int(dominant.key.red)) <= 1,
                  abs(Int(color.green) - Int(dominant.key.green)) <= 1,
                  abs(Int(color.blue) - Int(dominant.key.blue)) <= 1 else { return nil }
        }
        return dominant.key
    }
}
