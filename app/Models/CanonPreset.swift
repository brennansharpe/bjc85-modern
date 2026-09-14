import Foundation
struct CanonPreset: Identifiable {
    let id: String, name: String, settings: ScanSettings
    let originalColourMatching: Bool, originalEdgeEmphasis: Bool, manualPage: Int
    // Canon BJC85_IS12_user_manual.pdf, printed pages 70–72 (Macintosh table).
    static let all: [CanonPreset] = [
        .init(id:"dtpColour",name:L("DTP Colour"),settings:.init(imageType:.colour,dpi:180,previewType:.grayscale),originalColourMatching:true,originalEdgeEmphasis:false,manualPage:70),
        .init(id:"photo",name:L("Photo"),settings:.init(imageType:.colour,dpi:360,previewType:.colour),originalColourMatching:true,originalEdgeEmphasis:false,manualPage:70),
        .init(id:"dtpGray",name:L("DTP Grayscale / B&W"),settings:.init(imageType:.grayscale,dpi:180,previewType:.grayscale),originalColourMatching:false,originalEdgeEmphasis:false,manualPage:70),
        .init(id:"text",name:L("Text"),settings:.init(imageType:.blackAndWhite,dpi:180,previewType:.blackAndWhite),originalColourMatching:false,originalEdgeEmphasis:true,manualPage:71),
        .init(id:"fax",name:L("FAX"),settings:.init(imageType:.textEnhancedBW,dpi:200,previewType:.blackAndWhite),originalColourMatching:false,originalEdgeEmphasis:false,manualPage:71),
        .init(id:"ocr",name:L("OCR"),settings:.init(imageType:.textEnhancedBW,dpi:360,previewType:.blackAndWhite),originalColourMatching:false,originalEdgeEmphasis:false,manualPage:71)
    ]
    var qualificationNote: String {
        if let reason = settings.unavailableReason { return reason }
        if originalColourMatching { return L("Original preset: colour matching on. Canon colour matching is unavailable; this scan uses the saved white reference.") }
        if originalEdgeEmphasis { return L("Original preset: edge emphasis on. Canon edge processing is unavailable; native thresholding is used.") }
        return LF("Settings from Canon's Macintosh manual, page %d.",manualPage)
    }
}
