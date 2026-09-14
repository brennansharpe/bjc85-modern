import Foundation
@main struct PrintTests {
    static func main() throws {
        let document=URL(fileURLWithPath:"/tmp/a page.pdf")
        let args=try PrintSettings(paper:"A4",colour:false,copies:3).arguments(for:document)
        precondition(args.contains("media=A4") && args.contains("print-color-mode=monochrome"))
        precondition(args.contains("printer-resolution=360dpi") && args.last==document.path)
        precondition(args[args.firstIndex(of:"-n")!+1]=="3")
        precondition(args.contains("print-quality=4"))
        for quality in 3...5 {
            let mapped=try PrintSettings(quality:quality).arguments(for:document)
            precondition(mapped.contains("print-quality=\(quality)"))
        }
        precondition(!PrintSettings(quality:6).isValid)
        precondition(!PrintSettings(paper:"Legal").isValid && !PrintSettings(copies:0).isValid)
        print("Print settings map to supported CUPS/IPP options; unsupported media/copies are rejected.")
    }
}
