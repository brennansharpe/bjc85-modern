import Foundation
import CoreGraphics
import ImageIO

/// Shared by the app and an offline export verifier. Keep the scanner's pixels
/// and physical dimensions; no colour, threshold, or contrast correction here.
enum ScanExport {
    static func dpi(of source: URL) throws -> Double {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let x = properties[kCGImagePropertyDPIWidth] as? Double,
              let y = properties[kCGImagePropertyDPIHeight] as? Double,
              x.isFinite, y.isFinite, x > 0, abs(x-y) < 0.1 else {
            throw NSError(domain: "BJC85", code: 2, userInfo: [NSLocalizedDescriptionKey: "The saved image has no usable scan resolution."])
        }
        // PNG pixels-per-metre metadata rounds these exact device resolutions.
        if let native = [90.0, 180.0, 360.0].first(where: { abs($0-x) < 0.05 }) { return native }
        return x
    }

    static func write(source: URL, destination: URL) throws {
        let input = try Data(contentsOf: source)
        guard let imageSource = CGImageSourceCreateWithData(input as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { throw CocoaError(.fileReadCorruptFile) }
        let resolution = try dpi(of: source)
        let output: Data
        switch destination.pathExtension.lowercased() {
        case "png": output = input
        case "tif", "tiff":
            let data = NSMutableData()
            guard let writer = CGImageDestinationCreateWithData(data as CFMutableData, "public.tiff" as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImageFromSource(writer, imageSource, 0, [kCGImagePropertyDPIWidth: resolution,
                kCGImagePropertyDPIHeight: resolution,
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5]] as CFDictionary)
            guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
            output = data as Data
        case "pdf":
            let data = NSMutableData()
            var bounds = CGRect(x: 0, y: 0, width: Double(image.width)*72/resolution, height: Double(image.height)*72/resolution)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { throw CocoaError(.fileWriteUnknown) }
            context.beginPDFPage(nil); context.draw(image, in: bounds); context.endPDFPage(); context.closePDF()
            output = data as Data
        default: throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try output.write(to: destination, options: .atomic)
    }
}
