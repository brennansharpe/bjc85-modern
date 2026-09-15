import Foundation
import CoreGraphics
import ImageIO

final class ProcessingTicket: @unchecked Sendable {
    let id = UUID()
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}
/// A serial worker bounds full-resolution memory use. Cancellation coalesces
/// obsolete previews; exports get separate tickets and immutable snapshots.
final class ImageProcessingService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.bjc85.image-processing", qos: .userInitiated)
    func perform<T: Sendable>(ticket: ProcessingTicket = ProcessingTicket(), work: @escaping @Sendable () throws -> T,
                    completion: @escaping @MainActor @Sendable (Result<T, Error>) -> Void) {
        queue.async {
            let result: Result<T, Error> = autoreleasepool {
                Result { if ticket.cancelled { throw CancellationError() }; return try work() }
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
    static func render(_ snapshot: DocumentSnapshot, fullPage: Bool = false, ticket: ProcessingTicket) throws -> CGImage {
        precondition(!Thread.isMainThread, "Full-resolution processing must run off the main thread")
        let (original,_)=try RasterImport.decode(snapshot.master)
        let edits = snapshot.document.edits
        return try ScanProcessing.render(source: original, region: fullPage ? .fullPage : edits.region,
            adjustments: edits.adjustments, blackAndWhite: edits.imageType == .blackAndWhite,
            threshold: edits.threshold, rotation: edits.rotation, grayscale: edits.imageType == .grayscale,
            cancelled: { ticket.cancelled })
    }
    func preview(_ snapshot: DocumentSnapshot, ticket: ProcessingTicket, completion: @escaping @MainActor @Sendable (Result<CGImage, Error>) -> Void) {
        perform(ticket: ticket, work: { try Self.render(snapshot, fullPage: true, ticket: ticket) }, completion: completion)
    }
    func export(_ snapshot: DocumentSnapshot, to destination: URL, runtime: URL, ticket: ProcessingTicket,
                completion: @escaping @MainActor @Sendable (Result<DocumentExport, Error>) -> Void) {
        perform(ticket: ticket, work: {
            try FileIdentity.validateExport(destination, runtime: runtime, protected: [snapshot.master])
            let image = try Self.render(snapshot, ticket: ticket)
            // Revalidate immediately before replacement, after lengthy rendering.
            try FileIdentity.validateExport(destination, runtime: runtime, protected: [snapshot.master])
            try ScanExport.write(image: image, dpi: snapshot.document.acquisition.dpi, destination: destination, cancelled: { ticket.cancelled })
            return DocumentExport(destination: destination, revision: snapshot.document.revision, date: Date())
        }, completion: completion)
    }
}
