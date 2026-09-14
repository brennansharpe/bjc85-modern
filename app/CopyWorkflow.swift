import Foundation
struct CopyWorkflow {
    enum Stage: String { case empty, scanning, awaitingPrintCartridge, readyToPrint, printing, reprintReady, recoveryRequired }
    private(set) var stage: Stage = .empty
    private(set) var image: URL?
    mutating func beginScan() -> Bool {
        guard stage == .empty else { return false }; stage = .scanning; return true
    }
    mutating func retain(_ url: URL) { image = url; stage = .awaitingPrintCartridge }
    mutating func printerConfirmed() -> Bool {
        guard image != nil && stage == .awaitingPrintCartridge else { return false }
        stage = .readyToPrint; return true
    }
    mutating func beginPrint() -> URL? {
        guard [.readyToPrint, .reprintReady].contains(stage), let image else { return nil }
        stage = .printing; return image
    }
    mutating func completed(safely: Bool) { stage = safely ? .reprintReady : .recoveryRequired }
    mutating func scanStopped(safely: Bool) { if stage == .scanning { stage = safely ? .empty : .recoveryRequired } }
    mutating func reset() -> Bool {
        guard ![.scanning, .printing, .recoveryRequired].contains(stage) else { return false }
        image = nil; stage = .empty; return true
    }
    func saveSession(to file: URL) throws {
        if let image {
            try JSONEncoder().encode(image).write(to:file,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
        } else if FileManager.default.fileExists(atPath:file.path) { try FileManager.default.removeItem(at:file) }
    }
    mutating func restoreSession(from file: URL, within root: URL) throws {
        guard FileManager.default.fileExists(atPath:file.path) else { return }
        let restored=try JSONDecoder().decode(URL.self,from:Data(contentsOf:file)).standardizedFileURL
        let parent=restored.deletingLastPathComponent()
        guard restored.lastPathComponent=="copy.pdf", parent.lastPathComponent.hasPrefix("copy-"),
              parent.deletingLastPathComponent().path==root.standardizedFileURL.path,
              FileManager.default.fileExists(atPath:restored.path) else { throw CocoaError(.fileReadCorruptFile) }
        // Restart never resumes acquisition or printing. The user must confirm
        // the print-cartridge transition again; queue/recovery checks still apply.
        image=restored; stage = .awaitingPrintCartridge
    }
}
