import Foundation

extension ScanDocumentStore {
    private struct LegacyCopyIntent: Codable { let schema:Int; let source:URL; let documentID:UUID }
    func migrateLegacyCopy(_ saved:CopyWorkflow) throws -> CopyWorkflow {
        guard let image=saved.image, saved.documentID==nil else { return saved }
        let file=runtime.appendingPathComponent(".state/scanner-app/copy-migration.json")
        let intent:LegacyCopyIntent
        if FileManager.default.fileExists(atPath:file.path) {
            intent=try JSONDecoder().decode(LegacyCopyIntent.self,from:Data(contentsOf:file))
            guard intent.schema==1, intent.source==image else { throw DocumentError.corrupt }
        } else {
            intent=LegacyCopyIntent(schema:1,source:image,documentID:UUID())
            try DiskReceiptStorage().replace(try JSONEncoder().encode(intent),at:file)
        }
        let document:ScanDocument
        if FileManager.default.fileExists(atPath:folder(intent.documentID).path) { document=try load(intent.documentID) }
        else { document=try importImage(image,documentID:intent.documentID) }
        var copy=saved; copy.retain(master(document.id),document:document.id)
        try commitCopy(copy)
        return copy
    }
    /// copy-session.json is authoritative. Write it first, then reconcile the
    /// document bookkeeping. Interruption at either boundary is restartable.
    func commitCopy(_ copy: CopyWorkflow) throws {
        let state=runtime.appendingPathComponent(".state/scanner-app")
        try ownershipCheckpoint("beforeSession")
        try copy.saveSession(to:state.appendingPathComponent("copy-session.json"))
        try ownershipCheckpoint("afterSession")
        try reconcileCopyOwnership(copy)
    }
    func reconcileCopyOwnership(_ copy: CopyWorkflow) throws {
        let state=runtime.appendingPathComponent(".state/scanner-app")
        let file=state.appendingPathComponent("print-job.json")
        let job:PrintJobRecord?
        if FileManager.default.fileExists(atPath:file.path) {
            job=try JSONDecoder().decode(PrintJobRecord.self,from:Data(contentsOf:file))
        } else { job=nil }
        protectedDocuments=Set([job?.outstanding == true ? job?.document : nil, copy.documentID].compactMap {$0})
        // Native inspection is read-only. Unknown/recovery state forbids orphan
        // release; it never suppresses healthy document enumeration/export.
        let safety=SharedDeviceState.inspect(runtime)
        ownershipUncertain = safety == .recoveryRequired || (job?.outstanding == true && job?.document == nil)
        for var document in try all() {
            let previous=document.retainedCopies
            if copy.documentID==document.id { document.retainedCopies.insert(document.id) }
            else if !ownershipUncertain && !protectedDocuments.contains(document.id) && ![.jobUnknown,.printing,.recoveryRequired].contains(copy.stage) {
                document.retainedCopies.remove(document.id)
            }
            if document.retainedCopies != previous { try save(document); try ownershipCheckpoint("afterMarker") }
        }
    }
}
