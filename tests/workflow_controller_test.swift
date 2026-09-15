import AppKit
final class InjectedServices: ScannerServices {
    var response: Result<Void,Error> = .success(())
    var delayed: ((Result<Void,Error>) -> Void)?
    var delay=false
    func quiesce(completion:@escaping @MainActor @Sendable (Result<Void,Error>) -> Void) { if delay { delayed=completion } else { completion(response) } }
}
final class InjectedRunner: ScannerProcess {
    var launches=0, cancels=0, fail=false
    var terminal: ((Int32,Bool) -> Void)?
    var receive: ((Data) -> Void)?
    func launch(arguments:[String],log:URL,receive:@escaping @MainActor @Sendable (Data)->Void,completion:@escaping @MainActor @Sendable (Int32,Bool)->Void) throws {
        if fail { throw CocoaError(.executableNotLoadable) }; launches += 1; terminal=completion; self.receive=receive
    }
    func cancel() { cancels += 1 }
}
final class InjectedQueue: PrintQueueAccess {
    var submissions=0, cancels=0, queries=0
    var status=PrintJobResult.pending
    var fail=false
    var refuse=false
    func submit(_ image:URL,settings:PrintSettings) throws -> Int { submissions += 1; if refuse { throw PrintSubmissionFailure.refusedBeforeAcceptance("fixture refusal") }; if fail { throw CocoaError(.fileWriteUnknown) }; return 42 }
    func query(destination:String,id:Int) throws -> QueueJobStatus { queries += 1; precondition(id==42 && destination=="BJC85_Native"); if fail { throw CocoaError(.fileReadUnknown) }; return .init(result:status,reasons:["fixture"] ) }
    func cancel(destination:String,id:Int) throws { cancels += 1 }
}
@main @MainActor struct ControllerTests {
    static func main() throws {
        _=NSApplication.shared
        let fm=FileManager.default, directory=fm.temporaryDirectory.appendingPathComponent("bjc85-workflows-\(UUID())")
        try fm.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]); defer { try? fm.removeItem(at:directory) }
        let services=InjectedServices(), runner=InjectedRunner(), controller=ScanOperationController(services:services,runner:runner)
        var terminals:[ScanOperationCompletion]=[]
        controller.completed={ terminals.append($0) }
        func request(_ id:UUID=UUID()) -> ScanOperationRequest { .init(id:id,copyAttempt:id,kind:"scan",arguments:[],directory:directory.appendingPathComponent("scan-fixture"),log:directory.appendingPathComponent("test.log"),capture:ScanCapture(acquisition:ScanAcquisition(acquired:Date(),dpi:90,width:1,height:1,source:"Fixture",mode:"Image",whiteReference:nil),edits:.init(),prescan:false)) }
        for message in ["busy service","timeout","quiescence failure"] {
            services.response = .failure(NSError(domain:"fixture",code:1,userInfo:[NSLocalizedDescriptionKey:message]))
            precondition(controller.start(request())); precondition(controller.active==nil && terminals.last?.launched==false && runner.launches==0)
        }
        services.response = .success(()); runner.fail=true
        precondition(controller.start(request())); precondition(controller.active==nil && terminals.count==4)
        runner.fail=false; services.delay=true
        precondition(controller.start(request())); controller.cancel(); services.delayed?(.success(()))
        precondition(controller.active==nil && runner.launches==0 && terminals.last?.exitCode==6)
        services.delay=false
        let old=request(); precondition(controller.start(old)); let callback=runner.terminal!
        callback(1,true); callback(1,true); precondition(terminals.count==6)
        let next=request(); precondition(controller.start(next)); callback(0,true); precondition(controller.active?.id==next.id)
        runner.terminal?(0,true); precondition(controller.active==nil && terminals.count==7)
        print("PASS: actual ScanOperationController busy/timeout/quiescence refusal, launch failure, canceled preflight, stale and duplicate completion, subsequent scan.")
        let ready=ScannerReadiness(kind:"ready",transport_ok:true,replies_ok:true,head_matches:true,ready:true,temperature_raw:50)
        var device=DeviceCoordinator(); device.observe(ready,hasReference:true)
        precondition(device.requestScan()); device.preflightRefused(); precondition(device.state == .scannerReady)
        _=device.requestPrint(); device.cancelPrintCartridge(unchanged:true); precondition(device.state == .scannerReady)
        _=device.requestPrint(); device.cancelPrintCartridge(unchanged:false); precondition(device.state == .scannerDetected)
        device.observe(ready,hasReference:true); precondition(device.state == .scannerReady)
        var copy=CopyWorkflow(); let attempt=UUID(); precondition(copy.beginScan(id:attempt)); copy.scanStopped(safely:true,attempt:attempt)
        precondition(copy.stage == .empty)
        let ordinary=UUID(); precondition(copy.beginScan(id:ordinary)); precondition(!copy.retain(directory,attempt:attempt))
        precondition(copy.retain(directory,attempt:ordinary)); _=device.requestPrint(); precondition(device.confirmPrintCartridge(servicePrepared:true)); precondition(copy.printerConfirmed())
        var settings=PrintSettings(); settings.copies=0; precondition(!copy.canPrint(settings:settings,device:device.state,busy:false))
        settings.copies=2; precondition(copy.canPrint(settings:settings,device:device.state,busy:false))
        let printAttempt=UUID(); precondition(copy.beginPrint(id:printAttempt) != nil); copy.printFinished(.rejected,safe:true,attempt:printAttempt)
        precondition(copy.stage == .readyToPrint && copy.canPrint(settings:settings,device:device.state,busy:false))
        let second=UUID(); _=copy.beginPrint(id:second); copy.printFinished(.completed,safe:true,attempt:second); precondition(copy.stage == .reprintReady)
        let third=UUID(); _=copy.beginPrint(id:third); copy.printFinished(.cancelled,safe:false,attempt:third); precondition(copy.stage == .recoveryRequired && !copy.reset())
        print("PASS: cartridge cancellation with unchanged/uncertain evidence, retryable Copy after validation correction/rejection, reconnect, no rescanning for reprint, recovery reset block.")
        let queue=InjectedQueue(), file=directory.appendingPathComponent("job.json")
        let tracker=try PrintJobTracker(file:file,queue:queue)
        let job=try tracker.submit(directory,settings:settings,document:nil,copy:true,attempt:UUID())
        precondition(job.result == .pending && queue.submissions==1)
        let restored=try PrintJobTracker(file:file,queue:queue); precondition(restored.record==job && queue.submissions==1)
        try restored.cancel(); precondition(queue.cancels==1 && restored.record?.result == .pending)
        for state in [PrintJobResult.unknown,.pending,.cancelled] {
            queue.status=state; let value=try restored.reconcile(); precondition(value?.result==state)
        }
        for state in [PrintJobResult.completed,.aborted,.unknown] {
            let instance=try PrintJobTracker(file:directory.appendingPathComponent("\(state).json"),queue:queue)
            _=try instance.submit(directory,settings:settings,document:nil,copy:false,attempt:UUID()); queue.status=state
            let value=try instance.reconcile(); precondition(value?.result==state)
            _=try instance.reconcile()
        }
        let failed=try PrintJobTracker(file:directory.appendingPathComponent("failure.json"),queue:queue)
        queue.fail=true; let result=try failed.submit(directory,settings:settings,document:nil,copy:true,attempt:UUID()); precondition(result.result == .unknown && result.jobID==nil)
        let count=queue.submissions
        do { _=try failed.submit(directory,settings:settings,document:nil,copy:true,attempt:UUID()); preconditionFailure() } catch { }
        precondition(queue.submissions==count)
        queue.fail=false
        let queryFailure=try PrintJobTracker(file:directory.appendingPathComponent("query-failure.json"),queue:queue)
        _=try queryFailure.submit(directory,settings:settings,document:nil,copy:false,attempt:UUID())
        queue.fail=true; let queries=queue.queries
        let unavailable=try queryFailure.reconcile()
        precondition(queue.queries==queries+1 && unavailable?.result == .unknown && unavailable?.jobID==42)
        queue.fail=false; queue.status = .completed
        let reconciled=try queryFailure.reconcile(); precondition(reconciled?.result == .completed)
        queue.refuse=true
        let refused=try PrintJobTracker(file:directory.appendingPathComponent("refused.json"),queue:queue)
        let refusal=try refused.submit(directory,settings:settings,document:nil,copy:true,attempt:UUID())
        precondition(refusal.result == .rejected && refusal.jobID==nil && !refusal.outstanding)
        queue.refuse=false
        print("PASS: actual queue query error remains unknown with exact job ID, later reconciliation succeeds without replay; typed refusal before acceptance is retryable rejection.")
        print("PASS: authoritative pending/completed/canceled/aborted/unknown results, restart reconciliation without resubmission, failed submission remains unknown, duplicate terminal queries, no replay.")
        // Test the actual window/controller projection with injected preflight.
        setenv("BJC85_FIXTURE_DIRECTORY",directory.appendingPathComponent("ui").path,1)
        let utility=UtilityWindowController()
        let deadline=Date().addingTimeInterval(10)
        while utility.tracker==nil && Date()<deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.02)) }
        precondition(utility.tracker != nil)
        let appServices=InjectedServices(), appRunner=InjectedRunner()
        appServices.response = .failure(NSError(domain:"fixture",code:1,userInfo:[NSLocalizedDescriptionKey:"Image Capture busy"]))
        utility.scanController=ScanOperationController(services:appServices,runner:appRunner)
        utility.scanController.completed={ utility.scanFinished($0) }
        utility.reference=directory.appendingPathComponent("reference.bin"); utility.referenceValid=true; utility.model.coordinator.observe(ready,hasReference:true)
        utility.scan.isEnabled=true; utility.acquire(copy:true)
        precondition(utility.model.copy.stage == .empty && utility.model.coordinator.state == .scannerReady && utility.scanController.active==nil)
        precondition(utility.layout.status.stringValue.contains("Image Capture busy"), "Synchronous refusal must not be overwritten by preparing progress")
        utility.lastAvailability = .busy; utility.updateControls()
        precondition(utility.layout.device.stringValue.contains("device in use"))
        precondition(utility.layout.device.accessibilityValue()?.contains("device in use") == true)
        precondition(utility.model.coordinator.state == .scannerReady, "An availability check must not claim disconnection")
        utility.lastAvailability = .available
        appServices.delay=true
        utility.model.scan.imageType = .blackAndWhite; utility.model.scan.previewType = .grayscale
        utility.model.scan.dpi=360; utility.isPrescan=true; utility.scan.isEnabled=true; utility.acquire(copy:true)
        let capture=utility.scanController.active!.capture!
        utility.model.scan.dpi=180; utility.model.scan.imageType = .colour; utility.isPrescan=false
        precondition(capture.prescan && capture.acquisition.dpi==90 && capture.acquisition.mode=="gray" && capture.edits.imageType == .blackAndWhite)
        utility.scanController.cancel(); appServices.delayed?(.success(()))
        precondition(appRunner.launches==0 && utility.model.copy.stage == .empty && utility.model.coordinator.state == .scannerReady)
        print("PASS: actual acquisition request freezes prescan mode, DPI and edits before mutable settings change; cancellation never launches a helper.")
        utility.model.copy.retain(directory); _=utility.model.copy.printerConfirmed(); _=utility.model.coordinator.requestPrint(); _=utility.model.coordinator.confirmPrintCartridge(servicePrepared:true)
        utility.copyControls.settings.copies.stringValue="0"; utility.updateControls(); precondition(!utility.copyControls.reprint.isEnabled)
        utility.copyControls.settings.copies.stringValue="3"; utility.updateControls()
        precondition(utility.model.copy.canPrint(settings:utility.copyControls.settings.settings,device:utility.model.coordinator.state,busy:false))
        precondition(utility.copyControls.reprint.title == "Print retained copy")
        precondition(!utility.copyControls.reprint.isEnabled, "fixture must not reach an installed queue")
        precondition(!utility.canPerform(#selector(utility.connectScanner)))
        let beforeTransfer=UUID(); _=utility.model.copy.beginPrint(id:beforeTransfer); _=utility.model.coordinator.requestPrint()
        let canceled=PrintJobRecord(attempt:beforeTransfer,document:nil,isCopy:true,destination:"BJC85_Native",created:Date(),jobID:99,result:.cancelled,reasons:["job-canceled-by-user"])
        utility.latestJob=canceled; utility.applyJobResult(canceled,safety:.available)
        precondition(utility.model.copy.stage == .readyToPrint && utility.model.coordinator.state == .printerReady)
        let afterTransfer=UUID(); _=utility.model.copy.beginPrint(id:afterTransfer); _=utility.model.coordinator.requestPrint()
        let ambiguous=PrintJobRecord(attempt:afterTransfer,document:nil,isCopy:true,destination:"BJC85_Native",created:Date(),jobID:100,result:.cancelled,reasons:["transfer started; safe completion unknown"])
        utility.latestJob=ambiguous; utility.applyJobResult(ambiguous,safety:.recoveryRequired)
        precondition(utility.model.copy.stage == .recoveryRequired && utility.model.coordinator.state == .recoveryRequired && !utility.copyControls.reset.isEnabled)
        print("PASS: actual terminal job projection distinguishes canceled-before-transfer safe retry from canceled-after-transfer recovery; no success wording or recovery reset.")
        print("PASS: actual UtilityWindowController rejects Copy preflight without stale scanning state; inline settings/next action refresh; fixture physical actions remain disabled.")
    }
}
