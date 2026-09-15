import Foundation
import Darwin

final class ServiceTransitionController {
    typealias Result=ServiceController.Result
    let command: (String,[String]) throws -> Result
    let admission: () throws -> AnyObject
    let availability: (URL) -> SharedDeviceState.State
    let agentsDirectory: URL
    let wait: (TimeInterval) -> Void
    init(command: @escaping (String,[String]) throws -> Result,
         admission: @escaping () throws -> AnyObject,
         availability: @escaping (URL) -> SharedDeviceState.State,
         agentsDirectory: URL, wait: @escaping (TimeInterval)->Void = Thread.sleep(forTimeInterval:)) {
        self.command=command; self.admission=admission; self.availability=availability; self.agentsDirectory=agentsDirectory; self.wait=wait
    }
    private func requireAvailable(_ runtime: URL) throws {
        guard availability(runtime) == .available else {
            throw NSError(domain:"BJC85",code:1,userInfo:[NSLocalizedDescriptionKey:L("The device is busy or requires recovery. Service switching is blocked.")])
        }
    }
    /// Only the canonical localhost URI is owned. No DNS/alias normalization,
    /// percent decoding, credentials, alternate ports, queries or fragments.
    static func ownsQueue(_ output: String) -> Bool {
        guard output.utf8.count <= 4096 else { return false }
        return output == "device for BJC85_Native: ipp://localhost:8631/ipp/print" ||
               output == "device for BJC85_Native: ipp://localhost:8631/ipp/print\n"
    }
    private func checkPrintQueue() throws -> Bool {
        let queue=try command("/usr/bin/lpstat",["-v","BJC85_Native"])
        guard queue.code==0 else {
            let message=queue.output.lowercased()
            if queue.code == 1 && ["lpstat: unknown destination \"bjc85_native\".", "lpstat: invalid destination name in list \"bjc85_native\"."].contains(message.trimmingCharacters(in:.whitespacesAndNewlines)) { return false }
            throw NSError(domain:"BJC85.Service",code:1,userInfo:[NSLocalizedDescriptionKey:"The print queue could not be inspected. Service switching is blocked. "+queue.output])
        }
        guard Self.ownsQueue(queue.output) else {
            throw NSError(domain:"BJC85",code:1,userInfo:[NSLocalizedDescriptionKey:L("BJC85_Native belongs to another printer connection. Resolve the queue name before switching services.")])
        }
        let jobs=try command("/usr/bin/lpstat",["-W","not-completed","-o","BJC85_Native"])
        guard jobs.code==0, jobs.output.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
            throw NSError(domain:"BJC85",code:1,userInfo:[NSLocalizedDescriptionKey:L("Finish or cancel the queued BJC-85 print jobs first.")])
        }
        return true
    }
    func require(_ path: String,_ args: [String]) throws {
        let result=try command(path,args)
        guard result.code==0 else { throw NSError(domain:"BJC85",code:Int(result.code),userInfo:[NSLocalizedDescriptionKey:result.output]) }
    }
    func stop(_ label: String) throws {
        let domain="gui/\(getuid())/\(label)"
        try require("/bin/launchctl",["disable",domain])
        if try command("/bin/launchctl",["print",domain]).code==0 { try require("/bin/launchctl",["bootout",domain]) }
    }
    func quiesceScanner(runtime: URL) throws {
        let admission=try admission()
        try withExtendedLifetime(admission) { try requireAvailable(runtime); try quiesceScannerLocked() }
    }
    private func quiesceScannerLocked() throws {
        if try command("/bin/launchctl",["print","gui/\(getuid())/local.bjc85.native-scan"]).code==0 {
            let status=try command("/usr/bin/curl",["--fail","--silent","--max-time","3","http://127.0.0.1:8641/utility/idle"])
            guard status.code==0, status.output.trimmingCharacters(in:.whitespacesAndNewlines) == "idle" else {
                throw NSError(domain:"BJC85",code:1,userInfo:[NSLocalizedDescriptionKey:L("Finish the Image Capture job or inspect its recovery state before switching device use.")])
            }
            try stop("local.bjc85.native-scan")
        }
    }
    private func install(label: String,args: [String],bundle: URL,runtime: URL) throws {
        let fm=FileManager.default
        let agents=agentsDirectory
        let logs=runtime.appendingPathComponent(".state/logs")
        try fm.createDirectory(at:agents,withIntermediateDirectories:true)
        try fm.createDirectory(at:logs,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let attributes:[String:Any] = ["Label":label,"ProgramArguments":args,"WorkingDirectory":runtime.path,
            "EnvironmentVariables":["BJC85_RUNTIME_DIRECTORY":runtime.path,"BJC85_STATE_DIRECTORY":runtime.path,
                                    "STP_DATA_PATH":bundle.appendingPathComponent("Contents/Resources/gutenprint/xml").path],
            "RunAtLoad":true,"KeepAlive":false,"ProcessType":"Background",
            "StandardOutPath":logs.appendingPathComponent(label+".log").path,
            "StandardErrorPath":logs.appendingPathComponent(label+".log").path]
        let plist=agents.appendingPathComponent(label+".plist")
        try PropertyListSerialization.data(fromPropertyList:attributes,format:.xml,options:0).write(to:plist,options:.atomic)
        try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:plist.path)
        try require("/bin/launchctl",["enable","gui/\(getuid())/\(label)"])
        try require("/bin/launchctl",["bootstrap","gui/\(getuid())",plist.path])
    }
    func prepareScanner(bundle: URL,runtime: URL,reference: URL) throws {
        let admission=try admission()
        defer { withExtendedLifetime(admission) {} }
        try requireAvailable(runtime)
        if try checkPrintQueue() {
            try require("/usr/sbin/cupsdisable",["-r",L("IS-12 scanner installed; restore BC-11e before printing."),"BJC85_Native"])
        }
        _=try checkPrintQueue() // Queue pause precedes the final idle check.
        try stop("local.bjc85.native-print")
        try quiesceScannerLocked()
        let helpers=bundle.appendingPathComponent("Contents/Helpers")
        try install(label:"local.bjc85.native-scan",args:[helpers.appendingPathComponent("is12-escl-bridge").path,"--scanner-installed",helpers.appendingPathComponent("bjc85-is12").path,reference.path],bundle:bundle,runtime:runtime)
    }
    func preparePrinter(bundle: URL,runtime: URL) throws {
        let admission=try admission()
        defer { withExtendedLifetime(admission) {} }
        try requireAvailable(runtime)
        _=try checkPrintQueue()
        try quiesceScannerLocked()
        try stop("local.bjc85.native-print")
        let spool=runtime.appendingPathComponent(".state/print-spool")
        try FileManager.default.createDirectory(at:spool,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try install(label:"local.bjc85.native-print",args:[bundle.appendingPathComponent("Contents/Helpers/bjc85-ipp").path,"--print-cartridge=bc11e","--spool-dir",spool.path,"--port","8631"],bundle:bundle,runtime:runtime)
        var ready=false
        for _ in 0..<20 {
            if try command("/usr/bin/curl",["--fail","--silent","--max-time","1","http://127.0.0.1:8631/"]).code==0 { ready=true; break }
            wait(0.25)
        }
        guard ready else { throw NSError(domain:"BJC85",code:1,userInfo:[NSLocalizedDescriptionKey:L("Print service did not become ready. Inspect the service log.")]) }
        _=try checkPrintQueue() // Repeat ownership, inspection errors and idle check at mutation boundary.
        try require("/usr/sbin/lpadmin",["-p","BJC85_Native","-E","-v","ipp://localhost:8631/ipp/print","-m","everywhere","-D",L("Canon BJC-85 Native"),"-o","printer-is-shared=false","-o","printer-error-policy=stop-printer"])
    }
}
