import Foundation
import ImageIO
import CoreGraphics

/// Budget: 512 MiB for decoded pixels plus working/encoding buffers, estimated
/// conservatively at 40 bytes/pixel (including 16-bit RGBA and intermediate
/// buffers). Compressed input has a separate 128 MiB cap. No downsampling.
enum RasterImport {
    static let memoryBudget: UInt64 = 512 * 1024 * 1024
    static func validate(width: Double, height: Double, depth: Double) throws {
        guard width.isFinite, height.isFinite, depth.isFinite,
              width > 0, height > 0, width.rounded(.down)==width, height.rounded(.down)==height,
              width <= 20000, height <= 20000, [1,2,4,8,16].contains(depth) else { throw DocumentError.corrupt }
        let (pixels, overflow)=UInt64(width).multipliedReportingOverflow(by:UInt64(height))
        let (bytes, byteOverflow)=pixels.multipliedReportingOverflow(by:40)
        guard !overflow, !byteOverflow, pixels <= 100_000_000, bytes <= memoryBudget else { throw DocumentError.quota }
    }
    /// Read the dimensions that drive decoding, independently of EXIF values
    /// that ImageIO may project over top-level PixelWidth/PixelHeight.
    static func dimensions(_ data:Data, type:String) throws -> (Double,Double,Double) {
        let bytes=[UInt8](data)
        func number(_ offset:Int,_ count:Int,_ little:Bool=false) throws -> UInt64 {
            guard offset>=0, count>0, count<=8, offset<=bytes.count-count else { throw DocumentError.corrupt }
            var result:UInt64=0
            for index in 0..<count { result=(result<<8)|UInt64(bytes[offset+(little ? count-1-index : index)]) }
            return result
        }
        if type=="public.png" {
            guard bytes.count>=33, String(bytes:bytes[12..<16],encoding:.ascii)=="IHDR", try number(8,4)==13 else { throw DocumentError.corrupt }
            return (Double(try number(16,4)),Double(try number(20,4)),Double(bytes[24]))
        }
        if type=="public.jpeg" {
            var offset=2
            while offset<bytes.count-1 {
                guard bytes[offset]==255 else { throw DocumentError.corrupt }
                while offset<bytes.count && bytes[offset]==255 { offset += 1 }
                guard offset<bytes.count else { throw DocumentError.corrupt }
                let marker=bytes[offset]; offset += 1
                if marker==0xd9 || marker==0xda { break }
                if marker==0x01 || (0xd0...0xd7).contains(marker) { continue }
                let length=Int(try number(offset,2))
                guard length>=2, offset<=bytes.count-length else { throw DocumentError.corrupt }
                if (0xc0...0xcf).contains(marker) && ![0xc4,0xc8,0xcc].contains(marker) {
                    guard length>=8, (1...4).contains(bytes[offset+7]) else { throw DocumentError.corrupt }
                    return (Double(try number(offset+5,2)),Double(try number(offset+3,2)),Double(bytes[offset+2]))
                }
                offset += length
            }
            throw DocumentError.corrupt
        }
        // Classic TIFF's first IFD controls the retained first page. BigTIFF
        // and unsupported scalar/count representations fail explicitly.
        guard bytes.count>=8 else { throw DocumentError.corrupt }
        let little=bytes[0]==0x49 && bytes[1]==0x49
        guard little || (bytes[0]==0x4d && bytes[1]==0x4d), try number(2,2,little)==42 else { throw DocumentError.corrupt }
        let ifd=Int(try number(4,4,little)), count=Int(try number(ifd,2,little))
        guard count<=4096 else { throw DocumentError.corrupt }
        var fields:[Int:Double]=[:]
        for index in 0..<count {
            let offset=ifd+2+index*12, tag=Int(try number(offset,2,little))
            guard [256,257,258].contains(tag) else { continue }
            let kind=try number(offset+2,2,little), items=try number(offset+4,4,little)
            guard (kind==3 || kind==4), items>0, items<=4, fields[tag]==nil else { throw DocumentError.corrupt }
            let width=kind==3 ? 2 : 4
            let valueOffset=Int(items)*width<=4 ? offset+8 : Int(try number(offset+8,4,little))
            let value=try number(valueOffset,width,little)
            if tag != 258 && items != 1 { throw DocumentError.corrupt }
            for item in 0..<Int(items) { guard try number(valueOffset+item*width,width,little)==value else { throw DocumentError.corrupt } }
            fields[tag]=Double(value)
        }
        guard let width=fields[256], let height=fields[257] else { throw DocumentError.corrupt }
        return (width,height,fields[258] ?? 1)
    }
    static func decode(_ url: URL, decoder: (CGImageSource) -> CGImage? = {
        CGImageSourceCreateImageAtIndex($0,0,[kCGImageSourceShouldCacheImmediately:true] as CFDictionary)
    }) throws -> (CGImage,Double) {
        let size=(try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber)?.uint64Value
        guard let size, size > 0, size <= 128 * 1024 * 1024 else { throw DocumentError.quota }
        // Own an immutable byte snapshot; metadata and decode use this SAME
        // source even if another process replaces the original filename.
        let handle=try FileHandle(forReadingFrom:url); defer { try? handle.close() }
        guard let data=try handle.read(upToCount:128 * 1024 * 1024 + 1) else { throw DocumentError.corrupt }
        guard data.count <= 128 * 1024 * 1024,
              let source=CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
              let type=CGImageSourceGetType(source) as String?,
              ["public.png","public.jpeg","public.tiff"].contains(type),
              CGImageSourceGetCount(source)>0 else { throw DocumentError.corrupt }
        let (containerWidth,containerHeight,containerDepth)=try dimensions(data,type:type)
        try validate(width:containerWidth,height:containerHeight,depth:containerDepth)
        guard let properties=CGImageSourceCopyPropertiesAtIndex(source,0,[kCGImageSourceShouldCache:false] as CFDictionary) as? [CFString:Any],
              let width=properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height=properties[kCGImagePropertyPixelHeight] as? NSNumber,
              let depth=properties[kCGImagePropertyDepth] as? NSNumber else { throw DocumentError.corrupt }
        guard width.doubleValue==containerWidth, height.doubleValue==containerHeight else { throw DocumentError.corrupt }
        try validate(width:width.doubleValue,height:height.doubleValue,depth:depth.doubleValue)
        guard let image=decoder(source), image.width==width.intValue, image.height==height.intValue else { throw DocumentError.corrupt }
        try validate(width:Double(image.width),height:Double(image.height),depth:Double(image.bitsPerComponent))
        let dpi=(properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        guard dpi.isFinite, dpi>0 else { throw DocumentError.corrupt }
        return (image,dpi)
    }
}
