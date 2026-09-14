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
            throw NSError(domain: "BJC85", code: 2, userInfo: [NSLocalizedDescriptionKey: L("The saved image has no usable scan resolution.")])
        }
        // PNG pixels-per-metre metadata rounds these exact device resolutions.
        if let native = [90.0, 180.0, 360.0].first(where: { abs($0-x) < 0.05 }) { return native }
        return x
    }

    static func write(source: URL, destination: URL) throws {
        guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(input, 0, nil) else { throw CocoaError(.fileReadCorruptFile) }
        let resolution=try dpi(of:source), ext=destination.pathExtension.lowercased()
        if ext == "png", CGImageSourceGetType(input) as String? == "public.png" {
            // Preserve one-bit PNG representation: ImageIO's decoded CGImage
            // may expand it to eight bits even though its pixels are unchanged.
            try Data(contentsOf:source).write(to:destination,options:.atomic)
        } else if ["tiff","tif"].contains(ext) {
            let data=NSMutableData()
            guard let writer=CGImageDestinationCreateWithData(data as CFMutableData,"public.tiff" as CFString,1,nil) else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImageFromSource(writer,input,0,[kCGImagePropertyDPIWidth:resolution,kCGImagePropertyDPIHeight:resolution,kCGImagePropertyTIFFDictionary:[kCGImagePropertyTIFFCompression:5]] as CFDictionary)
            guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
            try (data as Data).write(to:destination,options:.atomic)
        } else { try write(image:image,dpi:resolution,destination:destination) }
        guard FileManager.default.isReadableFile(atPath:destination.path) else { throw CocoaError(.fileReadCorruptFile) }
    }
    static func write(image: CGImage, dpi: Double, destination: URL, cancelled: () -> Bool = { false }) throws {
        guard dpi.isFinite, dpi > 0 else { throw CocoaError(.fileWriteUnknown) }
        let data = NSMutableData()
        switch destination.pathExtension.lowercased() {
        case "png", "tif", "tiff":
            let uti = destination.pathExtension.lowercased() == "png" ? "public.png" : "public.tiff"
            guard let writer = CGImageDestinationCreateWithData(data as CFMutableData, uti as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(writer, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi,
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5]] as CFDictionary)
            guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
        case "pdf":
            var bounds = CGRect(x: 0, y: 0, width: Double(image.width)*72/dpi, height: Double(image.height)*72/dpi)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { throw CocoaError(.fileWriteUnknown) }
            context.beginPDFPage(nil); context.draw(image, in: bounds); context.endPDFPage(); context.closePDF()
        default: throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        // Atomic write never exposes partial encoding or truncates a good output on failure.
        if cancelled() { throw CancellationError() }
        try (data as Data).write(to: destination, options: .atomic)
        guard FileManager.default.isReadableFile(atPath: destination.path),
              (try Data(contentsOf: destination, options: .mappedIfSafe)).count == data.length else { throw CocoaError(.fileReadCorruptFile) }
    }
}
