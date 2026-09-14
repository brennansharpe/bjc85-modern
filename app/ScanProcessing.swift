import Foundation
import CoreGraphics
import ImageIO

/// Contract v1: orientation → spatial filter over the whole page (clamped edges)
/// → brightness/contrast/inversion → gray/threshold → rounded crop → encoding.
/// Full-page preview uses this same contract with a full region and a crop overlay.
enum ScanProcessing {
    static func render(source: CGImage, region: ScanRegion, adjustments: ScanAdjustments,
                       blackAndWhite: Bool, threshold: Int, rotation: Int = 0,
                       grayscale: Bool = false, cancelled: () -> Bool = { false }) throws -> CGImage {
        let turns = ((rotation % 4) + 4) % 4
        let width = turns % 2 == 0 ? source.width : source.height
        let height = turns % 2 == 0 ? source.height : source.width
        guard let rect = region.pixels(width: width, height: height), (0...255).contains(threshold),
              adjustments.brightness.isFinite, (-1...1).contains(adjustments.brightness),
              adjustments.contrast.isFinite, (0...2).contains(adjustments.contrast),
              width * height <= 100_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        func check() throws { if cancelled() { throw CancellationError() } }
        try check()
        if adjustments == ScanAdjustments() && !blackAndWhite && !grayscale && turns == 0 {
            guard let result = source.cropping(to: rect) else { throw CocoaError(.fileReadCorruptFile) }
            return result
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        var original = [UInt8](repeating: 0, count: source.width * source.height * 4)
        let drawn = original.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: source.width, height: source.height,
                bitsPerComponent: 8, bytesPerRow: source.width*4, space: space, bitmapInfo: info) else { return false }
            // Flatten alpha on white: scanned paper and imported transparency stay opaque.
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x:0,y:0,width:source.width,height:source.height))
            context.draw(source, in: CGRect(x:0,y:0,width:source.width,height:source.height)); return true
        }
        guard drawn else { throw CocoaError(.fileReadCorruptFile) }
        var bytes = original
        if turns != 0 {
            for y in 0..<height {
                if y % 32 == 0 { try check() }
                for x in 0..<width {
                    let sx: Int, sy: Int
                    switch turns {
                    case 1: sx = y; sy = source.height-1-x
                    case 2: sx = source.width-1-x; sy = source.height-1-y
                    default: sx = source.width-1-y; sy = x
                    }
                    let from = (sy*source.width+sx)*4, to = (y*width+x)*4
                    for c in 0..<4 { bytes[to+c] = original[from+c] }
                }
            }
        }
        if adjustments.filter != .none {
            original = bytes
            // One reusable scratch buffer, no heap allocation per pixel/channel.
            var values = [Int](repeating: 0, count: 9)
            for y in 0..<height {
                if y % 16 == 0 { try check() }
                for x in 0..<width { for c in 0..<3 {
                    var i = 0, sum = 0
                    for dy in -1...1 { for dx in -1...1 {
                        let py = min(height-1,max(0,y+dy)), px = min(width-1,max(0,x+dx))
                        let v = Int(original[(py*width+px)*4+c]); values[i] = v; sum += v; i += 1
                    } }
                    let value: Int
                    switch adjustments.filter {
                    case .soften: value = (sum+4)/9
                    case .despeckle:
                        for j in 1..<9 { let v = values[j]; var k = j; while k > 0 && values[k-1] > v { values[k] = values[k-1]; k -= 1 }; values[k] = v }
                        value = values[4]
                    case .sharpen: value = 5*values[4]-values[1]-values[3]-values[5]-values[7]
                    case .none: value = values[4]
                    }
                    bytes[(y*width+x)*4+c] = UInt8(clamping: value)
                } }
            }
        }
        // A lookup table is equivalent to the specified point operation.
        let lookup = (0...255).map { input -> UInt8 in
            var value = (Double(input)/255-0.5)*adjustments.contrast+0.5+adjustments.brightness
            if adjustments.invert { value = 1-value }
            return UInt8(clamping: Int((min(1,max(0,value))*255).rounded()))
        }
        for y in 0..<height {
            if y % 32 == 0 { try check() }
            for x in 0..<width {
                let p = (y*width+x)*4
                for c in 0..<3 { bytes[p+c] = lookup[Int(bytes[p+c])] }
                bytes[p+3] = 255
            }
        }
        let result: CGImage?
        if blackAndWhite || grayscale {
            // Repack after selecting the rounded crop. CGImage.cropping can
            // produce a bit-offset one-bit provider that ImageIO cannot encode.
            // Threshold is pointwise, so trimming its input yields identical bits.
            let cropWidth=Int(rect.width), cropHeight=Int(rect.height)
            let stride = blackAndWhite ? (cropWidth+7)/8 : cropWidth
            var packed = [UInt8](repeating: 0, count: stride*cropHeight)
            for y in 0..<cropHeight {
                if y % 32 == 0 { try check() }
                for x in 0..<cropWidth {
                    let p = ((y+Int(rect.minY))*width+x+Int(rect.minX))*4
                    let luminance = (77*Int(bytes[p])+150*Int(bytes[p+1])+29*Int(bytes[p+2])+128)>>8
                    if blackAndWhite {
                        if luminance >= threshold { packed[y*stride+x/8] |= UInt8(0x80 >> (x%8)) }
                    } else { packed[y*stride+x] = UInt8(luminance) }
                }
            }
            let provider = CGDataProvider(data: Data(packed) as CFData)!
            guard let gray=CGImage(width:cropWidth,height:cropHeight,bitsPerComponent:blackAndWhite ? 1 : 8,bitsPerPixel:blackAndWhite ? 1 : 8,
                bytesPerRow:stride,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:[],provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { throw CocoaError(.fileReadCorruptFile) }
            return gray
        } else {
            let provider = CGDataProvider(data: Data(bytes) as CFData)!
            result = CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,
                space:space,bitmapInfo:CGBitmapInfo(rawValue:info),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)
        }
        try check()
        guard let cropped = result?.cropping(to: rect) else { throw CocoaError(.fileReadCorruptFile) }
        return cropped
    }
    static func writePNG(image: CGImage, dpi: Double, destination: URL) throws {
        try ScanExport.write(image: image, dpi: dpi, destination: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}
