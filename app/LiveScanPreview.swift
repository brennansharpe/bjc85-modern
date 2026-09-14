import Foundation
import CoreGraphics

// Confined to the app's serial preview queue. The helper appends 90 dpi RGB rows
// and announces them only after flushing. Never decode the growing final PNG.
final class LiveScanPreview: @unchecked Sendable {
    let directory: URL
    private var width = 0
    private var height = 0
    private var rows = 0
    private var pixels = Data()

    init(directory: URL) { self.directory = directory }

    func update(width: Int, height: Int, rows: Int, rotate180: Bool) throws -> CGImage {
        guard width > 0, width <= 750, height > 0, height <= 1250,
              rows > 0, rows <= height, rows >= self.rows,
              self.width == 0 || (self.width == width && self.height == height) else {
            throw PreviewError.invalidFrame
        }
        let expected = width * rows * 3
        if expected > pixels.count {
            let input = try FileHandle(forReadingFrom: directory.appendingPathComponent("live-preview.rgb"))
            defer { try? input.close() }
            try input.seek(toOffset: UInt64(pixels.count))
            let added = try input.read(upToCount: expected - pixels.count) ?? Data()
            guard added.count == expected - pixels.count else { throw PreviewError.incompleteFrame }
            pixels.append(added)
        }
        self.width = width; self.height = height; self.rows = rows
        // Gray means not yet scanned; real white paper appears as it arrives.
        var canvas = Data(repeating: 230, count: width * height * 3)
        canvas.replaceSubrange(0..<pixels.count, with: pixels)
        if rotate180 {
            canvas.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
                let count = width * height
                for p in 0..<(count / 2) {
                    for c in 0..<3 { bytes.swapAt(p * 3 + c, (count - 1 - p) * 3 + c) }
                }
            }
        }
        guard let provider = CGDataProvider(data: canvas as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                                  bytesPerRow: width * 3, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent) else {
            throw PreviewError.invalidFrame
        }
        return image
    }

    enum PreviewError: Error { case invalidFrame, incompleteFrame }
}
