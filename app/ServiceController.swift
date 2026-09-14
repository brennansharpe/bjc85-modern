import Foundation
import Darwin

enum ServiceController {
    private static func requireAvailable(_ runtime: URL) throws {
        guard SharedDeviceState.inspect(runtime) == .available else {
            throw NSError(domain:"BJC85",code:1,userInfo:[NSLocalizedDescriptionKey:L("The device is busy or requires recovery. Service switching is blocked.")])
        }
    }
    private static func checkPrintQueue() throws -> Bool {
        let queue=try command("/usr/bin/lpstat",["-v","BJC85_Native"])
        guard queue.code==0 else { return false }
        guard queue.output.contains("ipp://localhost:8631/ipp/print") else {
            throw NSError(domain:"BJC85",code:1,userInfo:[NSLocalizedDescriptionKey:L("BJC85_Native belongs to another printer connection. Resolve the queue name before switching services.")])
        }
        let jobs=try command("/usr/bin/lpstat",["-W","not-completed","-o","BJC85_Native"])
        guard jobs.code==0, jobs.output.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
            throw NSError(domain:"BJC85",code:1,userInfo:[NSLocalizedDescriptionKey:L("Finish or cancel the queued BJC-85 print jobs first.")])
        }
        return true
    }
    struct Result { let code: Int32; let output: String }
    static func command(_ path: String, _ arguments: [String]) throws -> Result {
        let process=Process(), pipe=Pipe()
        process.executableURL=URL(fileURLWithPath:path); process.arguments=arguments
        var environment=ProcessInfo.processInfo.environment; environment["LC_ALL"]="C"; process.environment=environment
        process.standardOutput=pipe; process.standardError=pipe
        try process.run(); let data=pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        return Result(code:process.terminationStatus,output:String(decoding:data,as:UTF8.self))
    }
    static func require(_ path: String,_ args: [String]) throws {
        let result=try command(path,args)
        guard result.code==0 else { throw NSError(domain:"BJC85",code:Int(result.code),userInfo:[NSLocalizedDescriptionKey:result.output]) }
    }
    static func stop(_ label: String) throws {
        let domain="gui/\(getuid())/\(label)"
        try require("/bin/launchctl",["disable",domain])
        if try command("/bin/launchctl",["print",domain]).code==0 { try require("/bin/launchctl",["bootout",domain]) }
    }
    static func quiesceScanner() throws {
        if try command("/bin/launchctl",["print","gui/\(getuid())/local.bjc85.native-scan"]).code==0 {
            let status=try command("/usr/bin/curl",["--fail","--silent","--max-time","3","http://127.0.0.1:8641/eSCL/ScannerStatus"])
            guard status.code==0, status.output.contains("<pwg:State>Idle</pwg:State>") else {
                throw NSError(domain:"BJC85",code:1,userInfo:[NSLocalizedDescriptionKey:L("Finish the Image Capture job or inspect its recovery state before switching device use.")])
            }
            try stop("local.bjc85.native-scan")
        }
    }
    private static func install(label: String,args: [String],bundle: URL,runtime: URL) throws {
        let fm=FileManager.default
        let agents=fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
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
    static func prepareScanner(bundle: URL,runtime: URL,reference: URL) throws {
        try requireAvailable(runtime)
        if try checkPrintQueue() {
            try require("/usr/sbin/cupsdisable",["-r",L("IS-12 scanner installed; restore BC-11e before printing."),"BJC85_Native"])
        }
        try stop("local.bjc85.native-print")
        try quiesceScanner()
        let helpers=bundle.appendingPathComponent("Contents/Helpers")
        try install(label:"local.bjc85.native-scan",args:[helpers.appendingPathComponent("is12-escl-bridge").path,"--scanner-installed",helpers.appendingPathComponent("bjc85-is12").path,reference.path],bundle:bundle,runtime:runtime)
    }
    static func preparePrinter(bundle: URL,runtime: URL) throws {
        try requireAvailable(runtime)
        _=try checkPrintQueue()
        try quiesceScanner()
        try stop("local.bjc85.native-print")
        let spool=runtime.appendingPathComponent(".state/print-spool")
        try FileManager.default.createDirectory(at:spool,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try install(label:"local.bjc85.native-print",args:[bundle.appendingPathComponent("Contents/Helpers/bjc85-ipp").path,"--print-cartridge=bc11e","--spool-dir",spool.path,"--port","8631"],bundle:bundle,runtime:runtime)
        var ready=false
        for _ in 0..<20 {
            if try command("/usr/bin/curl",["--fail","--silent","--max-time","1","http://127.0.0.1:8631/"]).code==0 { ready=true; break }
            Thread.sleep(forTimeInterval:0.25)
        }
        guard ready else { throw NSError(domain:"BJC85",code:1,userInfo:[NSLocalizedDescriptionKey:L("Print service did not become ready. Inspect the service log.")]) }
        let queue=try command("/usr/bin/lpstat",["-v","BJC85_Native"])
        if queue.code==0 && !queue.output.contains("ipp://localhost:8631/ipp/print") { throw CocoaError(.validationMissingMandatoryProperty) }
        try require("/usr/sbin/lpadmin",["-p","BJC85_Native","-E","-v","ipp://localhost:8631/ipp/print","-m","everywhere","-D",L("Canon BJC-85 Native"),"-o","printer-is-shared=false","-o","printer-error-policy=stop-printer"])
    }
}
