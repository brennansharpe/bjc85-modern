import Foundation
// All app transitions run on the main thread. The C transport separately enforces
// a cross-process USB lease and durable recovery marker for every native client.
struct DeviceCoordinator {
    private(set) var state: DeviceState = .disconnected
    private(set) var referenceAvailable = false
    private var printingOperation = false
    private var previousState: DeviceState?
    private var swapPreviousState: DeviceState?
    mutating func observe(_ readiness: ScannerReadiness, hasReference: Bool) {
        guard state != .recoveryRequired else { return }
        referenceAvailable = hasReference
        guard !state.isBusy else { return }
        if readiness.canScan { state = hasReference ? .scannerReady : .scannerNeedsCalibration }
        else if readiness.kind == "warming" { state = .scannerWarming }
        else if readiness.kind == "wrongHead" { state = .awaitingScannerCartridge }
        else { state = .error }
    }
    mutating func requestScan(calibration: Bool = false) -> Bool {
        guard state != .recoveryRequired, !state.isBusy else { return false }
        guard state == .scannerReady || (calibration && state == .scannerNeedsCalibration) else {
            if state == .printerReady || state == .disconnected { state = .awaitingScannerCartridge }
            return false
        }
        previousState=state; printingOperation=false; state = .scanning; return true
    }
    mutating func requestPrint() -> Bool {
        guard state != .recoveryRequired, !state.isBusy else { return false }
        guard state == .printerReady else { if state != .awaitingPrintCartridge { swapPreviousState=state }; state = .awaitingPrintCartridge; return false }
        previousState=state; printingOperation=true; state = .printing; return true
    }
    mutating func confirmPrintCartridge(servicePrepared: Bool) -> Bool {
        guard state == .awaitingPrintCartridge, servicePrepared else { return false }
        state = .printerReady; return true
    }
    mutating func cancelPrintCartridge(unchanged: Bool) {
        guard state == .awaitingPrintCartridge else { return }
        state = unchanged ? (swapPreviousState ?? .scannerDetected) : .scannerDetected
        swapPreviousState=nil
    }
    mutating func preflightRefused() {
        guard state != .recoveryRequired else { return }
        if let previousState { state=previousState }; previousState=nil; printingOperation=false
    }
    mutating func cancel() { if state.isBusy { state = .cancelling } }
    mutating func finish(_ outcome: OperationOutcome?, hasReference: Bool) {
        guard let outcome, outcome.permitsNextOperation else { state = .recoveryRequired; return }
        if state == .recoveryRequired { return }
        referenceAvailable = hasReference
        previousState=nil
        state = printingOperation ? .printerReady : .scannerDetected
        printingOperation=false
        // Scanner readiness is checked again, never inferred from process exit.
    }
    mutating func requireRecovery() { state = .recoveryRequired }
    mutating func disconnected() { if state != .recoveryRequired { state = .disconnected } }
}
