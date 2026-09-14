import Foundation
@main struct PrivacyTests {
    static func main() throws {
        let fm=FileManager.default, directory=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer { try? fm.removeItem(at:directory) }
        for name in PrivacyRetention.captureFiles+["outcome.json","recovery-required.json","reference.bin"] {
            try Data("private document".utf8).write(to:directory.appendingPathComponent(name))
        }
        try PrivacyRetention.removeExportedCapture(directory,retainDiagnostics:false,outcome:.recoveryRequired)
        precondition(fm.fileExists(atPath:directory.appendingPathComponent("records.bin").path))
        try PrivacyRetention.removeExportedCapture(directory,retainDiagnostics:true,outcome:.completedSafe)
        precondition(fm.fileExists(atPath:directory.appendingPathComponent("records.bin").path))
        try PrivacyRetention.removeExportedCapture(directory,retainDiagnostics:false,outcome:.completedSafe)
        for name in PrivacyRetention.captureFiles { precondition(!fm.fileExists(atPath:directory.appendingPathComponent(name).path)) }
        for name in ["outcome.json","recovery-required.json","reference.bin"] { precondition(fm.fileExists(atPath:directory.appendingPathComponent(name).path)) }
        let jobs=directory.appendingPathComponent(".state/escl-jobs")
        for outcome in [OperationOutcome.completedSafe,.recoveryRequired] {
            let job=jobs.appendingPathComponent(outcome.rawValue)
            try fm.createDirectory(at:job.appendingPathComponent("capture"),withIntermediateDirectories:true)
            try Data("document pixels".utf8).write(to:job.appendingPathComponent("capture/records.bin"))
            let receipt=job.appendingPathComponent("acquisition-ended.json")
            try JSONSerialization.data(withJSONObject:["outcome":outcome.rawValue]).write(to:receipt)
            try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:0)],ofItemAtPath:receipt.path)
        }
        try Data().write(to:directory.appendingPathComponent("retain-diagnostics"))
        let retained=try PrivacyRetention.removeExpiredESCLDocuments(directory)
        precondition(retained.isEmpty)
        try fm.removeItem(at:directory.appendingPathComponent("retain-diagnostics"))
        let removed=try PrivacyRetention.removeExpiredESCLDocuments(directory)
        precondition(removed==["completedSafe"])
        precondition(fm.fileExists(atPath:jobs.appendingPathComponent("recoveryRequired/capture/records.bin").path))
        print("Export cleanup removes document captures while retaining references and recovery evidence.")
    }
}
