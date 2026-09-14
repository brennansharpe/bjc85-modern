import Foundation
import ImageCaptureCore

final class Probe: NSObject, ICDeviceBrowserDelegate, ICScannerDeviceDelegate {
    var scanner: ICScannerDevice?
    var ready = false
    var scanStarted = false
    var scanFinished = false
    var selectionRequested = false
    func report(_ record: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: record, options: .sortedKeys) {
            print(String(decoding: data, as: UTF8.self)); fflush(stdout)
        }
    }
    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        let target=CommandLine.arguments.contains("--scan") ? "Canon BJC-85 IS-12 Native" : "BJC-85 IS-12 Native Discovery Test"
        guard let scanner = device as? ICScannerDevice, device.name == target else { return }
        self.scanner = scanner; scanner.delegate = self
        report(["event":"scanner_found", "name":device.name ?? "", "module":device.modulePath])
        scanner.requestOpenSession()
    }
    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {}
    func didRemove(_ device: ICDevice) {}
    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        report(["event":"session_open", "error":error?.localizedDescription ?? "none"])
    }
    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        report(["event":"session_close", "error":error?.localizedDescription ?? "none"])
    }
    func deviceDidBecomeReady(_ device: ICDevice) {
        ready = true
        report(["event":"scanner_ready", "units":scanner?.availableFunctionalUnitTypes ?? []])
        if CommandLine.arguments.contains("--scan"), !selectionRequested, let scanner {
            selectionRequested=true
            scanner.requestSelect(.documentFeeder)
        }
    }
    func scannerDevice(_ scanner: ICScannerDevice, didSelect functionalUnit: ICScannerFunctionalUnit, error: Error?) {
        report(["event":"unit_selected", "error":error?.localizedDescription ?? "none", "state":functionalUnit.state.rawValue,
                "type":functionalUnit.type.rawValue,"size":String(describing:functionalUnit.physicalSize),
                "resolutions":Array(functionalUnit.supportedResolutions)])
        guard ready, error == nil, functionalUnit.type == .documentFeeder,
              functionalUnit.state.rawValue & ICScannerFunctionalUnitState.ready.rawValue != 0,
              CommandLine.arguments.contains("--scan"), !scanStarted else { return }
        scanStarted=true
        DispatchQueue.main.asyncAfter(deadline:.now()+1) {
            let unit=scanner.selectedFunctionalUnit
            unit.measurementUnit = .inches
            let dpi=CommandLine.arguments.contains("--360") ? 360 : CommandLine.arguments.contains("--180") ? 180 : 90
            unit.resolution = dpi
            let lineart=CommandLine.arguments.contains("--lineart")
            unit.pixelDataType = lineart ? .BW : CommandLine.arguments.contains("--gray") ? .gray : .RGB
            unit.bitDepth = ICScannerBitDepth(rawValue:lineart ? 1 : 8)!
            unit.scanArea = CGRect(x:0,y:0,width:8,height:10.8)
            scanner.transferMode = .fileBased
            scanner.downloadsDirectory = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("scans/2026-09-13")
            scanner.documentName = "imagecapture-native-\(lineart ? "lineart-" : CommandLine.arguments.contains("--gray") ? "gray-" : "")\(dpi)dpi"
            scanner.documentUTI = "public.png"
            self.report(["event":"request_scan","dpi":unit.resolution,"area":String(describing:unit.scanArea),
                    "state":unit.state.rawValue,"scan_in_progress":unit.scanInProgress,"bit_depth":unit.bitDepth.rawValue,
                    "paper_loaded":(unit as? ICScannerFunctionalUnitDocumentFeeder)?.documentLoaded ?? false])
            scanner.requestScan()
        }
    }
    func device(_ device: ICDevice, didEncounterError error: Error?) {
        report(["event":"device_error", "error":error?.localizedDescription ?? "none"])
    }
    func scannerDevice(_ scanner: ICScannerDevice, didScanTo url: URL) {
        savedFiles += 1
        report(["event":"scan_saved","path":url.path])
    }
    var savedFiles = 0
    func scannerDevice(_ scanner: ICScannerDevice, didCompleteScanWithError error: Error?) {
        scanFinished=true
        report(["event":"scan_complete","error":error?.localizedDescription ?? "none"])
    }
}
let probe = Probe(), browser = ICDeviceBrowser()
browser.delegate = probe
browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: ICDeviceTypeMask.scanner.rawValue | ICDeviceLocationTypeMask.bonjour.rawValue)!
browser.start()
let deadline=Date(timeIntervalSinceNow:CommandLine.arguments.contains("--scan") ? 600 : 25)
while Date() < deadline && !probe.scanFinished { RunLoop.main.run(until:Date(timeIntervalSinceNow:0.2)) }
probe.scanner?.requestCloseSession()
RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
browser.stop()
probe.report(["event":"probe_result", "discovered":probe.scanner != nil, "ready":probe.ready,"scan_finished":probe.scanFinished,"saved_files":probe.savedFiles])
if CommandLine.arguments.contains("--scan") && probe.savedFiles == 0 { exit(1) }
