import Foundation
import ImageIO
import CoreGraphics
import Darwin

/// Acquisition facts never change when the document is edited or exported.
struct ScanAcquisition: Codable, Equatable, Sendable {
    let acquired: Date
    let dpi: Double
    let width: Int
    let height: Int
    let source: String
    let mode: String
    let whiteReference: String?
}
struct DocumentEdits: Codable, Equatable, Sendable {
    var rotation = 0 // clockwise quarter turns, from the immutable master
    var region = ScanRegion.fullPage
    var adjustments = ScanAdjustments()
    var imageType = ScanImageType.colour
    var threshold = 128
}
struct DocumentExport: Codable, Equatable, Sendable {
    let destination: URL
    let revision: Int
    let date: Date
}
struct ScanDocument: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let acquisition: ScanAcquisition
    var edits = DocumentEdits()
    var revision = 0
    var exports: [DocumentExport] = []
    var retainedCopies: Set<UUID> = []
    var closedAt: Date?
    var needsExport: Bool { !exports.contains { $0.revision == revision } }
}
struct DocumentSnapshot: @unchecked Sendable {
    let document: ScanDocument
    let master: URL
    // A strong pin spans queued and executing work, including canceled workers.
    let pin: DocumentPin
}
final class DocumentPin: @unchecked Sendable {
    private let release: () -> Void
    init(_ release: @escaping () -> Void) { self.release = release }
    deinit { release() }
}
enum DocumentError: LocalizedError {
    case unsafeDestination, busy, quota, corrupt, missing
    var errorDescription: String? {
        switch self {
        case .unsafeDestination: return L("Choose an export folder outside the utility’s private storage. This location belongs to a document, diagnostic capture, or recovery record.")
        case .busy: return L("Wait for document processing to finish before discarding this document.")
        case .quota: return L("Document storage is full. Export and discard older documents before opening or scanning another page.")
        case .corrupt: return L("The saved document could not be restored. Its files have been preserved for inspection.")
        case .missing: return L("The document is no longer available.")
        }
    }
}
/// Serialized disk owner. It never starts jobs on restoration and never owns USB.
/// Call from a worker queue: decoding/import/export is intentionally synchronous here.
final class ScanDocumentStore: @unchecked Sendable {
    let runtime: URL
    let directory: URL
    private let lock = NSRecursiveLock()
    var metadataCheckpoint: () throws -> Void = {}
    var ownershipCheckpoint: (String) throws -> Void = { _ in }
    var recoveryCheckpoint: (String) throws -> Void = { _ in }
    var protectedDocuments: Set<UUID> = []
    var ownershipUncertain = false
    private var pins: [UUID: Int] = [:]
    static let maximumDocuments = 100
    static let maximumBytes: Int64 = 2 * 1024 * 1024 * 1024
    let documentLimit: Int
    let byteLimit: Int64
    private(set) var damagedEntries: [UUID] = []
    private(set) var recoveryWarnings: [String] = []
    var decodeRaster: (URL) throws -> (CGImage,Double) = { try RasterImport.decode($0) }
    init(runtime: URL, documentLimit: Int = maximumDocuments, byteLimit: Int64 = maximumBytes) throws {
        self.documentLimit=documentLimit; self.byteLimit=byteLimit
        self.runtime = runtime
        directory = runtime.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    private func synchronized<T>(_ body: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try body() }
    func folder(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString, isDirectory: true) }
    func master(_ id: UUID) -> URL { folder(id).appendingPathComponent("master.png") }
    private var activeFile: URL { directory.appendingPathComponent("active.json") }
    func save(_ document: ScanDocument) throws {
        try synchronized {
            try metadataCheckpoint()
            try DiskReceiptStorage().replace(try JSONEncoder().encode(document),at:folder(document.id).appendingPathComponent("document.json"))
        }
    }
    func load(_ id: UUID) throws -> ScanDocument {
        try synchronized {
            let document = try JSONDecoder().decode(ScanDocument.self, from: Data(contentsOf: folder(id).appendingPathComponent("document.json")))
            guard document.id == id, document.acquisition.dpi > 0, document.acquisition.dpi.isFinite,
                  document.edits.region.isValid, FileIdentity.contains(directory, master(id)),
                  CGImageSourceCreateWithURL(master(id) as CFURL, nil) != nil else { throw DocumentError.corrupt }
            return document
        }
    }
    func all() throws -> [ScanDocument] {
        try synchronized {
            let ids=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
                .compactMap { UUID(uuidString:$0.lastPathComponent) }
            var healthy:[ScanDocument]=[]; damagedEntries=[]
            for id in ids {
                do { healthy.append(try load(id)) }
                catch { damagedEntries.append(id) }
            }
            return healthy.sorted { $0.acquisition.acquired > $1.acquisition.acquired }
        }
    }
    func activate(_ id: UUID?) throws {
        try synchronized { try DiskReceiptStorage().replace(try JSONEncoder().encode(id),at:activeFile) }
    }
    func restore() throws -> ScanDocument? {
        try synchronized {
            guard FileManager.default.fileExists(atPath: activeFile.path) else { return nil }
            guard let id = try JSONDecoder().decode(UUID?.self, from: Data(contentsOf: activeFile)) else { return nil }
            return try load(id)
        }
    }
    func importImage(_ source: URL, acquisition: ScanAcquisition? = nil, edits: DocumentEdits = .init(), documentID: UUID? = nil) throws -> ScanDocument {
        try synchronized {
            // Count every UUID entry and every existing byte, including partial
            // and corrupt entries. Unreadable accounting fails the import only.
            let entries=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
                .filter { UUID(uuidString:$0.lastPathComponent) != nil }
            var size:Int64=0
            func count(_ url:URL) throws {
                let attrs=try FileManager.default.attributesOfItem(atPath:url.path)
                guard attrs[.type] as? FileAttributeType != .typeSymbolicLink else { throw DocumentError.corrupt }
                if attrs[.type] as? FileAttributeType == .typeDirectory {
                    for child in try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil) { try count(child) }
                } else {
                    guard let bytes=(attrs[.size] as? NSNumber)?.int64Value, bytes>=0 else { throw DocumentError.corrupt }
                    let (sum,overflow)=size.addingReportingOverflow(bytes)
                    guard !overflow else { throw DocumentError.quota }; size=sum
                }
            }
            for entry in entries { try count(entry) }
            guard entries.count < documentLimit, size < byteLimit else { throw DocumentError.quota }
            let image: CGImage, importedDPI: Double
            if source.pathExtension.lowercased() == "pdf" {
                // Explicit import boundary for a one-page PDF (including v1
                // retained copies). This is rasterization, not original scan data.
                guard let pdf=CGPDFDocument(source as CFURL), pdf.numberOfPages==1, let page=pdf.page(at:1) else { throw DocumentError.corrupt }
                let bounds=page.getBoxRect(.mediaBox); importedDPI=360
                guard bounds.width.isFinite,bounds.height.isFinite,bounds.width>0,bounds.height>0,bounds.width<=4000,bounds.height<=4000 else { throw DocumentError.corrupt }
                let w=Int(ceil(bounds.width*5)), h=Int(ceil(bounds.height*5))
                try RasterImport.validate(width:Double(w),height:Double(h),depth:8)
                guard w>0,h>0,w<=20000,h<=20000,w*h<=100_000_000,
                      let context=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DocumentError.corrupt }
                context.setFillColor(CGColor(gray:1,alpha:1)); context.fill(CGRect(x:0,y:0,width:w,height:h))
                context.concatenate(page.getDrawingTransform(.mediaBox,rect:CGRect(x:0,y:0,width:w,height:h),rotate:0,preserveAspectRatio:true))
                context.drawPDFPage(page)
                guard let raster=context.makeImage() else { throw DocumentError.corrupt }; image=raster
            } else {
                (image,importedDPI)=try decodeRaster(source)
            }
            let metadata = acquisition ?? ScanAcquisition(acquired: Date(), dpi: importedDPI,
                width: image.width, height: image.height, source: source.pathExtension.lowercased()=="pdf" ? "Imported PDF (rasterized)" : "Imported image", mode: "Image", whiteReference: nil)
            guard metadata.width == image.width, metadata.height == image.height else { throw DocumentError.corrupt }
            let document = ScanDocument(id: documentID ?? UUID(), acquisition: metadata, edits: edits)
            try FileManager.default.createDirectory(at: folder(document.id), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            do {
                try ScanProcessing.writePNG(image: image, dpi: metadata.dpi, destination: master(document.id))
                let masterHandle=try FileHandle(forWritingTo:master(document.id)); try masterHandle.synchronize(); try masterHandle.close()
                let importedSize=(try FileManager.default.attributesOfItem(atPath:master(document.id).path)[.size] as? NSNumber)?.int64Value ?? 0
                let metadataSize=Int64(try JSONEncoder().encode(document).count)
                guard importedSize <= byteLimit-size, metadataSize <= byteLimit-size-importedSize else { throw DocumentError.quota }
                try save(document); if documentID == nil { try activate(document.id) }
            } catch {
                // An incomplete import has no user edits; the original is untouched.
                try? FileManager.default.removeItem(at: folder(document.id)); throw error
            }
            return document
        }
    }
    /// Recover completed captures left by the old app or by a crash before import.
    /// Incomplete/uncertain journals are deliberately untouched; no jobs resume.
    func recoverCompletedCaptures() throws {
        recoveryWarnings=[]
        let captures=runtime.appendingPathComponent(".state/scanner-app")
        guard FileManager.default.fileExists(atPath:captures.path) else { return }
        for folder in try FileManager.default.contentsOfDirectory(at:captures,includingPropertiesForKeys:nil).sorted(by:{$0.lastPathComponent<$1.lastPathComponent}) where folder.lastPathComponent.hasPrefix("scan-") && !folder.lastPathComponent.hasSuffix(".intent.json") {
            do {
                guard try folder.resourceValues(forKeys:[.isDirectoryKey]).isDirectory == true else { continue }
                _=try importCompletedCapture(folder)
            }
            catch { recoveryWarnings.append("A completed capture is pending: " + error.localizedDescription) }
        }
    }
    @discardableResult func importCompletedCapture(_ captureFolder: URL) throws -> ScanDocument? {
        try synchronized {
            let captures=runtime.appendingPathComponent(".state/scanner-app")
            guard FileIdentity.contains(captures,captureFolder) else { throw DocumentError.corrupt }
            let receipt=captureFolder.appendingPathComponent("document-imported")
            if FileManager.default.fileExists(atPath:receipt.path) { return nil }
            let outcome=captureFolder.appendingPathComponent("outcome.json")
            guard FileManager.default.fileExists(atPath:outcome.path) else { return nil }
            let value=try JSONSerialization.jsonObject(with:Data(contentsOf:outcome)) as? [String:Any]
            guard value?["schema_version"] as? Int == 1 else { throw DocumentError.corrupt }
            guard value?["outcome"] as? String == "completedSafe", value?["image_complete"] as? Bool == true,
                  DriverOutcome.journalPermitsRestart(captureFolder) else { return nil }
            let intentFile=CaptureIntent.file(for:captureFolder)
            let intent: CaptureIntent
            if FileManager.default.fileExists(atPath:intentFile.path) {
                intent=try JSONDecoder().decode(CaptureIntent.self,from:Data(contentsOf:intentFile))
                guard intent.schema==1, intent.capture.edits.region.isValid else { throw DocumentError.corrupt }
            } else {
                // Recognized v1 native capture; persist a migration identity before
                // import. Unknown acquisition facts remain explicitly unknown.
                let (image,dpi)=try decodeRaster(captureFolder.appendingPathComponent("scan-raw.png"))
                intent=CaptureIntent(schema:1,documentID:UUID(),copyAttempt:nil,capture:ScanCapture(acquisition:ScanAcquisition(acquired:Date(),dpi:dpi,width:image.width,height:image.height,source:"Recovered legacy capture (orientation unknown)",mode:"Unknown",whiteReference:nil),edits:.init(),prescan:false))
                try DiskReceiptStorage().replace(try JSONEncoder().encode(intent),at:intentFile)
            }
            let document:ScanDocument
            if FileManager.default.fileExists(atPath:folder(intent.documentID).path) {
                document=try load(intent.documentID)
                guard document.acquisition==intent.capture.acquisition else { throw DocumentError.corrupt }
            } else {
                document=try importImage(captureFolder.appendingPathComponent("scan-raw.png"),acquisition:intent.capture.acquisition,edits:intent.capture.edits,documentID:intent.documentID)
            }
            // Copy intent remains durable even if the separate ownership commit
            // fails. A subsequent recovery retries reconciliation with this ID.
            if intent.copyAttempt != nil {
                var copy=CopyWorkflow()
                let copyFile=captures.appendingPathComponent("copy-session.json")
                try copy.restoreSession(from:copyFile,within:runtime)
                guard copy.documentID==document.id || copy.stage == .empty else { throw DocumentError.busy }
                if copy.stage == .empty { copy.retain(master(document.id),document:document.id) }
                try commitCopy(copy)
            }
            try recoveryCheckpoint("beforeReceipt")
            try DiskReceiptStorage().replace(Data(document.id.uuidString.utf8),at:receipt)
            return try load(document.id)
        }
    }
    func snapshot(_ document: ScanDocument) throws -> DocumentSnapshot {
        try synchronized {
            guard FileManager.default.isReadableFile(atPath: master(document.id).path) else { throw DocumentError.missing }
            pins[document.id, default: 0] += 1
            let pin = DocumentPin { [self] in synchronized { pins[document.id, default: 1] -= 1 } }
            return DocumentSnapshot(document: document, master: master(document.id), pin: pin)
        }
    }
    func close(_ document: ScanDocument, now: Date = Date()) throws {
        var closed = document; closed.closedAt = now; try save(closed); try activate(nil)
    }
    func discard(_ id: UUID) throws {
        try synchronized {
            // Re-read physical ownership at disposal, including ordinary print
            // jobs submitted after startup reconciliation. Never rely on a stale
            // in-memory ownership snapshot to release an unknown job's master.
            let jobFile=runtime.appendingPathComponent(".state/scanner-app/print-job.json")
            if FileManager.default.fileExists(atPath:jobFile.path) {
                let job=try JSONDecoder().decode(PrintJobRecord.self,from:Data(contentsOf:jobFile))
                if job.outstanding && (job.document==nil || job.document==id) { throw DocumentError.busy }
            }
            for name in ["recovery-required.json", ".state/print-spool/usb-recovery-required.txt"] {
                var info=stat()
                if lstat(runtime.appendingPathComponent(name).path,&info)==0 || errno != ENOENT { throw DocumentError.busy }
            }
            guard !ownershipUncertain, !protectedDocuments.contains(id), pins[id, default: 0] == 0, try load(id).retainedCopies.isEmpty else { throw DocumentError.busy }
            var active:UUID?
            do { active=try restore()?.id }
            catch { /* Preserve corrupt pointer; it cannot make healthy files inaccessible. */ }
            if active==id { try activate(nil) }
            try FileManager.default.removeItem(at: folder(id))
        }
    }
    func purgeExportedClosed(now: Date = Date()) throws {
        // Export receipts are history, never consent to delete a master.
        // Retained masters require explicit confirmed disposal, regardless of age.
    }
}
