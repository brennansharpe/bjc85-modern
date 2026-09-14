import Foundation
enum MaintenanceOperation: String, CaseIterable {
    case calibration, status, testPage, cleaning, deepCleaning, alignment, inkLevels
    var verifiedCommand: Bool { [.calibration, .status].contains(self) }
}
