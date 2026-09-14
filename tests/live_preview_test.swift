import Foundation
import CoreGraphics

@main
struct Test {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("live-preview.rgb")
        let first = Data([255,0,0, 0,255,0])
        try first.write(to: path)
        let model = LiveScanPreview(directory: directory)
        func bytes(_ image: CGImage) -> Data { image.dataProvider!.data! as Data }
        let frame = try model.update(width: 2, height: 3, rows: 1, rotate180: false)
        assert(bytes(frame) == first + Data(repeating: 230, count: 12))
        let rotated = try model.update(width: 2, height: 3, rows: 1, rotate180: true)
        assert(bytes(rotated) == Data(repeating: 230, count: 12) + Data([0,255,0, 255,0,0]))
        do {
            _ = try model.update(width: 2, height: 3, rows: 2, rotate180: false)
            assertionFailure("An announced incomplete row must be rejected")
        } catch LiveScanPreview.PreviewError.incompleteFrame {}
        // A later retry sees the complete bytes without duplicating the first row.
        let full = first + Data([0,0,255, 255,255,255, 0,0,0, 128,128,128])
        try full.write(to: path)
        let complete = try model.update(width: 2, height: 3, rows: 3, rotate180: false)
        assert(bytes(complete) == full)
        for (width, height, rows) in [(0,3,3), (751,3,3), (2,1251,3), (2,3,4), (2,3,2), (3,3,3)] {
            do {
                _ = try model.update(width: width, height: height, rows: rows, rotate180: false)
                assertionFailure("Invalid frame geometry or rewind was accepted")
            } catch LiveScanPreview.PreviewError.invalidFrame {}
        }
        // The already rendered snapshot must remain immutable after later updates.
        assert(bytes(frame) == first + Data(repeating: 230, count: 12))
        print("Live preview rendering: partial fill, rotation, append, bounds, immutable snapshots passed")
    }
}
