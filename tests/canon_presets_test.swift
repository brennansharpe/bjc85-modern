import Foundation
@main struct PresetTests {
    static func main() {
        let presets=Dictionary(uniqueKeysWithValues:CanonPreset.all.map { ($0.id,$0) })
        precondition(presets["fax"]!.settings.dpi==200 && presets["fax"]!.settings.imageType == .textEnhancedBW)
        precondition(presets["ocr"]!.settings.dpi==360 && presets["ocr"]!.settings.imageType == .textEnhancedBW)
        precondition(presets["photo"]!.settings.dpi==360 && presets["photo"]!.settings.imageType == .colour)
        precondition(presets["dtpColour"]!.settings.previewType == .grayscale)
        precondition(presets["text"]!.originalEdgeEmphasis)
        precondition(presets["fax"]!.settings.unavailableReason != nil && presets["ocr"]!.settings.unavailableReason != nil)
        precondition(ScanSettings(imageType:.colour,dpi:300).unavailableReason != nil)
        precondition(presets["photo"]!.qualificationNote.contains("unavailable"))
        print("Canon Macintosh preset table (manual pages 70–72) and unavailable-mode gates pass.")
    }
}
