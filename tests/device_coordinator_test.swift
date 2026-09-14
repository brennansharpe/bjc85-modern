import Foundation
@main struct DeviceTests {
    static func main() {
        let ready=ScannerReadiness(kind:"ready",transport_ok:true,replies_ok:true,head_matches:true,ready:true,temperature_raw:52)
        var device=DeviceCoordinator(); device.observe(ready,hasReference:true)
        precondition(device.state == .scannerReady)
        precondition(!device.requestPrint() && device.state == .awaitingPrintCartridge)
        precondition(!device.confirmPrintCartridge(servicePrepared:false))
        precondition(device.confirmPrintCartridge(servicePrepared:true))
        precondition(device.requestPrint() && !device.requestScan())
        device.cancel(); device.finish(.cancelledSafe,hasReference:true)
        precondition(device.state == .printerReady)
        device.requireRecovery(); device.observe(ready,hasReference:true)
        precondition(!device.requestPrint() && !device.requestScan(calibration:true))
        precondition(device.state == .recoveryRequired)
        var noReference=DeviceCoordinator(); noReference.observe(ready,hasReference:false)
        precondition(!noReference.requestScan() && noReference.requestScan(calibration:true))
        noReference.finish(nil,hasReference:false); precondition(noReference.state == .recoveryRequired)
        print("Cartridge transition, exclusivity, calibration and unknown-outcome gates pass.")
    }
}
