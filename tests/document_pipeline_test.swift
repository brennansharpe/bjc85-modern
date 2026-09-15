import AppKit
import ImageIO

func expect(_ condition: @autoclosure () -> Bool, _ message:String = "", line:UInt = #line) { if !condition() { print("FAILED at line \(line): \(message)"); exit(1) } }
func fixture(_ width:Int=31,_ height:Int=43) -> CGImage {
    var bytes=[UInt8](repeating:255,count:width*height*4)
    for y in 0..<height { for x in 0..<width {
        let p=(y*width+x)*4
        bytes[p]=UInt8((x*13+y*5)%256); bytes[p+1]=UInt8((x*3+y*11)%256); bytes[p+2]=UInt8((x*7+y*2)%256)
        if x%7==0 || y%11==0 { bytes[p]=0;bytes[p+1]=0;bytes[p+2]=0 }
    } }
    for (x,y,r,g,b) in [(0,0,255,0,0),(width-1,0,0,255,0),(0,height-1,0,0,255),(width-1,height-1,255,255,0)] {
        let p=(y*width+x)*4; bytes[p]=UInt8(r); bytes[p+1]=UInt8(g); bytes[p+2]=UInt8(b)
    }
    return CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),provider:CGDataProvider(data:Data(bytes) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
}
func pixels(_ image:CGImage) -> Data {
    var bytes=[UInt8](repeating:0,count:image.width*image.height*4)
    bytes.withUnsafeMutableBytes {
        let context=CGContext(data:$0.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
    }; return Data(bytes)
}
func check(_ condition: @autoclosure () throws -> Bool) rethrows { let value=try condition(); expect(value) }
@main struct DocumentPipelineTests {
    static func main() throws {
        setbuf(stdout,nil)
        let fm=FileManager.default, root=fm.temporaryDirectory.appendingPathComponent("bjc85-doc-test-\(UUID())")
        try fm.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]); defer { try? fm.removeItem(at:root) }
        let runtime=root.appendingPathComponent("private"), source=root.appendingPathComponent("source.png")
        try ScanProcessing.writePNG(image:fixture(),dpi:360,destination:source)
        let store=try ScanDocumentStore(runtime:runtime)
        var document=try store.importImage(source), master=try Data(contentsOf:store.master(try store.restore()!.id))
        let id=document.id, acquisition=document.acquisition
        let snapshot=try store.snapshot(document)
        do { try store.discard(id); preconditionFailure("pinned document deleted") } catch DocumentError.busy { }
        let alias=root.appendingPathComponent("alias"); try fm.createSymbolicLink(at:alias,withDestinationURL:runtime)
        let hard=root.appendingPathComponent("hard.png"); try fm.linkItem(at:store.master(id),to:hard)
        for destination in [runtime.appendingPathComponent("processed.png"),store.master(id),alias.appendingPathComponent("processed.png"),hard] {
            do { try FileIdentity.validateExport(destination,runtime:runtime,protected:[snapshot.master]); print("unsafe destination: \(destination.path), runtime \(runtime.path)"); exit(1) } catch { }
        }
        for ext in ["png","tiff","pdf"] {
            let destination=root.appendingPathComponent("export."+ext)
            try FileIdentity.validateExport(destination,runtime:runtime,protected:[snapshot.master])
            try ScanExport.write(source:snapshot.master,destination:destination)
            document.exports.append(.init(destination:destination,revision:document.revision,date:Date())); try store.save(document)
            expect(fm.isReadableFile(atPath:destination.path))
            if ext != "pdf" { let input=CGImageSourceCreateWithURL(destination as CFURL,nil)!; expect(pixels(CGImageSourceCreateImageAtIndex(input,0,nil)!)==pixels(fixture())); try check(abs(try ScanExport.dpi(of:destination)-360)<0.05) }
            else { let pdf=CGPDFDocument(destination as CFURL)!; expect(abs(pdf.page(at:1)!.getBoxRect(.mediaBox).width-31.0*72/360)<0.01) }
        }
        expect(!document.needsExport && document.exports.count==3)
        document.edits.adjustments.brightness=0.1; document.revision += 1; try store.save(document)
        expect(document.needsExport && document.acquisition==acquisition)
        try check(try Data(contentsOf:store.master(id))==master)
        let good=root.appendingPathComponent("good.png"); try ScanExport.write(source:source,destination:good); let old=try Data(contentsOf:good)
        do { try ScanExport.write(image:fixture(),dpi:360,destination:good,cancelled:{true}); preconditionFailure() } catch is CancellationError { }
        try check(try Data(contentsOf:good)==old)
        do { try ScanExport.write(source:source,destination:root.appendingPathComponent("missing/fail.png")); preconditionFailure() } catch { }
        try check(try Data(contentsOf:store.master(id))==master)
        let capture=runtime.appendingPathComponent("capture"); try fm.createDirectory(at:capture,withIntermediateDirectories:true)
        let unsaved=capture.appendingPathComponent("processed.png"); try master.write(to:unsaved)
        try Data([1,2]).write(to:capture.appendingPathComponent("records.bin"))
        try PrivacyRetention.removeExportedCapture(capture,retainDiagnostics:false,outcome:.completedSafe,protected:[unsaved,store.directory])
        expect(fm.isReadableFile(atPath:unsaved.path)); expect(!fm.fileExists(atPath:capture.appendingPathComponent("records.bin").path))
        try Data([1,2]).write(to:capture.appendingPathComponent("records.bin"))
        try PrivacyRetention.removeExportedCapture(capture,retainDiagnostics:false,outcome:.recoveryRequired)
        expect(fm.fileExists(atPath:capture.appendingPathComponent("records.bin").path))
        document.retainedCopies.insert(id); try store.save(document)
        try store.close(document,now:Date(timeIntervalSince1970:0)); try store.purgeExportedClosed()
        try check(try store.load(id).id==id)
        try store.activate(id); let relaunched=try ScanDocumentStore(runtime:runtime); try check(try relaunched.restore()?.id==document.id)
        // Isolate Copy retention from dirty state and worker pins: this closed,
        // exported document has no active pin and would otherwise be expired.
        var copyOnly=try store.importImage(source)
        copyOnly.exports.append(.init(destination:good,revision:0,date:Date()))
        copyOnly.retainedCopies.insert(UUID())
        try store.close(copyOnly,now:Date(timeIntervalSince1970:0)); try store.purgeExportedClosed()
        try check(try store.load(copyOnly.id).id==copyOnly.id)
        copyOnly.retainedCopies.removeAll(); copyOnly.closedAt=Date(timeIntervalSince1970:0); try store.save(copyOnly)
        try store.purgeExportedClosed(); expect(fm.fileExists(atPath:store.master(copyOnly.id).path))
        try store.discard(copyOnly.id); expect(!fm.fileExists(atPath:store.master(copyOnly.id).path))
        print("PASS: Copy ownership independently blocks exported-document expiry; explicit disposal permits cleanup without touching external output.")
        let restoredPDF=try store.importImage(root.appendingPathComponent("export.pdf"))
        expect(restoredPDF.acquisition.dpi==360 && restoredPDF.acquisition.source.contains("rasterized"))
        let legacy=runtime.appendingPathComponent(".state/scanner-app/scan-fixture")
        try fm.createDirectory(at:legacy,withIntermediateDirectories:true)
        try master.write(to:legacy.appendingPathComponent("scan-raw.png"))
        try JSONSerialization.data(withJSONObject:["schema_version":1,"outcome":"completedSafe","image_complete":true]).write(to:legacy.appendingPathComponent("outcome.json"))
        try store.recoverCompletedCaptures(); let count=try store.all().count
        try store.recoverCompletedCaptures(); try check(try store.all().count==count)
        expect(fm.fileExists(atPath:legacy.appendingPathComponent("document-imported").path))
        print("PASS: completed capture migration is idempotent; one-page PDF import is explicit 360 dpi rasterization.")
        print("PASS: multi-format external exports; managed processed.png, symlink and hard-link collisions; edit/save/print source lifetime; atomic failed/canceled export; unsaved diagnostic protection; Copy/recovery pins; close/relaunch.")
        let sourceImage=fixture(), region=ScanRegion(x:0.13,y:0.21,width:0.61,height:0.55)
        for filter in ScanFilter.allCases { for turns in 0..<4 { for type in [ScanImageType.colour,.grayscale,.blackAndWhite] {
            let a=ScanAdjustments(brightness:0.1,contrast:1.15,invert:true,filter:filter)
            let full=try ScanProcessing.render(source:sourceImage,region:.fullPage,adjustments:a,blackAndWhite:type == .blackAndWhite,threshold:129,rotation:turns,grayscale:type == .grayscale)
            let crop=try ScanProcessing.render(source:sourceImage,region:region,adjustments:a,blackAndWhite:type == .blackAndWhite,threshold:129,rotation:turns,grayscale:type == .grayscale)
            let expected=full.cropping(to:region.pixels(width:full.width,height:full.height)!)!
            expect(pixels(crop)==pixels(expected),"crop-edge contract mismatch")
            let output=root.appendingPathComponent("filter.png"); do { try ScanExport.write(image:crop,dpi:360,destination:output) } catch { print("ENCODING FAILED",filter,turns,type,crop.bitsPerPixel,crop.width,crop.height,error); throw error }
            expect(pixels(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(output as CFURL,nil)!,0,nil)!)==pixels(crop))
        } } }
        let turned=try ScanProcessing.render(source:sourceImage,region:.fullPage,adjustments:.init(),blackAndWhite:false,threshold:128,rotation:1)
        let restored=try ScanProcessing.render(source:turned,region:.fullPage,adjustments:.init(),blackAndWhite:false,threshold:128,rotation:3)
        expect(pixels(restored)==pixels(sourceImage))
        let rotated=try ScanProcessing.render(source:sourceImage,region:.fullPage,adjustments:.init(),blackAndWhite:false,threshold:128,rotation:2)
        expect(pixels(rotated).prefix(4)==Data([255,255,0,255]))
        print("PASS: asymmetric 2D colored corners, lines and gradients; 48 filter/rotation/mode crop-edge pixel comparisons; full-resolution PNG equality; DPI and PDF dimensions.")
        withExtendedLifetime(snapshot) {}; master.removeAll()
    }
}
