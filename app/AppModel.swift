import Foundation
struct AppModel {
    var coordinator = DeviceCoordinator()
    var scan = ScanSettings()
    var adjustments = ScanAdjustments()
    var region = ScanRegion.fullPage
    var print = PrintSettings()
    var copy = CopyWorkflow()
    var presetID = "photo"
    var retainDiagnosticCaptures = false
    mutating func choose(_ preset: CanonPreset) { presetID = preset.id; scan = preset.settings }
}
