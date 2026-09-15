import Foundation
struct CopyWorkflow: Sendable {
    enum Stage: String, Codable, Sendable { case empty, scanning, awaitingPrintCartridge, readyToPrint, printing, reprintReady, jobUnknown, recoveryRequired }
    private(set) var stage: Stage = .empty
    private(set) var image: URL?
    private(set) var documentID: UUID?
    private(set) var attemptID: UUID?
    private(set) var lastMessage = ""
    mutating func beginScan(id: UUID = UUID()) -> Bool {
        guard stage == .empty else { return false }
        attemptID = id; stage = .scanning; lastMessage = ""; return true
    }
    @discardableResult mutating func retain(_ url: URL, document: UUID? = nil, attempt: UUID? = nil) -> Bool {
        if let attempt { guard attemptID == attempt, stage == .scanning else { return false } }
        image = url; documentID = document; attemptID = nil; stage = .awaitingPrintCartridge; return true
    }
    mutating func printerConfirmed() -> Bool {
        guard image != nil, [.awaitingPrintCartridge, .readyToPrint, .reprintReady].contains(stage) else { return false }
        stage = .readyToPrint; return true
    }
    mutating func needsCartridgeValidation() {
        if image != nil && [.readyToPrint, .reprintReady].contains(stage) { stage = .awaitingPrintCartridge }
    }
    mutating func beginPrint(id: UUID = UUID()) -> URL? {
        guard [.readyToPrint, .reprintReady].contains(stage), let image else { return nil }
        attemptID = id; stage = .printing; return image
    }
    /// Every terminal scan path, including refusal before a helper exists.
    mutating func scanStopped(safely: Bool, attempt: UUID? = nil) {
        guard stage == .scanning, attempt == nil || attempt == attemptID else { return }
        attemptID = nil; stage = safely ? .empty : .recoveryRequired
    }
    mutating func printFinished(_ result: PrintJobResult, safe: Bool, attempt: UUID) {
        guard attemptID == attempt, [.printing, .jobUnknown].contains(stage) else { return }
        lastMessage = result.label
        guard safe else { stage = .recoveryRequired; attemptID = nil; return }
        if result == .unknown || result == .pending { stage = .jobUnknown; return }
        attemptID = nil; stage = result == .completed ? .reprintReady : .readyToPrint
    }
    // Compatibility for existing model clients; production uses identified outcomes.
    mutating func completed(safely: Bool) { attemptID = nil; stage = safely ? .reprintReady : .recoveryRequired }
    mutating func reset() -> Bool {
        guard ![.scanning, .printing, .jobUnknown, .recoveryRequired].contains(stage) else { return false }
        image = nil; documentID = nil; attemptID = nil; stage = .empty; return true
    }
    func canPrint(settings: PrintSettings, device: DeviceState, busy: Bool) -> Bool {
        !busy && settings.isValid && device == .printerReady && [.readyToPrint, .reprintReady].contains(stage) && image != nil
    }
    private struct Session: Codable { let schema: Int; let image: URL; let documentID: UUID?; let stage: Stage; let attemptID: UUID? }
    func saveSession(to file: URL) throws {
        if let image {
            try DiskReceiptStorage().replace(try JSONEncoder().encode(Session(schema: 2, image: image, documentID: documentID, stage: stage, attemptID: attemptID)),at:file)
        } else if FileManager.default.fileExists(atPath: file.path) { try DiskReceiptStorage().restore(nil,at:file) }
    }
    mutating func restoreSession(from file: URL, within root: URL) throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let data = try Data(contentsOf: file)
        if let saved = try? JSONDecoder().decode(Session.self, from: data) {
            guard saved.schema == 2, FileIdentity.contains(root, saved.image), FileManager.default.isReadableFile(atPath:saved.image.path) else { throw CocoaError(.fileReadCorruptFile) }
            image = saved.image; documentID = saved.documentID
            if [.printing, .jobUnknown].contains(saved.stage) { stage = .jobUnknown; attemptID = saved.attemptID }
            else { stage = saved.stage == .recoveryRequired ? .recoveryRequired : .awaitingPrintCartridge; attemptID = nil }
        } else {
            // Explicit migration of v1 URL-only copy sessions. Never resume jobs.
            let restored = try JSONDecoder().decode(URL.self, from: data)
            guard restored.lastPathComponent == "copy.pdf", restored.deletingLastPathComponent().lastPathComponent.hasPrefix("copy-"),
                  FileIdentity.contains(root, restored), FileManager.default.isReadableFile(atPath: restored.path) else { throw CocoaError(.fileReadCorruptFile) }
            image = restored; stage = .awaitingPrintCartridge
        }
    }
}
