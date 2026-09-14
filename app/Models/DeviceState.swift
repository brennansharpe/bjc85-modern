import Foundation
enum DeviceState: String, Codable {
    case disconnected, printerReady, scannerDetected, scannerWarming
    case scannerNeedsCalibration, scannerReady, printing, scanning
    case awaitingScannerCartridge, awaitingPrintCartridge, cancelling, recoveryRequired, error
    var isBusy: Bool { [.printing, .scanning, .cancelling].contains(self) }
    var label: String {
        switch self {
        case .disconnected: return L("Not connected")
        case .printerReady: return L("Printer ready")
        case .scannerDetected: return L("Scanner detected")
        case .scannerWarming: return L("Scanner warming up")
        case .scannerNeedsCalibration: return L("White reference needed")
        case .scannerReady: return L("Scanner ready")
        case .printing: return L("Printing")
        case .scanning: return L("Scanning")
        case .awaitingScannerCartridge: return L("Install the IS-12")
        case .awaitingPrintCartridge: return L("Install the BC-11e")
        case .cancelling: return L("Stopping device")
        case .recoveryRequired: return L("Recovery required")
        case .error: return L("Device unavailable")
        }
    }
}
