import Foundation
enum PrivacyRetention {
    static let undeliveredESCLLifetime: TimeInterval = 24*60*60
    static let captureFiles = ["usb-in.bin","records.bin","live-preview.rgb","live-preview.json","scan-raw.png","scan-upright.png","processed.png","print.pdf","driver.jsonl"]
    static func removeExportedCapture(_ directory: URL, retainDiagnostics: Bool, outcome: OperationOutcome?, protected: [URL] = []) throws {
        guard !retainDiagnostics, let outcome, outcome.permitsNextOperation else { return }
        for name in captureFiles {
            let file = directory.appendingPathComponent(name)
            if !FileIdentity.isProtected(file, by: protected), FileManager.default.fileExists(atPath:file.path) { try FileManager.default.removeItem(at:file) }
        }
        // Keep the small outcome receipt; never remove a recovery marker here.
    }
    static func removeExpiredESCLDocuments(_ root: URL, now: Date = Date()) throws -> Set<String> {
        let fm=FileManager.default
        guard !fm.fileExists(atPath:root.appendingPathComponent("retain-diagnostics").path) else { return [] }
        let jobs=root.appendingPathComponent(".state/escl-jobs")
        guard fm.fileExists(atPath:jobs.path) else { return [] }
        var removed=Set<String>()
        for job in try fm.contentsOfDirectory(at:jobs,includingPropertiesForKeys:nil) {
            let terminal=job.appendingPathComponent("acquisition-ended.json")
            guard let values=try? fm.attributesOfItem(atPath:terminal.path),
                  let date=values[.modificationDate] as? Date, now.timeIntervalSince(date)>undeliveredESCLLifetime,
                  let data=try? Data(contentsOf:terminal),
                  let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
                  object["outcome"] as? String == OperationOutcome.completedSafe.rawValue else { continue }
            try removeExportedCapture(job.appendingPathComponent("capture"),retainDiagnostics:false,outcome:.completedSafe)
            for name in ["document.jpg","document.png","driver.jsonl"] {
                let file=job.appendingPathComponent(name)
                if fm.fileExists(atPath:file.path) { try fm.removeItem(at:file) }
            }
            removed.insert(job.lastPathComponent)
        }
        return removed
    }
}
