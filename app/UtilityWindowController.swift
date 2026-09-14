import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class UtilityWindowController: NSObject, NSWindowDelegate, NSMenuItemValidation, NSToolbarDelegate, NSToolbarItemValidation {
    let window: NSWindow?
    func showWindow(_ sender:Any?) { window?.makeKeyAndOrderFront(sender) }
    let layout = WorkspaceLayout()
    var model = AppModel()
    var document: ScanDocument?
    let processing = ImageProcessingService()
    var store: ScanDocumentStore!
    var scanController: ScanOperationController!
    var tracker: PrintJobTracker!
    var previewTicket: ProcessingTicket?
    var exportTicket: ProcessingTicket?
    var documentBusy = false
    var serviceBusy = false
    var reference: URL?
    var referenceValid: Bool?
    var lastOutcome: OperationOutcome?
    var lastAvailability: SharedDeviceState.State?
    var activeCopyAttempt: UUID?
    var isPrescan = false
    var hasPrescan = false
    var livePreview: LiveScanPreview?
    var pending = Data()
    var latestJob: PrintJobRecord?
    var jobTimer: Timer?
    var savingError: String?
    let editUndo = UndoManager()
    let root: URL
    let state: URL
    let fixture = HardwareAccess.fixtureMode
    let preset = NSPopUpButton(), mode = NSPopUpButton(), resolution = NSPopUpButton(), filter = NSPopUpButton()
    let brightness = NSSlider(value:0,minValue:-1,maxValue:1,target:nil,action:nil)
    let contrast = NSSlider(value:1,minValue:0,maxValue:2,target:nil,action:nil)
    let threshold = NSSlider(value:128,minValue:0,maxValue:255,target:nil,action:nil)
    let invert = NSButton(checkboxWithTitle:"Invert",target:nil,action:nil)
    let bottomFirst = NSButton(checkboxWithTitle:"Sheet fed bottom first",target:nil,action:nil)
    let presetNote = RootView.label("")
    let connect = NSButton(title:"Connect scanner",target:nil,action:nil)
    let scan = NSButton(title:"Scan loaded page…",target:nil,action:nil)
    let prescan = NSButton(title:"Prescan loaded page…",target:nil,action:nil)
    let calibrate = NSButton(title:"White-Level Calibration…",target:nil,action:nil)
    let referenceLabel = RootView.label("No saved white reference")
    let printSettings = PrintSettingsView()
    let copyControls = CopyWorkflowView()
    let printButton = NSButton(title:"Print document…",target:nil,action:nil)
    let swap = NSButton(title:"Prepare printing…",target:nil,action:nil)
    let jobLabel = RootView.label("No print job submitted")
    var panels: [NSView] = []
    var actionButtons: [NSButton] = []
    var settingsWindow: NSWindowController?
    var savePanel: NSSavePanel?
    var processingCount = 0
    var busy: Bool { serviceBusy || scanController?.active != nil || latestJob?.result == .pending }
    override init() {
        let support = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        if HardwareAccess.fixtureMode {
            root = ProcessInfo.processInfo.environment["BJC85_FIXTURE_DIRECTORY"].map { URL(fileURLWithPath:$0) }
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("BJC85-Fixture-\(UUID().uuidString)")
        } else {
            root = ProcessInfo.processInfo.environment["BJC85_RUNTIME_DIRECTORY"].map { URL(fileURLWithPath:$0) }
                ?? support.appendingPathComponent("local.bjc85.utility")
        }
        state = root.appendingPathComponent(".state/scanner-app")
        let window = UtilityWindow(contentRect:NSRect(x:0,y:0,width:1140,height:780),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        self.window=window
        super.init()
        window.title = fixture ? "BJC-85 Utility — Fixture" : "BJC-85 Utility"
        window.subtitle = "Independent BJC-85 / IS-12 project"
        // 145-point navigation + 320-point canvas + 285-point inspector and
        // dividers remain usable together at this observed window width.
        window.minSize = NSSize(width:760,height:560); window.delegate=self
        // Inspector contents change with the workspace. Keep newly installed
        // controls in the native Tab loop instead of retaining the old loop.
        window.autorecalculatesKeyViewLoop = true
        window.contentViewController=layout; window.toolbarStyle = .unified
        window.setFrameAutosaveName(fixture ? "BJC85FixtureWindow" : "BJC85DocumentWindow")
        if let screen = NSScreen.main, !screen.visibleFrame.intersects(window.frame) { window.center() }
        let toolbar=NSToolbar(identifier:"DocumentToolbar"); toolbar.delegate=self; toolbar.displayMode = .iconOnly; window.toolbar=toolbar
        makeControls(); makeMenus()
        layout.selected = { [weak self] row in self?.selectWorkspace(row) }
        selectWorkspace(0)
        layout.canvas.changed = { [weak self] region in self?.changeEdits { $0.region=region } }
        bootstrap()
    }
    required init?(coder:NSCoder) { fatalError() }
    func bootstrap() {
        documentBusy=true; updateControls()
        processing.perform(work: { [root,state] in
            try FileManager.default.createDirectory(at:state,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let store=try ScanDocumentStore(runtime:root)
            try store.recoverCompletedCaptures(); try store.purgeExportedClosed()
            return (store, try store.restore())
        }) { [weak self] result in
            guard let self else { return }
            self.documentBusy=false
            do {
                let (store,document)=try result.get(); self.store=store; self.document=document
                let runner=NativeScannerProcess(helper:Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/bjc85-is12"),runtime:self.root)
                self.scanController=ScanOperationController(services:NativeScannerServices(runtime:self.root),runner:runner)
                self.scanController.receive = { [weak self] id,data in self?.receive(id,data) }
                self.scanController.completed = { [weak self] value in self?.scanFinished(value) }
                self.loadRuntimeState()
                let args=CommandLine.arguments
                if let index=args.firstIndex(where: { $0 == "--fixture" || $0 == "--preview" }), index+1<args.count, !args[index+1].hasPrefix("--") {
                    self.importImage(URL(fileURLWithPath:args[index+1]))
                } else { self.syncEdits(); self.refreshPreview(); self.applyFixturePresentation() }
            } catch { self.report(error) }
            self.updateControls()
        }
    }
    func loadRuntimeState() {
        processing.perform(work: { [root,state,fixture] in
            let retained=FileManager.default.fileExists(atPath:root.appendingPathComponent("retain-diagnostics").path)
            let values=(try? Data(contentsOf:state.appendingPathComponent("settings.json"))).flatMap { try? JSONDecoder().decode([String:String].self,from:$0) }
            let reference=values?["reference"].map { URL(fileURLWithPath:$0) }
            var copy=CopyWorkflow(); try copy.restoreSession(from:state.appendingPathComponent("copy-session.json"),within:root)
            if let image=copy.image, copy.documentID==nil {
                let migration=try ScanDocumentStore(runtime:root), active=try migration.restore()?.id
                var document=try migration.importImage(image); document.retainedCopies.insert(document.id); try migration.save(document)
                copy.retain(migration.master(document.id),document:document.id)
                try copy.saveSession(to:state.appendingPathComponent("copy-session.json")); try migration.activate(active)
            }
            let tracker=try PrintJobTracker(file:state.appendingPathComponent("print-job.json"),queue:NativePrintQueue(queryHelper:Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/bjc85-job-query")))
            return (retained,reference,copy,tracker,fixture ? SharedDeviceState.State.available : SharedDeviceState.inspect(root))
        }) { [weak self] result in
            guard let self else { return }
            do {
                let (retained,reference,copy,tracker,safety)=try result.get()
                self.model.retainDiagnosticCaptures=retained; self.reference=reference; self.model.copy=copy; self.tracker=tracker; self.latestJob=tracker.record
                self.lastAvailability=safety
                if safety == .recoveryRequired { self.model.coordinator.requireRecovery() }
                self.layout.status.stringValue=self.fixture ? "Fixture mode · Synthetic content · USB and production services disabled" : self.document == nil ? "Open an image or connect the IS-12 to begin." : "Document restored. No physical operation resumed."
                if !self.fixture && safety == .busy { self.layout.status.stringValue="Another client currently owns the device. Documents remain available; retry connection after that job finishes." }
                if tracker.record?.outstanding == true { self.recheckJob() }
            } catch { self.savingError=error.localizedDescription; self.report(error) }
            self.updateControls()
        }
    }
    func report(_ error: Error) { layout.status.stringValue=error.localizedDescription; updateControls() }
    func selectWorkspace(_ row: Int) {
        guard panels.indices.contains(row) else { return }
        layout.showInspector(panels[row])
        if row == 2, let id=model.copy.documentID, id != document?.id { reopenDocument(id) }
    }
    func updateControls() {
        let recovery=model.coordinator.state == .recoveryRequired
        layout.device.show(model.coordinator.state)
        if lastAvailability == .busy && !busy && !recovery { layout.device.stringValue="Last check: device in use by another client" }
        if fixture { layout.device.stringValue="Fixture · \(layout.device.stringValue)" }
        layout.device.setAccessibilityValue(layout.device.stringValue)
        connect.isEnabled = !busy && !recovery && !fixture
        let canScan = model.coordinator.state == .scannerReady && !busy && !documentBusy && !recovery && !fixture && model.scan.unavailableReason == nil
        scan.isEnabled=canScan; prescan.isEnabled=canScan
        calibrate.isEnabled = !busy && !fixture && [.scannerReady,.scannerNeedsCalibration].contains(model.coordinator.state)
        layout.cancel.isHidden = scanController?.active == nil && latestJob?.result != .pending
        layout.cancel.title = latestJob?.result == .pending ? "Cancel print job" : "Cancel acquisition"
        layout.cancelExport.isHidden = exportTicket == nil
        printButton.isEnabled = document != nil && !busy && !documentBusy && !recovery && printSettings.settings.isValid && latestJob?.outstanding != true && !fixture
        swap.isEnabled = !busy && !recovery && !fixture
        copyControls.copy.isEnabled = canScan && model.copy.stage == .empty && copyControls.settings.settings.isValid
        copyControls.reprint.title = model.copy.stage == .reprintReady ? "Reprint retained copy" : "Print retained copy"
        copyControls.reprint.isEnabled = model.copy.canPrint(settings:copyControls.settings.settings,device:model.coordinator.state,busy:busy || documentBusy) && latestJob?.outstanding != true && !fixture
        copyControls.swap.isEnabled = !busy && !fixture && !recovery && [.awaitingPrintCartridge,.readyToPrint,.reprintReady].contains(model.copy.stage)
        copyControls.reset.isEnabled = !busy && !documentBusy && !recovery && ![.empty,.scanning,.printing,.jobUnknown,.recoveryRequired].contains(model.copy.stage)
        copyControls.brightness.isHidden=true
        copyControls.edit.isEnabled=canPerform(#selector(editCopy))
        for button in actionButtons { button.isEnabled=canPerform(button.action) }
        copyControls.information.stringValue = copyInformation()
        for view in [printSettings,copyControls.settings] { view.validate() }
        referenceLabel.stringValue = reference == nil ? "No saved white reference" : referenceValid == true ? "Plain-paper reference · validated at last connection" : "Saved reference · connect to validate"
        jobLabel.stringValue = latestJob.map { "\($0.destination)\($0.jobID.map { "-\($0)" } ?? "")\n\($0.result.label)\n\($0.reasons.joined(separator:", "))" } ?? "No print job submitted"
        if recovery { layout.status.stringValue="Recovery required. Keep the previous capture and inspect the printer. New physical jobs are blocked." }
        if busy || documentBusy || exportTicket != nil || processingCount>0 { layout.progress.startAnimation(nil) } else { layout.progress.stopAnimation(nil) }
        if let document {
            layout.documentTitle.stringValue = "\(document.acquisition.source) · revision \(document.revision)\(document.needsExport ? " · not exported" : " · exported")"
            let swapped=document.edits.rotation%2 != 0
            let w=Double(swapped ? document.acquisition.height : document.acquisition.width)/document.acquisition.dpi
            let h=Double(swapped ? document.acquisition.width : document.acquisition.height)/document.acquisition.dpi
            layout.canvas.physicalSize=NSSize(width:w,height:h)
            layout.dimensions.stringValue=LF("Selection %.2f × %.2f in · %.0f dpi · %d exports",w*document.edits.region.width,h*document.edits.region.height,document.acquisition.dpi,document.exports.count)
        } else { layout.documentTitle.stringValue="No document"; layout.dimensions.stringValue="Open an image without connecting the scanner." }
        window?.isDocumentEdited = document?.needsExport == true
        window?.toolbar?.validateVisibleItems()
    }
    func copyInformation() -> String {
        switch model.copy.stage {
        case .empty: return "1. Acquire original\nLoad one sheet with the IS-12 installed."
        case .scanning: return "1. Acquiring original\nThe previous document stays retained."
        case .awaitingPrintCartridge: return "2. Review retained image\nEdit in Scan, then confirm the BC-11e cartridge change."
        case .readyToPrint: return "3. Ready to print retained copy\nReview settings, then choose Print retained copy."
        case .printing: return "4. Job submitted\nFollow its queue status above."
        case .reprintReady: return "4. Queue reports completed\nInspect the paper. Reprint uses this retained image."
        case .jobUnknown: return "Job outcome unknown\nRecheck the queue. The image is retained; no automatic retry."
        case .recoveryRequired: return "Recovery required\nThe retained image is protected. Inspect the device and operation evidence."
        }
    }
}
