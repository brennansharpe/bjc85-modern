import Foundation

enum PrintJobResult: String, Codable, Sendable { case pending, completed, cancelled, aborted, rejected, unknown
    var label: String {
        switch self {
        case .pending: return "Queued or processing"
        case .completed: return "Queue reports completed. Inspect the printed page."
        case .cancelled: return "Queue reports canceled"
        case .aborted: return "Queue reports aborted"
        case .rejected: return "Print request rejected"
        case .unknown: return "Print outcome unknown. Check the queue; do not resubmit."
        }
    }
}
struct PrintJobRecord: Codable, Equatable, Sendable {
    let attempt: UUID
    let document: UUID?
    var revision: Int? = nil
    let isCopy: Bool
    let destination: String
    let created: Date
    var jobID: Int?
    var result: PrintJobResult
    var reasons: [String]
    var outstanding: Bool { [.pending, .unknown].contains(result) }
}
struct QueueJobStatus: Sendable { let result: PrintJobResult; let reasons: [String] }
enum PrintSubmissionFailure: Error { case refusedBeforeAcceptance(String) }
protocol PrintQueueAccess {
    func submit(_ image: URL, settings: PrintSettings) throws -> Int
    func query(destination: String, id: Int) throws -> QueueJobStatus
    func cancel(destination: String, id: Int) throws
}
/// Worker-confined tracker. Persist BEFORE submission, then persist the exact job
/// reference. Crash between acceptance and receipt leaves unknown, never a replay.
final class PrintJobTracker: @unchecked Sendable {
    let file: URL
    private let queue: PrintQueueAccess
    private let now: () -> Date
    private(set) var record: PrintJobRecord?
    init(file: URL, queue: PrintQueueAccess, now: @escaping () -> Date = Date.init) throws {
        self.file=file; self.queue=queue; self.now=now
        if FileManager.default.fileExists(atPath:file.path) { record=try JSONDecoder().decode(PrintJobRecord.self,from:Data(contentsOf:file)) }
    }
    private func persist() throws {
        try JSONEncoder().encode(record).write(to:file,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    }
    @discardableResult func submit(_ image: URL, settings: PrintSettings, document: UUID?, copy: Bool, attempt: UUID, revision: Int? = nil) throws -> PrintJobRecord {
        guard settings.isValid, record?.outstanding != true else { throw CocoaError(.validationMissingMandatoryProperty) }
        record = PrintJobRecord(attempt:attempt,document:document,revision:revision,isCopy:copy,destination:"BJC85_Native",created:now(),jobID:nil,result:.unknown,reasons:["Submission has not been reconciled"])
        try persist()
        do {
            let id=try queue.submit(image,settings:settings)
            record?.jobID=id; record?.result = .pending; record?.reasons=[]
        } catch PrintSubmissionFailure.refusedBeforeAcceptance(let reason) {
            record?.result = .rejected; record?.reasons=[reason]
        } catch {
            // A timeout/failed lp response may still have been accepted. Do not
            // treat process failure as rejection or automatically submit again.
            record?.result = .unknown; record?.reasons=[error.localizedDescription]
        }
        do { try persist() } catch { record?.result = .unknown; record?.reasons.append("The job receipt could not be saved. Do not resubmit.") }
        return record!
    }
    @discardableResult func reconcile() throws -> PrintJobRecord? {
        guard var value=record, value.outstanding, let id=value.jobID else { return record }
        do { let status=try queue.query(destination:value.destination,id:id); value.result=status.result; value.reasons=status.reasons }
        catch { value.result = .unknown; value.reasons=[error.localizedDescription] }
        guard record?.attempt == value.attempt else { return record }
        record=value; try persist(); return value
    }
    func cancel() throws {
        guard let record, record.outstanding, let id=record.jobID else { return }
        try queue.cancel(destination:record.destination,id:id)
        // Cancel's return code is not the job's terminal state.
    }
}
struct NativePrintQueue: PrintQueueAccess {
    let queryHelper: URL
    func submit(_ image: URL, settings: PrintSettings) throws -> Int {
        try HardwareAccess.requireLive()
        guard settings.isValid, FileManager.default.isReadableFile(atPath:image.path) else { throw PrintSubmissionFailure.refusedBeforeAcceptance("Check print settings and the retained document before retrying.") }
        let result=try ServiceController.command("/usr/bin/lp",settings.arguments(for:image))
        guard result.code==0, let word=result.output.split(whereSeparator: { $0.isWhitespace }).first(where: { $0.hasPrefix("BJC85_Native-") }),
              let id=Int(word.dropFirst("BJC85_Native-".count)), id>0 else { throw NSError(domain:"BJC85.Print",code:1,userInfo:[NSLocalizedDescriptionKey:result.output]) }
        return id
    }
    func query(destination: String, id: Int) throws -> QueueJobStatus {
        try HardwareAccess.requireLive()
        let result=try ServiceController.command(queryHelper.path,[destination,String(id)])
        struct Response: Decodable { let state: Int; let destination: String; let id: Int; let reasons: [String] }
        guard result.code==0, let data=result.output.data(using:.utf8), let reply=try? JSONDecoder().decode(Response.self,from:data),
              reply.id==id, reply.destination==destination else { return QueueJobStatus(result:.unknown,reasons:["Job history unavailable or query failed"] ) }
        let state: PrintJobResult
        switch reply.state { case 3...6: state = .pending; case 7: state = .cancelled; case 8: state = .aborted; case 9: state = .completed; default: state = .unknown }
        return QueueJobStatus(result:state,reasons:reply.reasons)
    }
    func cancel(destination: String, id: Int) throws {
        try HardwareAccess.requireLive()
        try ServiceController.require("/usr/bin/cancel",["\(destination)-\(id)"])
    }
}
