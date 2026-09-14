import Foundation
import CoreGraphics
import ImageIO
@main struct ProcessingTests {
    static func main() throws {
        let bytes: [UInt8] = [0,0,0,255, 80,80,80,255, 160,160,160,255, 255,255,255,255]
        let provider=CGDataProvider(data:Data(bytes) as CFData)!
        let source=CGImage(width:4,height:1,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:16,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
            provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        let bw=try ScanProcessing.render(source:source,region:.fullPage,adjustments:.init(),blackAndWhite:true,threshold:128)
        precondition(bw.bitsPerPixel==1 && bw.width==4)
        let packed=bw.dataProvider!.data! as Data
        precondition(packed[0]&0xf0 == 0x30)
        let inverted=try ScanProcessing.render(source:source,region:.fullPage,adjustments:.init(invert:true),blackAndWhite:true,threshold:128)
        precondition((inverted.dataProvider!.data! as Data)[0]&0xf0 == 0xc0)
        let crop=ScanRegion(x:0.25,y:0,width:0.5,height:1)
        let result=try ScanProcessing.render(source:source,region:crop,adjustments:.init(),blackAndWhite:false,threshold:128)
        precondition(result.width==2 && result.height==1)
        precondition(crop.rotated180.rotated180==crop)
        let region=ScanRegion(x:0.125,y:0.25,width:0.5,height:0.5)
        precondition(region.pixels(width:2880,height:3888)==CGRect(x:360,y:972,width:1440,height:1944))
        precondition(ScanRegion(x:-0.1).pixels(width:2880,height:3888)==nil)
        for filter in ScanFilter.allCases {
            let filtered=try ScanProcessing.render(source:source,region:.fullPage,adjustments:.init(filter:filter),blackAndWhite:false,threshold:128)
            precondition(filtered.width==4 && filtered.height==1)
        }
        print("Crop coordinates, 180° mapping, threshold bits, inversion and filter edge bounds pass.")
    }
}
