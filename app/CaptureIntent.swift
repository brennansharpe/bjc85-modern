import Foundation

struct CaptureIntent: Codable, Sendable {
    let schema: Int
    let documentID: UUID
    let copyAttempt: UUID?
    let capture: ScanCapture
    static func file(for directory: URL) -> URL { directory.appendingPathExtension("intent.json") }
    static func persist(_ request: ScanOperationRequest) throws {
        guard request.kind == "scan" else { return }
        guard let directory=request.directory, let capture=request.capture else { throw DocumentError.corrupt }
        let intent=CaptureIntent(schema:1,documentID:request.id,copyAttempt:request.copyAttempt,capture:capture)
        try DiskReceiptStorage().replace(try JSONEncoder().encode(intent),at:file(for:directory))
        // The helper exclusively creates directory. Intent lives beside it.
    }
}
