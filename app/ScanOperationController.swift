import Foundation

@MainActor protocol ScannerServices: AnyObject {
    func quiesce(completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void)
}
@MainActor protocol ScannerProcess: AnyObject {
    func launch(arguments: [String], log: URL, receive: @escaping @MainActor @Sendable (Data) -> Void,
                completion: @escaping @MainActor @Sendable (Int32, Bool) -> Void) throws
    func cancel()
}
struct ScanCapture: Codable, Sendable {
    let acquisition: ScanAcquisition
    let edits: DocumentEdits
    let prescan: Bool
}
struct ScanOperationRequest: Sendable {
    let id: UUID
    let copyAttempt: UUID?
    let kind: String
    let arguments: [String]
    let directory: URL?
    let log: URL
    let capture: ScanCapture?
    init(id: UUID, copyAttempt: UUID?, kind: String, arguments: [String], directory: URL?, log: URL, capture: ScanCapture? = nil) {
        self.id=id; self.copyAttempt=copyAttempt; self.kind=kind; self.arguments=arguments
        self.directory=directory; self.log=log; self.capture=capture
    }
}
struct ScanOperationCompletion: Sendable {
    let request: ScanOperationRequest
    let exitCode: Int32
    let launched: Bool
    let failure: String?
}
/// Main-thread orchestration with injectable preflight and child runner. One
/// shared terminal path consumes the attempt, including preflight/launch failure.
@MainActor final class ScanOperationController {
    private let services: ScannerServices
    private let runner: ScannerProcess
    private let persistIntent: (ScanOperationRequest) throws -> Void
    private(set) var active: ScanOperationRequest?
    private var stopped = false
    var receive: ((UUID, Data) -> Void)?
    var completed: ((ScanOperationCompletion) -> Void)?
    init(services: ScannerServices, runner: ScannerProcess, persistIntent: @escaping (ScanOperationRequest) throws -> Void = CaptureIntent.persist) { self.services = services; self.runner = runner; self.persistIntent=persistIntent }
    @discardableResult func start(_ request: ScanOperationRequest, needsQuiescence: Bool = true) -> Bool {
        precondition(Thread.isMainThread)
        guard active == nil else { return false }
        active = request; stopped = false
        let proceed: @MainActor @Sendable (Result<Void, Error>) -> Void = { [weak self] result in
            guard let self, self.active?.id == request.id else { return }
            if case .failure(let error) = result { self.finish(request, code: 1, launched: false, failure: error.localizedDescription); return }
            guard !self.stopped else { self.finish(request, code: 6, launched: false, failure: "Canceled before acquisition."); return }
            do {
                try self.persistIntent(request)
                try self.runner.launch(arguments: request.arguments, log: request.log, receive: { [weak self] data in
                    guard self?.active?.id == request.id else { return }; self?.receive?(request.id, data)
                }, completion: { [weak self] code, launched in self?.finish(request, code: code, launched: launched, failure: nil) })
            } catch { self.finish(request, code: 1, launched: false, failure: error.localizedDescription) }
        }
        if needsQuiescence { services.quiesce(completion: proceed) } else { proceed(.success(())) }
        return true
    }
    func cancel() { stopped = true; runner.cancel() }
    private func finish(_ request: ScanOperationRequest, code: Int32, launched: Bool, failure: String?) {
        guard active?.id == request.id else { return }
        active = nil
        completed?(.init(request: request, exitCode: code, launched: launched, failure: failure))
    }
}
final class NativeScannerProcess: ScannerProcess {
    let helper: URL, runtime: URL
    var process: Process?
    init(helper: URL, runtime: URL) { self.helper = helper; self.runtime = runtime }
    func launch(arguments: [String], log: URL, receive: @escaping @MainActor @Sendable (Data) -> Void, completion: @escaping @MainActor @Sendable (Int32, Bool) -> Void) throws {
        try HardwareAccess.requireLive()
        let task = Process(), pipe = Pipe()
        guard FileManager.default.createFile(atPath:log.path, contents:nil, attributes:[.posixPermissions:0o600]) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: log)
        task.executableURL = helper; task.arguments = arguments; task.currentDirectoryURL = runtime
        var environment = ProcessInfo.processInfo.environment
        environment["BJC85_STATE_DIRECTORY"] = runtime.path; environment["BJC85_RUNTIME_DIRECTORY"] = runtime.path
        task.environment = environment; task.standardOutput = pipe; task.standardError = pipe
        do { try task.run() } catch { try? handle.close(); throw error }
        process = task
        DispatchQueue.global(qos: .userInitiated).async {
            var loggingFailed = false
            while true {
                let data = pipe.fileHandleForReading.availableData
                if data.isEmpty { break }
                do { try handle.write(contentsOf: data) } catch { loggingFailed = true; task.interrupt() }
                DispatchQueue.main.async { receive(data) }
            }
            task.waitUntilExit(); try? handle.synchronize(); try? handle.close()
            let code = loggingFailed ? Int32(1) : task.terminationStatus
            DispatchQueue.main.async { self.process = nil; completion(code, true) }
        }
    }
    func cancel() { process?.interrupt() }
}
enum HardwareAccess {
    static var fixtureMode: Bool { CommandLine.arguments.contains("--fixture") || CommandLine.arguments.contains("--preview") || ProcessInfo.processInfo.environment["BJC85_OFFLINE_TEST"] == "1" }
    static func requireLive() throws {
        if fixtureMode { throw NSError(domain:"BJC85.Fixture", code:1, userInfo:[NSLocalizedDescriptionKey:"Fixture mode: USB, installed queues, and production services are disabled."]) }
    }
}
final class NativeScannerServices: ScannerServices {
    let runtime: URL
    init(runtime: URL) { self.runtime = runtime }
    func quiesce(completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        let runtime=self.runtime
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try HardwareAccess.requireLive(); try ServiceController.quiesceScanner(runtime: runtime) }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
