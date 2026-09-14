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
    private var pins: [UUID: Int] = [:]
    static let exportedClosedLifetime: TimeInterval = 7 * 24 * 3600
    static let maximumDocuments = 100
    static let maximumBytes: Int64 = 2 * 1024 * 1024 * 1024
    init(runtime: URL) throws {
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
            try JSONEncoder().encode(document).write(to: folder(document.id).appendingPathComponent("document.json"), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: folder(document.id).appendingPathComponent("document.json").path)
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
            try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .compactMap { UUID(uuidString: $0.lastPathComponent) }.map { try load($0) }
                .sorted { $0.acquisition.acquired > $1.acquisition.acquired }
        }
    }
    func activate(_ id: UUID?) throws {
        try synchronized { try JSONEncoder().encode(id).write(to: activeFile, options: .atomic) }
    }
    func restore() throws -> ScanDocument? {
        try synchronized {
            guard FileManager.default.fileExists(atPath: activeFile.path) else { return nil }
            guard let id = try JSONDecoder().decode(UUID?.self, from: Data(contentsOf: activeFile)) else { return nil }
            return try load(id)
        }
    }
    func importImage(_ source: URL, acquisition: ScanAcquisition? = nil, edits: DocumentEdits = .init()) throws -> ScanDocument {
        try synchronized {
            let documents = try all()
            var size: Int64 = 0
            for document in documents { size += (try FileManager.default.attributesOfItem(atPath: master(document.id).path)[.size] as? NSNumber)?.int64Value ?? 0 }
            guard documents.count < Self.maximumDocuments, size < Self.maximumBytes else { throw DocumentError.quota }
            let image: CGImage, importedDPI: Double
            if source.pathExtension.lowercased() == "pdf" {
                // Explicit import boundary for a one-page PDF (including v1
                // retained copies). This is rasterization, not original scan data.
                guard let pdf=CGPDFDocument(source as CFURL), pdf.numberOfPages==1, let page=pdf.page(at:1) else { throw DocumentError.corrupt }
                let bounds=page.getBoxRect(.mediaBox); importedDPI=360
                guard bounds.width.isFinite,bounds.height.isFinite,bounds.width>0,bounds.height>0,bounds.width<=4000,bounds.height<=4000 else { throw DocumentError.corrupt }
                let w=Int(ceil(bounds.width*5)), h=Int(ceil(bounds.height*5))
                guard w>0,h>0,w<=20000,h<=20000,w*h<=100_000_000,
                      let context=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DocumentError.corrupt }
                context.setFillColor(CGColor(gray:1,alpha:1)); context.fill(CGRect(x:0,y:0,width:w,height:h))
                context.concatenate(page.getDrawingTransform(.mediaBox,rect:CGRect(x:0,y:0,width:w,height:h),rotate:0,preserveAspectRatio:true))
                context.drawPDFPage(page)
                guard let raster=context.makeImage() else { throw DocumentError.corrupt }; image=raster
            } else {
                guard let input=CGImageSourceCreateWithURL(source as CFURL,nil), let decoded=CGImageSourceCreateImageAtIndex(input,0,[kCGImageSourceShouldCacheImmediately:true] as CFDictionary),
                      decoded.width<=20000,decoded.height<=20000,decoded.width*decoded.height<=100_000_000 else { throw DocumentError.corrupt }
                image=decoded; importedDPI=(try? ScanExport.dpi(of:source)) ?? 72
            }
            let metadata = acquisition ?? ScanAcquisition(acquired: Date(), dpi: importedDPI,
                width: image.width, height: image.height, source: source.pathExtension.lowercased()=="pdf" ? "Imported PDF (rasterized)" : "Imported image", mode: "Image", whiteReference: nil)
            guard metadata.width == image.width, metadata.height == image.height else { throw DocumentError.corrupt }
            let document = ScanDocument(id: UUID(), acquisition: metadata, edits: edits)
            try FileManager.default.createDirectory(at: folder(document.id), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            do {
                try ScanProcessing.writePNG(image: image, dpi: metadata.dpi, destination: master(document.id))
                let importedSize=(try FileManager.default.attributesOfItem(atPath:master(document.id).path)[.size] as? NSNumber)?.int64Value ?? 0
                guard size+importedSize <= Self.maximumBytes else { throw DocumentError.quota }
                try save(document); try activate(document.id)
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
        let previous=try restore()?.id
        let captures=runtime.appendingPathComponent(".state/scanner-app")
        guard FileManager.default.fileExists(atPath:captures.path) else { return }
        var recovered: UUID?
        for folder in try FileManager.default.contentsOfDirectory(at:captures,includingPropertiesForKeys:nil).sorted(by:{$0.lastPathComponent<$1.lastPathComponent}) where folder.lastPathComponent.hasPrefix("scan-") {
            let receipt=folder.appendingPathComponent("document-imported")
            guard FileIdentity.contains(captures,folder), !FileManager.default.fileExists(atPath:receipt.path),
                  let data=try? Data(contentsOf:folder.appendingPathComponent("outcome.json")),
                  let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
                  value["outcome"] as? String == "completedSafe", value["image_complete"] as? Bool == true,
                  FileManager.default.isReadableFile(atPath:folder.appendingPathComponent("scan-raw.png").path) else { continue }
            let document=try importImage(folder.appendingPathComponent("scan-raw.png"),edits:DocumentEdits(rotation:2))
            try Data(document.id.uuidString.utf8).write(to:receipt,options:.atomic)
            recovered=document.id
        }
        if let id=previous ?? recovered { try activate(id) }
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
            guard pins[id, default: 0] == 0, try load(id).retainedCopies.isEmpty else { throw DocumentError.busy }
            if try restore()?.id == id { try activate(nil) }
            try FileManager.default.removeItem(at: folder(id))
        }
    }
    func purgeExportedClosed(now: Date = Date()) throws {
        try synchronized {
            let active = try restore()?.id
            for document in try all() where document.id != active && !document.needsExport && document.retainedCopies.isEmpty {
                if let closed = document.closedAt, now.timeIntervalSince(closed) > Self.exportedClosedLifetime, pins[document.id, default: 0] == 0 {
                    try FileManager.default.removeItem(at: folder(document.id))
                }
            }
        }
    }
}
