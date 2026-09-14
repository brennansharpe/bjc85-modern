import Foundation
import CoreGraphics
enum ScanImageType: String, CaseIterable, Codable {
    case colour, grayscale, blackAndWhite, textEnhancedBW
    var label: String {
        switch self {
        case .colour: return L("Colour")
        case .grayscale: return L("Grayscale")
        case .blackAndWhite: return L("Black and white")
        case .textEnhancedBW: return L("B&W Text Enhanced — unavailable")
        }
    }
    var helperMode: String { self == .colour ? "color" : "gray" }
}
struct ScanSettings: Codable, Equatable {
    var imageType: ScanImageType = .colour
    var dpi = 360
    var threshold = 128
    var previewType: ScanImageType = .colour
    static let resolutions = [90, 180, 200, 300, 360]
    var unavailableReason: String? {
        if ![90, 180, 360].contains(dpi) { return LF("%d dpi is documented by Canon but its device mode has not been qualified.",dpi) }
        if imageType == .textEnhancedBW { return L("Canon's Text Enhanced processing is still under research. Select Black and white for adjustable native thresholding.") }
        return nil
    }
}
struct ScanRegion: Codable, Equatable {
    var x = 0.0, y = 0.0, width = 1.0, height = 1.0
    static let fullPage = ScanRegion()
    var isValid: Bool {
        [x,y,width,height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0 && height > 0 && x+width <= 1.000001 && y+height <= 1.000001
    }
    func pixels(width sourceWidth: Int, height sourceHeight: Int) -> CGRect? {
        guard isValid, sourceWidth > 0, sourceHeight > 0 else { return nil }
        let left = (x * Double(sourceWidth)).rounded(), top = (y * Double(sourceHeight)).rounded()
        let right = min(Double(sourceWidth), ((x+width) * Double(sourceWidth)).rounded())
        let bottom = min(Double(sourceHeight), ((y+height) * Double(sourceHeight)).rounded())
        guard right > left, bottom > top else { return nil }
        return CGRect(x: left, y: top, width: right-left, height: bottom-top)
    }
    var rotated180: ScanRegion { ScanRegion(x: max(0,1-x-width), y: max(0,1-y-height), width: width, height: height) }
    mutating func nudge(dx: Double, dy: Double) {
        x = min(max(0,x+dx),max(0,1-width)); y = min(max(0,y+dy),max(0,1-height))
    }
}
enum ScanFilter: String, CaseIterable, Codable { case none, sharpen, soften, despeckle }
struct ScanAdjustments: Codable, Equatable {
    var brightness = 0.0, contrast = 1.0
    var invert = false
    var filter: ScanFilter = .none
}
