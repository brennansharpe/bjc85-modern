import Foundation
import Darwin

/// Production adapter. Tests inject command/admission/storage into the same
/// ServiceTransitionController and never call launchctl or installed queues.
enum ServiceController {
    struct Result: Sendable { let code: Int32; let output: String }
    static func command(_ path: String, _ arguments: [String], timeout: TimeInterval = 15) throws -> Result {
        let process=Process(), pipe=Pipe()
        process.executableURL=URL(fileURLWithPath:path); process.arguments=arguments
        var environment=ProcessInfo.processInfo.environment; environment["LC_ALL"]="C"; process.environment=environment
        process.standardOutput=pipe; process.standardError=pipe
        try process.run()
        // Bound system checks. The reader drains independently to avoid pipe
        // backpressure. Only this child is stopped on timeout.
        let done=DispatchSemaphore(value:0), reader=DispatchQueue(label:"local.bjc85.command-output")
        final class Output: @unchecked Sendable { var data=Data() }
        let output=Output()
        reader.async { output.data=pipe.fileHandleForReading.readDataToEndOfFile(); done.signal() }
        let deadline=Date().addingTimeInterval(timeout)
        while process.isRunning && Date()<deadline { Thread.sleep(forTimeInterval:0.02) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval:0.1)
            if process.isRunning { kill(process.processIdentifier,SIGKILL) }
            process.waitUntilExit(); _=done.wait(timeout:.now()+1)
            throw NSError(domain:"BJC85.Service",code:2,userInfo:[NSLocalizedDescriptionKey:"The service check timed out. The document is retained; check device status and retry."])
        }
        process.waitUntilExit(); guard done.wait(timeout:.now()+1) == .success else { throw CocoaError(.fileReadUnknown) }
        let data=output.data
        return Result(code:process.terminationStatus,output:String(decoding:data,as:UTF8.self))
    }
    static func require(_ path:String,_ args:[String]) throws {
        let result=try command(path,args)
        guard result.code==0 else { throw NSError(domain:"BJC85.Service",code:Int(result.code),userInfo:[NSLocalizedDescriptionKey:result.output]) }
    }
    private static func transitions() throws -> ServiceTransitionController {
        try HardwareAccess.requireLive()
        return ServiceTransitionController(command: { try command($0,$1) },
            admission: { try DeviceAdmission(exclusive:true) }, availability: { SharedDeviceState.inspectUSB($0) },
            agentsDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents"))
    }
    static func quiesceScanner(runtime:URL) throws { try transitions().quiesceScanner(runtime:runtime) }
    static func prepareScanner(bundle:URL,runtime:URL,reference:URL) throws { try transitions().prepareScanner(bundle:bundle,runtime:runtime,reference:reference) }
    static func preparePrinter(bundle:URL,runtime:URL) throws { try transitions().preparePrinter(bundle:bundle,runtime:runtime) }
}
