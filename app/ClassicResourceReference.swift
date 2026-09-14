import Foundation
// Evidence descriptors only. No Canon artwork or resource payload is bundled.
struct ClassicResourceReference {
    let feature: String, manualPages: String
    let resourceID: Int? // nil means not yet recovered; never fabricate an ID.
    static let scanPresets = ClassicResourceReference(feature: L("Macintosh scan presets"), manualPages: "70–72", resourceID: nil)
}
