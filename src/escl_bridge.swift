import Foundation
import Network
import CoreGraphics
import ImageIO
import Darwin

// Single-page, local-only eSCL bridge. Native child processes own the USB protocol.
// ScanJobs starts one acquisition. Status reports its progress; NextDocument
// transfers the completed page without ever restarting a physical acquisition.
private let scanNS = "http://schemas.hp.com/imaging/escl/2011/05/03"
private let pwgNS = "http://www.pwg.org/schemas/2010/12/sm"
private let uuid = "00000000-0000-4000-8000-000000000009"
private let port: UInt16 = UInt16(ProcessInfo.processInfo.environment["BJC85_ESCL_PORT"] ?? "8641") ?? 8641
private let root = ProcessInfo.processInfo.environment["BJC85_RUNTIME_DIRECTORY"].map { URL(fileURLWithPath:$0,isDirectory:true) }
    ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("local.bjc85.utility",isDirectory:true)
private let arguments = CommandLine.arguments
guard arguments.count == 4 && arguments[1] == "--scanner-installed" else {
    fputs("Usage: is12-escl-bridge --scanner-installed NATIVE-DRIVER REFERENCE.bin\nPause printing first. Local clients can request one loaded sheet per job.\n", stderr)
    exit(2)
}
private let driver = URL(fileURLWithPath: arguments[2], relativeTo: root).standardizedFileURL
private let reference = URL(fileURLWithPath: arguments[3], relativeTo: root).standardizedFileURL
private let jobsRoot = root.appendingPathComponent(".state/escl-jobs", isDirectory: true)
umask(0o077)
try FileManager.default.createDirectory(at: jobsRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
// A restarted server never replays or silently abandons a paper-moving job.
for directory in try FileManager.default.contentsOfDirectory(at: jobsRoot, includingPropertiesForKeys: nil) {
    if !DriverOutcome.journalPermitsRestart(directory) {
        fputs("An interrupted scan needs inspection before restarting: \(directory.path)\n", stderr)
        exit(1)
    }
}

private func event(_ fields: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: fields, options: .sortedKeys) {
        print(String(decoding: data, as: UTF8.self)); fflush(stdout)
    }
}
private func envelope(_ name: String, _ body: String) -> Data {
    Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?><scan:\(name) xmlns:scan=\"\(scanNS)\" xmlns:pwg=\"\(pwgNS)\">\(body)</scan:\(name)>".utf8)
}
private let capabilities = envelope("ScannerCapabilities", """
<pwg:Version>2.0</pwg:Version><pwg:MakeAndModel>Canon BJC-85 IS-12 Native</pwg:MakeAndModel><pwg:SerialNumber>TEST-BJC85-0001-IS12</pwg:SerialNumber><scan:Manufacturer>Canon</scan:Manufacturer><scan:UUID>\(uuid)</scan:UUID>
<scan:Adf><scan:AdfSimplexInputCaps><scan:MinWidth>4</scan:MinWidth><scan:MaxWidth>2400</scan:MaxWidth><scan:MinHeight>4</scan:MinHeight><scan:MaxHeight>3240</scan:MaxHeight>
<scan:SettingProfiles><scan:SettingProfile><scan:ColorModes><scan:ColorMode>RGB24</scan:ColorMode><scan:ColorMode>Grayscale8</scan:ColorMode><scan:ColorMode>BlackAndWhite1</scan:ColorMode></scan:ColorModes><scan:DocumentFormats><pwg:DocumentFormat>image/png</pwg:DocumentFormat><pwg:DocumentFormat>image/jpeg</pwg:DocumentFormat></scan:DocumentFormats>
<scan:SupportedResolutions><scan:DiscreteResolutions><scan:DiscreteResolution><scan:XResolution>90</scan:XResolution><scan:YResolution>90</scan:YResolution></scan:DiscreteResolution><scan:DiscreteResolution><scan:XResolution>180</scan:XResolution><scan:YResolution>180</scan:YResolution></scan:DiscreteResolution><scan:DiscreteResolution><scan:XResolution>360</scan:XResolution><scan:YResolution>360</scan:YResolution></scan:DiscreteResolution></scan:DiscreteResolutions></scan:SupportedResolutions>
</scan:SettingProfile></scan:SettingProfiles><scan:SupportedIntents><scan:Intent>Document</scan:Intent><scan:Intent>Photo</scan:Intent></scan:SupportedIntents></scan:AdfSimplexInputCaps><scan:Justification><scan:XImagePosition>Left</scan:XImagePosition><scan:YImagePosition>Top</scan:YImagePosition></scan:Justification></scan:Adf>
""")

private final class Settings: NSObject, XMLParserDelegate {
    var values: [String: String] = [:], stack: [String] = []
    var text = "", invalid = false
    var dpi = 90, x = 0, y = 0, width = 2400, height = 3240
    var mode = "color", mime = "image/png"
    init?(_ data: Data) {
        super.init()
        guard let source = String(data: data, encoding: .utf8), !source.uppercased().contains("<!DOCTYPE"), !source.uppercased().contains("<!ENTITY") else { return nil }
        let parser = XMLParser(data: data); parser.delegate = self
        parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false
        guard parser.parse(), !invalid, stack.isEmpty,
              let rx = values["XResolution"].flatMap(Int.init), let ry = values["YResolution"].flatMap(Int.init), rx == ry, [90,180,360].contains(rx),
              values["InputSource"] == "Feeder", [nil,"false","0"].contains(values["Duplex"]),
              let w = values["Width"].flatMap(Int.init), let h = values["Height"].flatMap(Int.init),
              let ox = values["XOffset"].flatMap(Int.init), let oy = values["YOffset"].flatMap(Int.init),
              (4...2400).contains(w), (4...3240).contains(h), (0...2400-w).contains(ox), (0...3240-h).contains(oy),
              let colour = values["ColorMode"], ["RGB24","Grayscale8","BlackAndWhite1"].contains(colour),
              let format = values["DocumentFormatExt"] ?? values["DocumentFormat"], ["image/png","image/jpeg"].contains(format) else { return nil }
        if let units = values["ContentRegionUnits"], !units.hasSuffix("ThreeHundredthsOfInches") { return nil }
        dpi=rx; x=ox; y=oy; width=w; height=h; mime=format
        mode=colour == "RGB24" ? "color" : colour == "Grayscale8" ? "gray" : "bw"
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if stack.isEmpty && (name != "ScanSettings" || namespaceURI != scanNS) { invalid=true }
        if namespaceURI != scanNS && namespaceURI != pwgNS { invalid=true }
        stack.append(name); text=""
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value=text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { if values[name] != nil { invalid=true }; values[name]=value }
        if stack.popLast() != name { invalid=true }; text=""
    }
}

private final class HTTPRequest {
    let connection: NWConnection
    var buffer=Data(), parsed=false, answered=false
    var method="", path="", headers: [String: String]=[:], body=Data()
    init(_ connection: NWConnection) { self.connection=connection }
    func start() {
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now()+10) { [weak self] in
            guard let self, !self.parsed else { return }; self.connection.cancel()
        }
        read()
    }
    func read() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, complete, error in
            if let data { self.buffer.append(data) }
            guard self.buffer.count <= 81920 else { self.reply(413); return }
            if let delimiter=self.buffer.range(of: Data("\r\n\r\n".utf8)) {
                guard delimiter.lowerBound <= 16384 else { self.reply(431); return }
                let lines=String(decoding: self.buffer[..<delimiter.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
                let first=lines[0].split(separator: " ")
                guard first.count == 3 else { self.reply(400); return }
                self.method=String(first[0]); self.path=String(first[1]); self.headers=[:]
                for line in lines.dropFirst() {
                    guard let colon=line.firstIndex(of: ":") else { self.reply(400); return }
                    let key=line[..<colon].lowercased(), value=line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    guard self.headers[key] == nil else { self.reply(400); return }; self.headers[key]=value
                }
                let hosts=["localhost:\(port)","localhost.:\(port)","127.0.0.1:\(port)"]
                guard hosts.contains(self.headers["host"]?.lowercased() ?? ""), self.headers["origin"] == nil else { self.reply(403); return }
                guard self.headers["transfer-encoding"] == nil, let length=Int(self.headers["content-length"] ?? "0"), (0...65536).contains(length) else { self.reply(400); return }
                let available=self.buffer.count-delimiter.upperBound
                if available < length {
                    if error == nil && !complete { self.read() } else { self.connection.cancel() }; return
                }
                guard available == length else { self.reply(400); return }
                self.body=self.buffer.subdata(in: delimiter.upperBound..<self.buffer.count); self.parsed=true
                bridge.handle(self)
            } else if error == nil && !complete { self.read() }
            else { self.connection.cancel() }
        }
    }
    func reply(_ code: Int, data: Data=Data(), mime: String="text/xml", location: String?=nil, sent: ((Bool)->Void)?=nil) {
        guard !answered else { return }; answered=true
        let descriptions=[200:"OK",201:"Created",204:"No Content",400:"Bad Request",403:"Forbidden",404:"Not Found",409:"Conflict",413:"Payload Too Large",415:"Unsupported Media Type",431:"Request Header Fields Too Large",500:"Internal Server Error",503:"Service Unavailable"]
        var head="HTTP/1.1 \(code) \(descriptions[code] ?? "Error")\r\nContent-Type: \(mime)\r\nContent-Length: \(data.count)\r\nConnection: close\r\nCache-Control: no-store\r\n"
        if code == 503 { head += "Retry-After: 1\r\n" }
        if let location { head += "Location: \(location)\r\n" }
        var response=Data((head+"\r\n").utf8); response.append(data)
        event(["event":"http_response","method":method,"path":path,"status":code,"bytes":data.count])
        connection.send(content: response, completion: .contentProcessed { error in sent?(error == nil); self.connection.cancel() })
    }
}

private final class Job {
    let id=UUID().uuidString, settings: Settings, directory: URL, referenceURL: URL
    let created=Date()
    var stage="Pending", process: Process?, started=false, delivered=false, cancelled=false, sending=false, preflightDone=false
    var phaseSpawned=false
    var log: FileHandle?, output: Data?
    init(_ settings: Settings) throws {
        self.settings=settings; directory=jobsRoot.appendingPathComponent(id, isDirectory: true)
        if let data=try? Data(contentsOf:root.appendingPathComponent(".state/scanner-app/settings.json")),
           let values=try? JSONSerialization.jsonObject(with:data) as? [String:String], let path=values["reference"] {
            referenceURL=URL(fileURLWithPath:path)
        } else { referenceURL=reference }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
    var statusXML: String {
        let completed=stage == "Completed" ? 1 : 0
        return "<scan:JobInfo><pwg:JobUri>/eSCL/ScanJobs/\(id)</pwg:JobUri><pwg:JobUuid>\(id)</pwg:JobUuid><scan:Age>\(Int(Date().timeIntervalSince(created)))</scan:Age><pwg:ImagesCompleted>\(completed)</pwg:ImagesCompleted><pwg:ImagesToTransfer>\(completed == 1 && !delivered ? 1 : 0)</pwg:ImagesToTransfer><scan:TransferRetryCount>0</scan:TransferRetryCount><pwg:JobState>\(stage)</pwg:JobState></scan:JobInfo>"
    }
}
private final class Bridge {
    var jobs: [String: Job]=[:], active: Job?, stopping=false, recoveryRequired=false
    func handle(_ request: HTTPRequest) {
        let shared = active?.process == nil ? SharedDeviceState.inspect(root) : .busy
        if shared == .recoveryRequired { recoveryRequired=true }
        if request.method == "GET" && request.path == "/eSCL/ScannerCapabilities" { request.reply(200,data:capabilities); return }
        if request.method == "GET" && request.path == "/eSCL/ScannerStatus" {
            let busy=active?.process != nil || shared == .busy
            let jobStatus=jobs.values.sorted {$0.created > $1.created}.map {$0.statusXML}.joined()
            request.reply(200,data:envelope("ScannerStatus","<pwg:Version>2.0</pwg:Version><pwg:State>\(recoveryRequired ? "Stopped" : busy ? "Processing" : "Idle")</pwg:State><scan:AdfState>\(recoveryRequired ? "ScannerAdfJam" : "ScannerAdfLoaded")</scan:AdfState><scan:Jobs>\(jobStatus)</scan:Jobs>")); return
        }
        if request.method == "POST" && request.path == "/eSCL/ScanJobs" {
            guard !stopping, !recoveryRequired, shared != .busy, active?.process == nil, active?.stage != "Pending" else { request.reply(503); return }
            guard ["text/xml","application/xml"].contains(request.headers["content-type"]?.split(separator:";").first?.trimmingCharacters(in: .whitespaces) ?? "") else { request.reply(415); return }
            guard let settings=Settings(request.body) else {
                event(["event":"rejected_scan_settings","bytes":request.body.count]); request.reply(400); return
            }
            do {
                let job=try Job(settings)
                try request.body.write(to:job.directory.appendingPathComponent("settings.xml"),options:.withoutOverwriting)
                jobs[job.id]=job; active=job
                // Keep only a bounded recent index; raw captures stay on disk.
                if jobs.count > 4, let old=jobs.values.filter({$0.id != job.id && $0.process == nil && !$0.sending}).min(by:{$0.created < $1.created}) { jobs.removeValue(forKey:old.id) }
                request.reply(201,location:"http://localhost:\(port)/eSCL/ScanJobs/\(job.id)")
                start(job)
            } catch { request.reply(500) }
            return
        }
        let components=request.path.split(separator:"/")
        guard components.count >= 3, components[0] == "eSCL", components[1] == "ScanJobs", let job=jobs[String(components[2])] else { request.reply(404); return }
        if request.method == "DELETE" && components.count == 3 {
            job.cancelled=true
            if job.stage != "Completed" { job.stage="Canceled"; job.process?.interrupt() }
            job.output=nil; request.reply(200); return
        }
        if request.method == "GET" && components.count == 3 {
            request.reply(200,data:envelope("Jobs",job.statusXML)); return
        }
        guard request.method == "GET", components.count == 4, components[3] == "NextDocument" else { request.reply(404); return }
        if job.cancelled || job.delivered { request.reply(404); return }
        if job.sending { request.reply(503); return }
        if let output=job.output {
            job.sending=true
            request.reply(200,data:output,mime:job.settings.mime,sent:{ success in
                job.sending=false
                if success {
                    job.delivered=true; job.output=nil
                    if !FileManager.default.fileExists(atPath:root.appendingPathComponent("retain-diagnostics").path) {
                        do {
                            try PrivacyRetention.removeExportedCapture(job.directory.appendingPathComponent("capture"),retainDiagnostics:false,outcome:.completedSafe)
                            for name in ["document.jpg","document.png","driver.jsonl"] {
                                let file=job.directory.appendingPathComponent(name)
                                if FileManager.default.fileExists(atPath:file.path) { try FileManager.default.removeItem(at:file) }
                            }
                        } catch { event(["event":"capture_cleanup_failed","job":job.id]) }
                    }
                }
            }); return
        }
        if job.stage == "Aborted" { request.reply(500); return }
        // Acquisition is much slower than Apple's HTTP request timeout. A short
        // retry response leaves the same job running and avoids losing its page
        // to a timed-out socket. Never start another sheet for a retry.
        request.reply(503)
    }
    func start(_ job: Job) {
        job.started=true; job.stage="Processing"
        let logURL=job.directory.appendingPathComponent("driver.jsonl")
        do {
            let marker=try JSONSerialization.data(withJSONObject:["job":job.id,"started":Date().description,"dpi":job.settings.dpi,"mode":job.settings.mode,"reference":job.referenceURL.path],options:.sortedKeys)
            try marker.write(to:job.directory.appendingPathComponent("acquisition-started.json"),options:.withoutOverwriting)
            guard FileManager.default.createFile(atPath:logURL.path,contents:nil,attributes:[.posixPermissions:0o600]) else { throw CocoaError(.fileWriteUnknown) }
            job.log=try FileHandle(forWritingTo:logURL)
            runChild(job)
        } catch { finished(job,code:1) }
    }
    func runChild(_ job: Job) {
        let process=Process()
        job.phaseSpawned=false
        do {
            process.executableURL=driver; process.currentDirectoryURL=root
            var environment=ProcessInfo.processInfo.environment
            environment["BJC85_STATE_DIRECTORY"]=root.path; process.environment=environment
            process.arguments=job.preflightDone ?
                ["scan","--scanner-installed","--dpi",String(job.settings.dpi),"--mode",job.settings.mode,"--calibration",job.referenceURL.path,job.directory.appendingPathComponent("capture").path] :
                ["status","--scanner-installed","--enter-scanner-mode","--reference",job.referenceURL.path]
            process.standardOutput=job.log; process.standardError=job.log
            process.terminationHandler={ process in DispatchQueue.main.async {
                let result=DriverOutcome.read(job.directory.appendingPathComponent("driver.jsonl"))
                if !job.preflightDone && process.terminationStatus == 0 && result.readiness?.canScan == true &&
                    result.readiness?.reference_valid == true &&
                    result.outcome?.permitsNextOperation == true && !job.cancelled && !self.stopping {
                    job.preflightDone=true; self.runChild(job)
                } else { self.finished(job,code:process.terminationStatus) }
            } }
            job.process=process
            try process.run()
            job.phaseSpawned=true
            event(["event":job.preflightDone ? "native_scan_started" : "native_probe_started","job":job.id,"dpi":job.settings.dpi,"mode":job.settings.mode])
        } catch { finished(job,code:1) }
    }
    func finished(_ job: Job, code: Int32) {
        job.process=nil; try? job.log?.synchronize(); try? job.log?.close(); job.log=nil
        let result=DriverOutcome.read(job.directory.appendingPathComponent("driver.jsonl"))
        var outcome: OperationOutcome = job.phaseSpawned ? (result.outcome ?? .recoveryRequired) : .preflightFailedSafe
        // A preflight result cannot certify a later acquisition whose helper died.
        if job.preflightDone && job.phaseSpawned {
            if let data=try? Data(contentsOf:job.directory.appendingPathComponent("capture/outcome.json")),
               let receipt=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
               let name=receipt["outcome"] as? String, let value=OperationOutcome(rawValue:name) { outcome=value }
            else { outcome = .recoveryRequired }
        }
        do {
            let terminal=try JSONSerialization.data(withJSONObject:["exit_code":code,"cancelled":job.cancelled,"outcome":outcome.rawValue,"finished":Date().description],options:.sortedKeys)
            try terminal.write(to:job.directory.appendingPathComponent("acquisition-ended.json"),options:.atomic)
        } catch { outcome = .recoveryRequired }
        recoveryRequired = recoveryRequired || !outcome.permitsNextOperation
        guard code == 0 && !job.cancelled && job.preflightDone && outcome == .completedSafe else {
            job.stage=job.cancelled ? "Canceled" : "Aborted"
            event(["event":"native_scan_stopped","job":job.id,"code":code]); if stopping { exit(0) }; return
        }
        do {
            let imageURL=job.directory.appendingPathComponent("capture/scan-raw.png")
            guard let source=CGImageSourceCreateWithURL(imageURL as CFURL,nil), let image=CGImageSourceCreateImageAtIndex(source,0,nil) else { throw CocoaError(.fileReadCorruptFile) }
            let s=job.settings, scale=Double(s.dpi)/300
            let left=(Double(s.x)*scale).rounded(), top=(Double(s.y)*scale).rounded()
            let right=(Double(s.x+s.width)*scale).rounded(), bottom=(Double(s.y+s.height)*scale).rounded()
            let rect=CGRect(x:left,y:top,width:right-left,height:bottom-top)
            guard let cropped=image.cropping(to:rect), cropped.width == Int(rect.width), cropped.height == Int(rect.height) else { throw CocoaError(.fileReadCorruptFile) }
            let data=NSMutableData()
            let uti=s.mime == "image/jpeg" ? "public.jpeg" : "public.png"
            guard let destination=CGImageDestinationCreateWithData(data as CFMutableData,uti as CFString,1,nil) else { throw CocoaError(.fileWriteUnknown) }
            let properties:[CFString:Any]=[kCGImagePropertyDPIWidth:s.dpi,kCGImagePropertyDPIHeight:s.dpi,kCGImageDestinationLossyCompressionQuality:1.0]
            CGImageDestinationAddImage(destination,cropped,properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
            let output=data as Data
            try output.write(to:job.directory.appendingPathComponent(s.mime == "image/jpeg" ? "document.jpg" : "document.png"),options:.withoutOverwriting)
            job.output=output; job.stage="Completed"
            event(["event":"native_scan_completed","job":job.id,"width":cropped.width,"height":cropped.height,"mime":s.mime])
        } catch { job.stage="Aborted"; event(["event":"export_error","job":job.id,"error":error.localizedDescription]) }
        if stopping { exit(0) }
    }
    func stop() {
        stopping=true; is12_escl_unpublish(); listener.cancel()
        if let process=active?.process { active?.cancelled=true; process.interrupt() } else { exit(0) }
    }
}
private let bridge=Bridge()
// Clients can disappear without downloading. Keep safe completed document data
// for at most 24 hours by default, including across service restart.
private let retentionTimer=DispatchSource.makeTimerSource(queue:.main)
retentionTimer.schedule(deadline:.now(),repeating:3600)
retentionTimer.setEventHandler {
    do {
        let expired=try PrivacyRetention.removeExpiredESCLDocuments(root)
        for id in expired { bridge.jobs[id]?.output=nil; bridge.jobs[id]?.delivered=true }
    } catch { event(["event":"expired_capture_cleanup_failed"]) }
}
retentionTimer.resume()
private let parameters=NWParameters.tcp
parameters.requiredLocalEndpoint = .hostPort(host:.ipv4(.loopback),port:NWEndpoint.Port(rawValue:port)!)
private let listener=try NWListener(using:parameters)
listener.newConnectionHandler={ HTTPRequest($0).start() }
listener.stateUpdateHandler={ state in
    if case .ready=state {
        guard ProcessInfo.processInfo.environment["BJC85_ESCL_ADVERTISE"] == "0" || is12_escl_publish(UInt32(port)) else { fputs("Local AirScan publication failed.\n",stderr); exit(1) }
        event(["event":"airscan_ready","address":"127.0.0.1","port":port,"one_page_per_job":true])
    } else if case .failed(let error)=state { fputs("Listener failed: \(error)\n",stderr); exit(1) }
}
signal(SIGINT,SIG_IGN); signal(SIGTERM,SIG_IGN)
private let interrupt=DispatchSource.makeSignalSource(signal:SIGINT,queue:.main)
private let terminate=DispatchSource.makeSignalSource(signal:SIGTERM,queue:.main)
interrupt.setEventHandler { bridge.stop() }; terminate.setEventHandler { bridge.stop() }
interrupt.resume(); terminate.resume(); listener.start(queue:.main)
dispatchMain()
