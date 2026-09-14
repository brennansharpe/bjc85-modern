import Foundation
import CoreGraphics
import ImageIO

enum ScanProcessing {
    static func render(source: CGImage, region: ScanRegion, adjustments: ScanAdjustments,
                       blackAndWhite: Bool, threshold: Int) throws -> CGImage {
        guard let rect = region.pixels(width: source.width, height: source.height),
              let image = source.cropping(to: rect), (0...255).contains(threshold),
              adjustments.brightness.isFinite, (-1...1).contains(adjustments.brightness),
              adjustments.contrast.isFinite, (0...2).contains(adjustments.contrast) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if adjustments == ScanAdjustments() && !blackAndWhite { return image }
        let width = image.width, height = image.height
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width*4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        guard drawn else { throw CocoaError(.fileReadCorruptFile) }
        if adjustments.filter != .none {
            let original = bytes
            for y in 0..<height { for x in 0..<width { for c in 0..<3 {
                var values = [Int](); values.reserveCapacity(9)
                for dy in -1...1 { for dx in -1...1 {
                    let py = min(height-1,max(0,y+dy)), px = min(width-1,max(0,x+dx))
                    values.append(Int(original[(py*width+px)*4+c]))
                } }
                let value: Int
                switch adjustments.filter {
                case .soften: value = (values.reduce(0,+)+4)/9
                case .despeckle: value = values.sorted()[4]
                case .sharpen: value = 5*values[4]-values[1]-values[3]-values[5]-values[7]
                case .none: value = values[4]
                }
                bytes[(y*width+x)*4+c] = UInt8(clamping: value)
            } } }
        }
        for p in 0..<(width*height) {
            for c in 0..<3 {
                var value = (Double(bytes[p*4+c])/255 - 0.5)*adjustments.contrast + 0.5 + adjustments.brightness
                if adjustments.invert { value = 1-value }
                bytes[p*4+c] = UInt8(clamping: Int((min(1,max(0,value))*255).rounded()))
            }
            bytes[p*4+3] = 255
        }
        if blackAndWhite {
            let stride = (width+7)/8
            var packed = [UInt8](repeating: 0, count: stride*height)
            for y in 0..<height { for x in 0..<width {
                let p = (y*width+x)*4
                let luminance = (77*Int(bytes[p])+150*Int(bytes[p+1])+29*Int(bytes[p+2])+128)>>8
                if luminance >= threshold { packed[y*stride+x/8] |= UInt8(0x80 >> (x%8)) }
            } }
            guard let provider = CGDataProvider(data: Data(packed) as CFData),
                  let result = CGImage(width: width,height: height,bitsPerComponent: 1,bitsPerPixel: 1,
                    bytesPerRow: stride,space: CGColorSpaceCreateDeviceGray(),bitmapInfo: [],provider: provider,
                    decode: nil,shouldInterpolate: false,intent: .defaultIntent) else { throw CocoaError(.fileReadCorruptFile) }
            return result
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let result = CGImage(width: width,height: height,bitsPerComponent: 8,bitsPerPixel: 32,
                bytesPerRow: width*4,space: space,bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider,decode: nil,shouldInterpolate: false,intent: .defaultIntent) else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }

    static func writePNG(image: CGImage, dpi: Double, destination: URL) throws {
        let data = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(data as CFMutableData,"public.png" as CFString,1,nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(writer,image,[kCGImagePropertyDPIWidth:dpi,kCGImagePropertyDPIHeight:dpi] as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
        try (data as Data).write(to: destination,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:destination.path)
    }
}
