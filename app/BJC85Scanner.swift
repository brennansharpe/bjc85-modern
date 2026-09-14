import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin

// Development application: the protocol process and all dependencies are native.
// One process owns USB at a time; partial captures remain available after failure.
@main
@MainActor
final class ScannerApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let preview = ScanWorkspaceView()
    private var model = AppModel()
    private let deviceStatus = DeviceStatusView()
    private let preset = NSPopUpButton()
    private let prescan = NSButton(title: L("Prescan"), target: nil, action: nil)
    private let clearSelection = NSButton(title: L("Clear Selection"), target: nil, action: nil)
    private let selectionInfo = RootView.label(LF("%.2f × %.2f in",8.0,10.8))
    private let presetNote = RootView.label("")
    private let brightness = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    private let contrast = NSSlider(value: 1, minValue: 0, maxValue: 2, target: nil, action: nil)
    private let threshold = NSSlider(value: 128, minValue: 0, maxValue: 255, target: nil, action: nil)
    private let filter = NSPopUpButton()
    private let invert = NSButton(checkboxWithTitle: L("Invert"), target: nil, action: nil)
    private let printSettings = PrintSettingsView()
    private let copyControls = CopyWorkflowView()
    private var lastOutcome: OperationOutcome?
    private var lastScanOutcome: OperationOutcome?
    private var isPrescan = false
    private var hasPrescan = false
    private var lastRotation = true
    private var operationLog: URL?
    private var externalPreview=false
    private var pendingPrint=false
    private var printJobID: String?
    private let previewQueue = DispatchQueue(label: "local.bjc85.live-preview", qos: .userInitiated)
    private var livePreview: LiveScanPreview?
    private var liveSize = (width: 0, height: 0, rows: 0)
    private var previewRevision = 0
    private var previewUnavailable = false
    private var cancelling = false
    private let status = NSTextField(wrappingLabelWithString: L("Connect the BJC-85 with the IS-12 installed."))
    private let referenceStatus = NSTextField(wrappingLabelWithString: L("No white reference saved."))
    private let resolution = NSPopUpButton()
    private let mode = NSPopUpButton()
    private let rotate = NSButton(checkboxWithTitle: L("Sheet was fed bottom first"), target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private let connect = NSButton(title: L("Connect scanner"), target: nil, action: nil)
    private let calibrate = NSButton(title: L("Calibrate white sheet"), target: nil, action: nil)
    private let scan = NSButton(title: L("Scan page"), target: nil, action: nil)
    private let cancel = NSButton(title: L("Cancel"), target: nil, action: nil)
    private let save = NSButton(title: L("Save image…"), target: nil, action: nil)
    private let files = NSButton(title: L("Show files"), target: nil, action: nil)
    private var process: Process?
    private var outputPipe: Pipe?
    private var logHandle: FileHandle?
    private var pending = Data()
    private var tail = ""
    private var busy = false
    private var connected = false
    private var quitting = false
    private var operation = ""
    private var operationDirectory: URL?
    private var latestScan: URL?
    private var latestDPI = 90
    private var requestedDPI = 90
    private var requestedMode = "color"
    private var reference: URL?
    private var referenceValid: Bool?
    private var savePanel: NSSavePanel?
    private var root: URL!
    private var state: URL!
    private var helper: URL!

    static func main() {
        let app = NSApplication.shared
        let delegate = ScannerApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = ProcessInfo.processInfo.environment["BJC85_RUNTIME_DIRECTORY"].map { URL(fileURLWithPath: $0) }
            ?? support.appendingPathComponent("local.bjc85.utility", isDirectory: true)
        state = root.appendingPathComponent(".state/scanner-app", isDirectory: true)
        model.retainDiagnosticCaptures = FileManager.default.fileExists(atPath:root.appendingPathComponent("retain-diagnostics").path)
        if SharedDeviceState.inspect(root) == .recoveryRequired {
            model.coordinator.requireRecovery()
        }
        helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/bjc85-is12")
        do {
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            if let data = try? Data(contentsOf: state.appendingPathComponent("settings.json")),
               let settings = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let path = settings["reference"], FileManager.default.fileExists(atPath: path) {
                reference = URL(fileURLWithPath: path)
            }
            try model.copy.restoreSession(from:state.appendingPathComponent("copy-session.json"),within:state)
            if model.copy.image != nil { copyControls.information.stringValue=L("Saved copy image restored. Confirm the print cartridge before printing or reprinting.") }
        } catch { status.stringValue = LF("Cannot create the scanner's output folder: %@",error.localizedDescription) }
        makeWindow()
        updateControls()
        // Offline display mode does not open USB, pause queues, or feed paper.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--preview"), index + 1 < arguments.count {
            externalPreview=true
            let url = URL(fileURLWithPath: arguments[index + 1])
            preview.image = NSImage(contentsOf: url)
            latestDPI = Int((try? ScanExport.dpi(of: url))?.rounded() ?? 90)
            status.stringValue = LF("Saved scan · %d dpi",latestDPI)
            rotate.state = url.lastPathComponent == "scan-upright.png" ? .on : .off
            latestScan = url.deletingLastPathComponent()
            if url.lastPathComponent != "scan-upright.png" && url.lastPathComponent != "scan-raw.png" {
                latestScan = nil
            }
            updateControls()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() {
        let menu = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("Quit BJC-85 Utility"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; menu.addItem(item); NSApp.mainMenu = menu
        let deviceItem = NSMenuItem(title: L("Device"), action: nil, keyEquivalent: "")
        let deviceMenu = NSMenu(title: L("Device"))
        deviceMenu.addItem(withTitle: L("Open Image Capture"), action: #selector(openImageCapture), keyEquivalent: "")
        deviceMenu.addItem(withTitle: L("Switch to printing…"), action: #selector(preparePrinting), keyEquivalent: "")
        deviceItem.submenu = deviceMenu; menu.addItem(deviceItem)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 860),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = L("BJC-85 Utility")
        window.minSize = NSSize(width: 920, height: 700)
        window.center()
        let title = NSTextField(labelWithString: L("Canon IS-12"))
        title.font = .systemFont(ofSize: 25, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: L("Native scanning for your BJC-85"))
        subtitle.textColor = .secondaryLabelColor
        let help = NSTextField(wrappingLabelWithString: L("Install the IS-12 before connecting. Load one sheet for each scan. Connecting pauses the BJC-85 print queue."))
        help.font = .systemFont(ofSize: 12)
        resolution.addItems(withTitles: ScanSettings.resolutions.map { LF("%d dpi",$0) }); resolution.selectItem(at: 4)
        resolution.setAccessibilityLabel(L("Scan resolution"))
        mode.addItems(withTitles: ScanImageType.allCases.map(\.label))
        mode.setAccessibilityLabel(L("Scan mode"))
        rotate.state = .on
        rotate.target = self; rotate.action = #selector(rotationChanged)
        connect.target = self; connect.action = #selector(connectScanner)
        calibrate.target = self; calibrate.action = #selector(calibrateSheet)
        scan.target = self; scan.action = #selector(scanPage)
        scan.keyEquivalent = "\r"
        cancel.target = self; cancel.action = #selector(cancelOperation)
        save.target = self; save.action = #selector(saveImage)
        files.target = self; files.action = #selector(showFiles)
        referenceStatus.font = .systemFont(ofSize: 12)
        referenceStatus.textColor = .secondaryLabelColor
        let calibrationHelp = NSTextField(wrappingLabelWithString: L("Use a clean white sheet for calibration. This corrects uneven shading; colour accuracy with ordinary paper is unverified."))
        calibrationHelp.font = .systemFont(ofSize: 12)
        calibrationHelp.textColor = .secondaryLabelColor
        progress.style = .bar; progress.isIndeterminate = true
        progress.isDisplayedWhenStopped = false
        preset.addItems(withTitles: CanonPreset.all.map(\.name) + [L("Custom")]); preset.selectItem(at: 1)
        preset.target = self; preset.action = #selector(presetChanged)
        preset.setAccessibilityLabel(L("Canon scan preset"))
        mode.target = self; mode.action = #selector(settingsChanged)
        resolution.target = self; resolution.action = #selector(settingsChanged)
        presetNote.stringValue = CanonPreset.all[1].qualificationNote
        for (slider, label) in [(brightness, L("Brightness")), (contrast, L("Contrast")), (threshold, L("Black and white threshold"))] {
            slider.target = self; slider.action = #selector(adjustmentsChanged); slider.isContinuous = false
            slider.setAccessibilityLabel(label)
        }
        filter.addItems(withTitles: [L("None"), L("Sharpen"), L("Soften"), L("Despeckle")])
        filter.target = self; filter.action = #selector(adjustmentsChanged); filter.setAccessibilityLabel(L("Image filter"))
        invert.target = self; invert.action = #selector(adjustmentsChanged)
        prescan.target = self; prescan.action = #selector(prescanPage)
        clearSelection.target = self; clearSelection.action = #selector(clearCrop)
        preview.changed = { [weak self] region in
            guard let self else { return }; self.model.region = region
            self.selectionInfo.stringValue = LF("Selection %.2f × %.2f in · x %.2f, y %.2f",region.width*8,region.height*10.8,region.x*8,region.y*10.8)
        }
        let controls = RootView.column([title, subtitle, deviceStatus, connect, preset, presetNote, mode, resolution,
            RootView.label(L("Brightness")), brightness, RootView.label(L("Contrast")), contrast,
            RootView.label(L("B&W threshold")), threshold, filter, invert, rotate,
            NSStackView(views: [prescan, scan, cancel]), selectionInfo, clearSelection,
            referenceStatus, calibrate, progress, status, NSStackView(views:[save,files])], spacing: 8)
        controls.widthAnchor.constraint(equalToConstant: 290).isActive = true
        let scroll=NSScrollView(); scroll.hasVerticalScroller=true; scroll.drawsBackground=false
        scroll.documentView=controls; controls.translatesAutoresizingMaskIntoConstraints=false
        controls.leadingAnchor.constraint(equalTo:scroll.contentView.leadingAnchor).isActive=true
        controls.topAnchor.constraint(equalTo:scroll.contentView.topAnchor).isActive=true
        scroll.widthAnchor.constraint(equalToConstant: 308).isActive=true
        let scanBody=NSStackView(views:[scroll,preview]); scanBody.orientation = .horizontal; scanBody.spacing=18
        let tabs=NSTabView(); tabs.translatesAutoresizingMaskIntoConstraints=false
        let scanTab=NSTabViewItem(identifier:"scan"); scanTab.label=L("Scan"); scanTab.view=scanBody; tabs.addTabViewItem(scanTab)
        let printButton=NSButton(title:L("Print retained scan…"),target:self,action:#selector(printRetainedScan))
        let switchButton=NSButton(title:L("Switch to printing…"),target:self,action:#selector(preparePrinting))
        let jobs=NSButton(title:L("Open print jobs"),target:self,action:#selector(openJobs))
        let printBody=RootView.column([RootView.label(L("Print settings")),printSettings,printButton,switchButton,jobs,
            RootView.label(L("Advanced Canon cartridge, media, colour, halftone and maintenance options are unavailable until mapped and qualified."))])
        let printTab=NSTabViewItem(identifier:"print"); printTab.label=L("Print"); printTab.view=printBody; tabs.addTabViewItem(printTab)
        copyControls.copy.target=self; copyControls.copy.action=#selector(copyOriginal)
        copyControls.reprint.target=self; copyControls.reprint.action=#selector(reprintCopy)
        copyControls.reset.target=self; copyControls.reset.action=#selector(resetCopy)
        copyControls.swap.target=self; copyControls.swap.action=#selector(preparePrinting)
        let copyTab=NSTabViewItem(identifier:"copy"); copyTab.label=L("Copy"); copyTab.view=copyControls; tabs.addTabViewItem(copyTab)
        let utilityButton=NSButton(title:L("Maintenance information…"),target:self,action:#selector(showMaintenance))
        let privacyButton=NSButton(title:L("Privacy and diagnostic data…"),target:self,action:#selector(showSettings))
        let importButton=NSButton(title:L("Import existing white reference…"),target:self,action:#selector(importReference))
        let toolsTab=NSTabViewItem(identifier:"tools"); toolsTab.label=L("Device & Settings")
        toolsTab.view=RootView.column([utilityButton,privacyButton,importButton,RootView.label(L("No Canon executables or artwork are used by this native application."))]); tabs.addTabViewItem(toolsTab)
        window.contentView!.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:20),
            tabs.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-20),
            tabs.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:16),
            tabs.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor,constant:-16),
            preview.widthAnchor.constraint(greaterThanOrEqualToConstant:440),
            scroll.heightAnchor.constraint(equalTo:scanBody.heightAnchor),
            preview.heightAnchor.constraint(equalTo:scanBody.heightAnchor)
        ])
        let fileItem=NSMenuItem(title:L("File"),action:nil,keyEquivalent:""); let fileMenu=NSMenu(title:L("File"))
        fileMenu.addItem(withTitle:L("Save scan…"),action:#selector(saveImage),keyEquivalent:"s")
        fileMenu.addItem(withTitle:L("Print scan…"),action:#selector(printRetainedScan),keyEquivalent:"p")
        fileMenu.addItem(withTitle:L("Cancel / Halt"),action:#selector(cancelOperation),keyEquivalent:".")
        fileItem.submenu=fileMenu; menu.addItem(fileItem)
        appMenu.insertItem(withTitle:L("Settings…"),action:#selector(showSettings),keyEquivalent:",",at:0)
        let viewItem=NSMenuItem(title:L("View"),action:nil,keyEquivalent:""); let viewMenu=NSMenu(title:L("View"))
        viewMenu.addItem(withTitle:L("Zoom in"),action:#selector(zoomIn),keyEquivalent:"+")
        viewMenu.addItem(withTitle:L("Zoom out"),action:#selector(zoomOut),keyEquivalent:"-")
        viewMenu.addItem(withTitle:L("Crop dimensions…"),action:#selector(cropDimensions),keyEquivalent:"")
        viewItem.submenu=viewMenu; menu.addItem(viewItem)
        let helpItem=NSMenuItem(title:L("Help"),action:nil,keyEquivalent:""); let helpMenu=NSMenu(title:L("Help"))
        helpMenu.addItem(withTitle:L("BJC-85 Help"),action:#selector(showHelp),keyEquivalent:"?")
        helpItem.submenu=helpMenu; menu.addItem(helpItem)
    }

    private func space(_ height: CGFloat) -> NSView {
        let view = NSView(); view.heightAnchor.constraint(equalToConstant: height).isActive = true; return view
    }

    private func updateControls() {
        let recover = model.coordinator.state == .recoveryRequired
        deviceStatus.show(model.coordinator.state)
        connect.isEnabled = !busy && !recover
        calibrate.isEnabled = connected && !busy && !recover
        scan.isEnabled = connected && referenceValid == true && !busy && !recover && model.scan.unavailableReason == nil
        prescan.isEnabled = scan.isEnabled
        cancel.isEnabled = busy && (process != nil || printJobID != nil)
        for control in [resolution,mode,preset] { control.isEnabled = !busy }
        threshold.isEnabled = model.scan.imageType == .blackAndWhite && !busy
        for slider in [brightness,contrast] { slider.isEnabled = !busy }
        save.isEnabled = latestScan != nil && !busy
        files.isEnabled = !busy
        copyControls.copy.isEnabled = scan.isEnabled && model.copy.stage == .empty
        copyControls.reprint.isEnabled = !busy && model.copy.stage == .reprintReady && !recover
        copyControls.reset.isEnabled = !busy && !recover && ![.scanning,.printing,.recoveryRequired].contains(model.copy.stage)
        copyControls.swap.isEnabled = !busy && model.copy.stage == .awaitingPrintCartridge && !recover
        copyControls.brightness.isEnabled = !busy && model.copy.stage == .empty
        for control in [printSettings.paper,printSettings.colour,printSettings.copies,printSettings.quality,
                        copyControls.settings.paper,copyControls.settings.colour,copyControls.settings.copies,copyControls.settings.quality] {
            control.isEnabled = !busy
        }
        referenceStatus.stringValue = reference == nil ? L("No white reference saved.") :
            referenceValid == true ? L("Plain-paper reference · serial, head and temperature passed") :
            referenceValid == false ? L("Reference invalid for current device or temperature · recalibrate") : L("Saved reference · connect to validate")
        if recover { status.stringValue = L("Recovery required. Inspect the previous operation and printer. New device operations are blocked.") }
        if busy { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
    }

    // Run short system checks off the UI thread. No shell interpolation is used.
    nonisolated private static func command(_ path: String, _ arguments: [String]) throws -> (Int32, String) {
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: path); task.arguments = arguments
        task.standardOutput = pipe; task.standardError = pipe
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    @objc private func connectScanner() {
        guard !busy, model.coordinator.state != .recoveryRequired else { return }
        busy=true; connected=false; referenceValid=nil; status.stringValue=L("Preparing scanner connection…"); updateControls()
        let bundle=Bundle.main.bundleURL, runtime=root!, savedReference=reference ?? state.appendingPathComponent("missing-reference.bin")
        DispatchQueue.global(qos:.userInitiated).async {
            var failure: String?
            do { try ServiceController.prepareScanner(bundle:bundle,runtime:runtime,reference:savedReference) }
            catch { failure=error.localizedDescription }
            let message=failure
            DispatchQueue.main.async {
                self.busy=false
                if let message { self.status.stringValue=message; self.updateControls() }
                else { self.start("connect",arguments:["status","--scanner-installed","--enter-scanner-mode","--reference",savedReference.path],directory:nil) }
            }
        }
    }
    @objc private func calibrateSheet() {
        guard connected && !busy else { return }
        CalibrationView.sheet(reference:reference,valid:referenceValid).beginSheetModal(for:window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let directory=self.state.appendingPathComponent("reference-\(UUID().uuidString)",isDirectory:true)
            self.beginAcquisition(calibration:true,directory:directory,arguments:["calibrate","--scanner-installed","--plain-paper-reference",directory.path])
        }
    }
    private func beginAcquisition(calibration: Bool,directory: URL,arguments: [String]) {
        guard !busy, model.coordinator.requestScan(calibration:calibration) else { updateControls(); return }
        busy=true; updateControls()
        DispatchQueue.global(qos:.userInitiated).async {
            var failure: String?
            do { try ServiceController.quiesceScanner() } catch { failure=error.localizedDescription }
            let message=failure
            DispatchQueue.main.async {
                self.busy=false
                if let message { self.model.coordinator.disconnected(); self.connected=false; self.status.stringValue=message; self.updateControls() }
                else { self.start(calibration ? "calibrate" : "scan",arguments:arguments,directory:directory) }
            }
        }
    }
    @objc private func scanPage() {
        isPrescan=false
        if hasPrescan {
            let alert=NSAlert(); alert.messageText=L("Reload the original"); alert.informativeText=L("Prescan ejected the sheet. Reload the same original in the same orientation, then scan at the selected resolution. The saved image will use your selected region.")
            alert.addButton(withTitle:L("Original reloaded — scan")); alert.addButton(withTitle:L("Cancel"))
            alert.beginSheetModal(for:window) { if $0 == .alertFirstButtonReturn { self.acquirePage() } }
        } else { acquirePage() }
    }
    @objc private func prescanPage() { isPrescan=true; acquirePage() }
    private func acquirePage() {
        guard connected && !busy, let reference, model.scan.unavailableReason == nil else { return }
        requestedDPI=isPrescan ? 90 : model.scan.dpi
        requestedMode=(isPrescan ? model.scan.previewType : model.scan.imageType).helperMode
        let directory=state.appendingPathComponent("scan-\(UUID().uuidString)",isDirectory:true)
        beginAcquisition(calibration:false,directory:directory,arguments:["scan","--scanner-installed","--calibration",reference.path,
            "--dpi",String(requestedDPI),"--mode",requestedMode,"--live-preview",directory.path])
    }

    private func start(_ kind: String, arguments: [String], directory: URL?) {
        guard !busy else { return }
        operation = kind; operationDirectory = directory
        cancelling = false; lastOutcome = nil
        if kind == "scan", let directory {
            externalPreview=false
            latestScan = nil; preview.image = nil
            livePreview = LiveScanPreview(directory: directory)
            liveSize = (0, 0, 0); previewUnavailable = false; previewRevision += 1
        }
        pending.removeAll(); tail = ""; busy = true
        status.stringValue = kind == "calibrate" ? L("Measuring the blank white sheet…") : kind == "scan" ? L("Starting scan…") : L("Checking IS-12…")
        progress.isIndeterminate = true
        progress.doubleValue = 0
        let log = state.appendingPathComponent("\(kind)-\(UUID().uuidString).jsonl")
        operationLog = log
        let task = Process(), pipe = Pipe()
        do {
            guard FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw NSError(domain: "BJC85", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Cannot create operation log.")])
            }
            logHandle = try FileHandle(forWritingTo: log)
            task.executableURL = helper; task.arguments = arguments; task.currentDirectoryURL = root
            var environment=ProcessInfo.processInfo.environment
            environment["BJC85_STATE_DIRECTORY"]=root.path; environment["BJC85_RUNTIME_DIRECTORY"]=root.path
            task.environment=environment
            task.standardOutput = pipe; task.standardError = pipe
            process = task; outputPipe = pipe
            // A single background reader preserves byte ordering and drains through EOF.
            // Completion runs only after the final JSON record and trailing errors arrive.
            try task.run()
            DispatchQueue.global(qos: .userInitiated).async {
                while true {
                    let data = pipe.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    DispatchQueue.main.async { self.receive(data) }
                }
                task.waitUntilExit()
                let code = task.terminationStatus
                DispatchQueue.main.async { self.finished(code) }
            }
        } catch {
            busy = false; process = nil; outputPipe = nil
            lastOutcome = .preflightFailedSafe
            if kind == "scan" || kind == "calibrate" {
                model.coordinator.finish(lastOutcome,hasReference:referenceValid == true)
                model.copy.scanStopped(safely:true)
            }
            connected=false
            try? logHandle?.close(); logHandle = nil
            status.stringValue = LF("Could not start: %@",error.localizedDescription)
        }
        updateControls()
    }

    private func receive(_ data: Data) {
        do { try logHandle?.write(contentsOf: data) }
        catch { status.stringValue = L("Cannot save operation log; stopping."); process?.interrupt() }
        pending.append(data)
        while let end = pending.firstIndex(of: 10) {
            let line = pending.prefix(upTo: end)
            pending.removeSubrange(...end)
            if let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                let event = record["event"] as? String
                if event == "readiness", let readiness=try? JSONDecoder().decode(ScannerReadiness.self,from:Data(line)) {
                    referenceValid=readiness.reference_valid
                    model.coordinator.observe(readiness,hasReference:referenceValid == true); connected=readiness.canScan
                }
                if event == "operation_outcome", let value=record["outcome"] as? String { lastOutcome=OperationOutcome(rawValue:value) }
                if event == "scan_preview", operation == "scan", !cancelling,
                   let width = record["width"] as? Int, let height = record["height"] as? Int,
                   let rows = record["rows"] as? Int, width > 0, width <= 750,
                   height > 0, height <= 1250, rows > 0, rows <= height {
                    liveSize = (width, height, rows)
                    let percentage = min(99, rows * 100 / height)
                    progress.isIndeterminate = false; progress.doubleValue = Double(percentage)
                    status.stringValue = rows == height ? L("Finishing scan…") : LF("Scanning at %d dpi · %d%%",requestedDPI,percentage)
                    refreshLivePreview()
                }
                if event == "scan_preview_unavailable" { previewUnavailable = true }
                if event == "scan_progress", let count = record["image_bytes"] as? Int, operation == "scan",
                   !cancelling, liveSize.rows == 0 || previewUnavailable {
                    let bytesPerPixel = requestedMode == "color" ? 3.0 : 1.0
                    let expected = Double(requestedDPI * 8) * Double(requestedDPI) * 10.8 * bytesPerPixel
                    let percentage = min(99, Int(Double(count) / expected * 100))
                    progress.isIndeterminate = false; progress.doubleValue = Double(percentage)
                    status.stringValue = LF("Scanning at %d dpi · %d%%",requestedDPI,percentage)
                }
            } else {
                let text = String(decoding: line, as: UTF8.self)
                if !text.isEmpty { tail = String((tail + text + "\n").suffix(1400)) }
            }
        }
    }

    private func finished(_ code: Int32) {
        var outputFailure: String?
        process = nil; outputPipe = nil; busy = false
        try? logHandle?.synchronize(); try? logHandle?.close(); logHandle = nil
        if let log=operationLog, let directory=operationDirectory, operation == "scan" {
            try? FileManager.default.moveItem(at:log,to:directory.appendingPathComponent("driver.jsonl"))
        }
        if lastOutcome == nil || lastOutcome == .recoveryRequired { model.coordinator.requireRecovery(); connected=false }
        if operation == "scan" || operation == "calibrate" { model.coordinator.finish(lastOutcome,hasReference:reference != nil); connected=false }
        if code == 0 && lastOutcome == .completedSafe {
            if operation == "scan", let directory = operationDirectory {
                livePreview = nil; previewRevision += 1
                latestDPI = requestedDPI
                latestScan = directory; lastScanOutcome=lastOutcome; hasPrescan=isPrescan; refreshPreview()
                if model.copy.stage == .scanning {
                    do {
                        let copyDirectory=state.appendingPathComponent("copy-\(UUID().uuidString)")
                        try FileManager.default.createDirectory(at:copyDirectory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
                        let source=try processedSource(); let retained=copyDirectory.appendingPathComponent("copy.pdf")
                        try ScanExport.write(source:source,destination:retained); model.copy.retain(retained)
                        try model.copy.saveSession(to:state.appendingPathComponent("copy-session.json"))
                        try PrivacyRetention.removeExportedCapture(directory,retainDiagnostics:model.retainDiagnosticCaptures,outcome:lastScanOutcome)
                        if !model.retainDiagnosticCaptures { latestScan=nil }
                        copyControls.information.stringValue=L("Image retained. Replace the IS-12 with BC-11e, then choose Switch to printing. Reprint uses this same image.")
                    } catch { model.copy.scanStopped(safely:true); outputFailure=error.localizedDescription }
                }
                status.stringValue = LF("Scan complete · %d dpi · white-paper correction",latestDPI)
            } else if operation == "calibrate", let directory = operationDirectory {
                reference = directory.appendingPathComponent("reference.bin")
                if let data = try? JSONSerialization.data(withJSONObject: ["reference": reference!.path], options: .prettyPrinted) {
                    try? data.write(to: state.appendingPathComponent("settings.json"), options: .atomic)
                }
                status.stringValue = L("White reference saved. Load your document, then choose Scan page.")
            } else {
                status.stringValue = connected ? L("IS-12 connected. Ready to scan.") : L("Connected device did not pass the IS-12 check.")
            }
        } else {
            connected = false
            model.copy.scanStopped(safely:lastOutcome?.permitsNextOperation == true)
            status.stringValue = cancelling ? L("Scan cancelled. The preview is partial; captured data is retained in Show files. Reconnect before scanning.") :
                tail.isEmpty ? L("Operation stopped. Captured data is retained in Show files. Reconnect before trying again.") : tail
        }
        if let outputFailure { status.stringValue=outputFailure }
        updateControls()
        if quitting { NSApp.reply(toApplicationShouldTerminate: true) }
        else if ["scan","calibrate"].contains(operation), lastOutcome?.permitsNextOperation == true {
            DispatchQueue.main.async { self.connectScanner() }
        }
    }

    @objc private func cancelOperation() {
        if let printJobID {
            model.coordinator.cancel(); status.stringValue=L("Cancelling print job…")
            DispatchQueue.global().async { _=try? ServiceController.command("/usr/bin/cancel",[printJobID]) }
            return
        }
        cancelling = true; model.coordinator.cancel(); previewRevision += 1
        process?.interrupt()
        cancel.isEnabled = false
        status.stringValue = L("Stopping and retaining the captured data…")
    }

    @objc private func refreshPreview() {
        if livePreview != nil { refreshLivePreview(); return }
        guard let directory=latestScan else { return }
        let source=directory.appendingPathComponent(rotate.state == .on ? "scan-upright.png" : "scan-raw.png")
        let adjustments=model.adjustments, bw=model.scan.imageType == .blackAndWhite, value=model.scan.threshold
        previewRevision += 1; let revision=previewRevision
        previewQueue.async {
            guard let input=CGImageSourceCreateWithURL(source as CFURL,nil), let original=CGImageSourceCreateImageAtIndex(input,0,nil),
                  let image=try? ScanProcessing.render(source:original,region:.fullPage,adjustments:adjustments,blackAndWhite:bw,threshold:value) else { return }
            DispatchQueue.main.async { guard revision == self.previewRevision else { return }; self.preview.image=NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height)) }
        }
    }

    private func refreshLivePreview() {
        guard let model = livePreview, liveSize.rows > 0, !previewUnavailable else { return }
        let size = liveSize, rotated = rotate.state == .on
        previewRevision += 1
        let revision = previewRevision
        previewQueue.async {
            let image = try? model.update(width: size.width, height: size.height, rows: size.rows, rotate180: rotated)
            DispatchQueue.main.async {
                // A cancelled/finished job or newer rotation must win over a late frame.
                guard self.livePreview === model, self.previewRevision == revision else { return }
                if let image {
                    self.preview.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                } else {
                    self.previewUnavailable = true
                }
            }
        }
    }

    @objc private func showFiles() { NSWorkspace.shared.open(latestScan ?? livePreview?.directory ?? state) }

    @objc private func openImageCapture() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Image Capture.app"))
    }

    @objc private func preparePrinting() {
        guard !busy, model.coordinator.state != .recoveryRequired else { return }
        if model.coordinator.state == .printerReady { return }
        _=model.coordinator.requestPrint(); updateControls()
        CartridgeSwapView.sheet().beginSheetModal(for:window) { response in
            guard response == .alertFirstButtonReturn else { self.pendingPrint=false; return }
            self.busy=true; self.updateControls()
            let bundle=Bundle.main.bundleURL, runtime=self.root!
            DispatchQueue.global(qos:.userInitiated).async {
                var failure: String?
                do { try ServiceController.preparePrinter(bundle:bundle,runtime:runtime) } catch { failure=error.localizedDescription }
                let message=failure
                DispatchQueue.main.async {
                    self.busy=false; self.connected=false
                    if let message { self.status.stringValue=message }
                    else {
                        _=self.model.coordinator.confirmPrintCartridge(servicePrepared:true)
                        if self.model.copy.printerConfirmed() { self.reprintCopy() }
                        else if self.pendingPrint { self.pendingPrint=false; self.printRetainedScan() }
                        self.status.stringValue=L("Printing enabled. Choose Canon BJC-85 Native in the Print dialog.")
                    }
                    self.updateControls()
                }
            }
        }
    }
    private func processedSource() throws -> URL {
        guard let directory=latestScan else { throw CocoaError(.fileNoSuchFile) }
        let source=directory.appendingPathComponent(rotate.state == .on ? "scan-upright.png" : "scan-raw.png")
        guard let input=CGImageSourceCreateWithURL(source as CFURL,nil), let original=CGImageSourceCreateImageAtIndex(input,0,nil) else { throw CocoaError(.fileReadCorruptFile) }
        let image=try ScanProcessing.render(source:original,region:model.region,adjustments:model.adjustments,blackAndWhite:model.scan.imageType == .blackAndWhite,threshold:model.scan.threshold)
        let output=directory.appendingPathComponent("processed.png")
        try ScanProcessing.writePNG(image:image,dpi:Double(latestDPI),destination:output); return output
    }

    @objc private func saveImage() {
        guard let directory = latestScan else { return }
        let panel = NSSavePanel()
        savePanel = panel
        panel.allowedContentTypes = [.png, .tiff, .pdf]
        panel.canCreateDirectories = true; panel.isExtensionHidden = false
        panel.nameFieldStringValue = L("IS-12 scan.png")
        let formats = NSPopUpButton()
        formats.addItems(withTitles: [L("PNG"), L("TIFF"), L("PDF")])
        formats.setAccessibilityLabel(L("Export file format"))
        formats.target = self; formats.action = #selector(saveFormatChanged(_:))
        panel.accessoryView = formats
        panel.beginSheetModal(for: window) { response in
            defer { self.savePanel = nil }
            guard response == .OK, let destination = panel.url else { return }
            do {
                let source=try self.processedSource()
                try ScanExport.write(source: source, destination: destination)
                if !self.externalPreview {
                    try PrivacyRetention.removeExportedCapture(directory,retainDiagnostics:self.model.retainDiagnosticCaptures,outcome:self.lastScanOutcome)
                    if !self.model.retainDiagnosticCaptures { self.latestScan=nil; self.save.isEnabled=false }
                }

                self.status.stringValue = LF("Saved %@",destination.lastPathComponent)
            } catch { self.status.stringValue = LF("Could not save: %@",error.localizedDescription) }
        }
    }

    @objc private func saveFormatChanged(_ sender: NSPopUpButton) {
        guard let panel = savePanel else { return }
        let types: [UTType] = [.png, .tiff, .pdf]
        panel.allowedContentTypes = [types[sender.indexOfSelectedItem]]
        let stem = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.nameFieldStringValue = stem + "." + ["png", "tiff", "pdf"][sender.indexOfSelectedItem]
    }

    @objc private func presetChanged() {
        if preset.indexOfSelectedItem < CanonPreset.all.count {
            let selected=CanonPreset.all[preset.indexOfSelectedItem]; model.choose(selected)
            mode.selectItem(at:ScanImageType.allCases.firstIndex(of:model.scan.imageType)!)
            resolution.selectItem(at:ScanSettings.resolutions.firstIndex(of:model.scan.dpi)!)
            threshold.doubleValue=Double(model.scan.threshold); presetNote.stringValue=selected.qualificationNote
        } else { model.presetID="custom"; presetNote.stringValue=L("Custom scan settings") }
        updateControls(); refreshPreview()
    }
    @objc private func settingsChanged() {
        model.scan.imageType=ScanImageType.allCases[mode.indexOfSelectedItem]
        model.scan.dpi=ScanSettings.resolutions[resolution.indexOfSelectedItem]
        model.presetID="custom"; preset.selectItem(at:CanonPreset.all.count)
        presetNote.stringValue=model.scan.unavailableReason ?? L("Custom scan settings")
        updateControls(); refreshPreview()
    }
    @objc private func adjustmentsChanged() {
        model.adjustments.brightness=brightness.doubleValue; model.adjustments.contrast=contrast.doubleValue
        model.adjustments.filter=ScanFilter.allCases[filter.indexOfSelectedItem]; model.adjustments.invert=invert.state == .on
        model.scan.threshold=Int(threshold.doubleValue.rounded()); refreshPreview()
    }
    @objc private func clearCrop() { preview.region = .fullPage }
    @objc private func rotationChanged() {
        let value=rotate.state == .on
        if value != lastRotation { preview.region=preview.region.rotated180; lastRotation=value }
        refreshPreview()
    }
    @objc private func zoomIn() { preview.zoom=min(3,preview.zoom*1.25) }
    @objc private func zoomOut() { preview.zoom=max(1,preview.zoom/1.25) }
    @objc private func cropDimensions() {
        let alert=NSAlert(); alert.messageText=L("Crop dimensions in inches")
        let values=[model.region.x*8,model.region.y*10.8,model.region.width*8,model.region.height*10.8]
        let formatter=dimensionFormatter()
        let fields=values.map { value -> NSTextField in
            let field=NSTextField(string:formatter.string(from:NSNumber(value:value)) ?? "")
            field.formatter=formatter; return field
        }
        let labels=[L("Left"),L("Top"),L("Width"),L("Height")]
        let form=RootView.column(zip(labels,fields).map { label,field in
            field.setAccessibilityLabel(LF("%@ in inches",label)); field.widthAnchor.constraint(equalToConstant:100).isActive=true
            return NSStackView(views:[RootView.label(label),field])
        })
        form.frame=NSRect(x:0,y:0,width:270,height:140); alert.accessoryView=form
        alert.addButton(withTitle:L("Apply")); alert.addButton(withTitle:L("Cancel"))
        alert.beginSheetModal(for:window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let numbers=fields.compactMap { formatter.number(from:$0.stringValue)?.doubleValue }
            guard numbers.count==4 else { self.status.stringValue=L("Enter four valid dimensions."); return }
            let region=ScanRegion(x:numbers[0]/8,y:numbers[1]/10.8,width:numbers[2]/8,height:numbers[3]/10.8)
            guard region.isValid else { self.status.stringValue=L("Selection must fit within the 8 × 10.8 inch scan area."); return }
            self.preview.region=region
        }
    }
    @objc private func copyOriginal() {
        guard connected, !busy, referenceValid == true, copyControls.settings.settings.isValid,
              model.scan.unavailableReason == nil, model.copy.beginScan() else { return }
        model.scan.imageType=copyControls.settings.settings.colour ? .colour : .blackAndWhite
        model.adjustments.brightness=copyControls.brightness.doubleValue
        mode.selectItem(at:ScanImageType.allCases.firstIndex(of:model.scan.imageType)!)
        brightness.doubleValue=model.adjustments.brightness
        copyControls.information.stringValue=L("Scanning one original. Its completed image will be retained for printing and reprinting.")
        isPrescan=false; acquirePage()
    }
    @objc private func resetCopy() {
        guard !busy, model.coordinator.state != .recoveryRequired,
              ![.scanning,.printing,.recoveryRequired].contains(model.copy.stage) else { return }
        let retained=model.copy.image
        do {
            if let retained { try FileManager.default.removeItem(at:retained.deletingLastPathComponent()) }
            _=model.copy.reset()
            try model.copy.saveSession(to:state.appendingPathComponent("copy-session.json"))
            copyControls.information.stringValue=L("Load one original with the IS-12 installed. Copy will retain its image through the cartridge swap.")
        } catch { status.stringValue=error.localizedDescription }
        updateControls()
    }
    @objc private func reprintCopy() {
        guard !busy, copyControls.settings.settings.isValid, model.coordinator.state == .printerReady, let image=model.copy.beginPrint() else { return }
        submitPrint(image,copy:true)
    }
    @objc private func printRetainedScan() {
        guard !busy, latestScan != nil else { return }
        guard model.coordinator.state == .printerReady else { pendingPrint=true; preparePrinting(); return }
        do {
            let image=try processedSource(), document=image.deletingLastPathComponent().appendingPathComponent("print.pdf")
            try ScanExport.write(source:image,destination:document); submitPrint(document,copy:false)
        } catch { status.stringValue=error.localizedDescription }
    }
    private func submitPrint(_ image: URL,copy: Bool) {
        let settings=copy ? copyControls.settings.settings : printSettings.settings
        guard settings.isValid, model.coordinator.requestPrint() else {
            if copy { model.copy.completed(safely:true) }
            status.stringValue=L("Choose Letter or A4 and 1–999 copies."); updateControls(); return
        }
        busy=true; updateControls()
        DispatchQueue.global(qos:.userInitiated).async {
            let result: ServiceController.Result
            do { result=try ServiceController.command("/usr/bin/lp",settings.arguments(for:image)) }
            catch { result = .init(code:1,output:error.localizedDescription) }
            let id=result.output.split(whereSeparator: { $0.isWhitespace }).map(String.init).first { value in
                value.hasPrefix("BJC85_Native-") && Int(value.dropFirst("BJC85_Native-".count)) != nil
            }
            DispatchQueue.main.async {
                guard result.code==0, let id else {
                    self.busy=false; self.model.coordinator.finish(.preflightFailedSafe,hasReference:self.reference != nil)
                    if copy { self.model.copy.completed(safely:true) }
                    self.status.stringValue=result.output; self.updateControls(); return
                }
                self.printJobID=id; self.cancel.isEnabled=true; self.status.stringValue=LF("Print job submitted · %@",id)
                self.pollPrint(id,copy:copy)
            }
        }
    }
    private func pollPrint(_ id: String,copy: Bool) {
        DispatchQueue.global().asyncAfter(deadline:.now()+1) {
            let result=try? ServiceController.command("/usr/bin/lpstat",["-W","not-completed","-o","BJC85_Native"])
            DispatchQueue.main.async {
                guard self.printJobID==id else { return }
                if result?.code==0 && result!.output.split(separator:"\n").contains(where: { $0.hasPrefix(id+" ") }) {
                    self.pollPrint(id,copy:copy); return
                }
                let shared=SharedDeviceState.inspect(self.root)
                if result?.code==0 && shared == .busy { self.pollPrint(id,copy:copy); return }
                let safe=result?.code==0 && shared == .available
                self.printJobID=nil; self.busy=false
                self.model.coordinator.finish(safe ? .completedSafe : .recoveryRequired,hasReference:self.reference != nil)
                if copy { self.model.copy.completed(safely:safe) }
                self.status.stringValue=safe ? L("Print queue finished the job. Inspect the physical output.") : L("Print outcome needs inspection.")
                self.updateControls()
            }
        }
    }
    @objc private func openJobs() { JobsView.open() }
    @objc private func showMaintenance() { MaintenanceView.panel().beginSheetModal(for:window) }
    @objc private func showHelp() {
        if let url=Bundle.main.url(forResource:"USER-GUIDE",withExtension:"md") { NSWorkspace.shared.open(url) }
    }
    @objc private func showSettings() {
        let alert=NSAlert(); alert.messageText=L("Privacy and diagnostic data")
        alert.informativeText=L("Successful scan captures are removed after export unless you retain diagnostics. A copy session retains its image until Reset. Incomplete or ambiguous operations remain available for inspection.")
        let retain=NSButton(checkboxWithTitle:L("Retain diagnostic captures"),target:nil,action:nil)
        retain.state=model.retainDiagnosticCaptures ? .on : .off; alert.accessoryView=retain
        alert.addButton(withTitle:L("Save")); alert.addButton(withTitle:L("Cancel")); alert.addButton(withTitle:L("Delete Diagnostic Data…"))
        alert.beginSheetModal(for:window) { response in
            if response == .alertFirstButtonReturn {
                let flag=self.root.appendingPathComponent("retain-diagnostics")
                do {
                    if retain.state == .on {
                        try Data().write(to:flag,options:.atomic)
                        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:flag.path)
                    } else if FileManager.default.fileExists(atPath:flag.path) { try FileManager.default.removeItem(at:flag) }
                    self.model.retainDiagnosticCaptures=retain.state == .on
                    UserDefaults.standard.set(self.model.retainDiagnosticCaptures,forKey:"retainDiagnosticCaptures")
                } catch { self.status.stringValue=error.localizedDescription }
            } else if response == .alertThirdButtonReturn { self.deleteDiagnosticData() }
        }
    }
    private func deleteDiagnosticData() {
        guard !busy, model.coordinator.state != .recoveryRequired else { return }
        let alert=NSAlert(); alert.messageText=L("Delete completed diagnostic captures?")
        alert.informativeText=L("Saved exports, calibration references, active copy sessions and data requiring recovery are preserved.")
        alert.addButton(withTitle:L("Delete completed captures")); alert.addButton(withTitle:L("Cancel"))
        alert.beginSheetModal(for:window) { response in
            guard response == .alertFirstButtonReturn else { return }
            do {
                for directory in try FileManager.default.contentsOfDirectory(at:self.state,includingPropertiesForKeys:nil) where directory.lastPathComponent.hasPrefix("scan-") {
                    if let data=try? Data(contentsOf:directory.appendingPathComponent("outcome.json")),
                       let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
                       let name=value["outcome"] as? String, let outcome=OperationOutcome(rawValue:name), outcome.permitsNextOperation {
                        try PrivacyRetention.removeExportedCapture(directory,retainDiagnostics:false,outcome:outcome)
                    }
                }
                self.latestScan=nil; self.updateControls(); self.status.stringValue=L("Completed diagnostic captures deleted.")
            } catch { self.status.stringValue=error.localizedDescription }
        }
    }
    @objc private func importReference() {
        guard !busy else { return }
        let panel=NSOpenPanel(); panel.canChooseDirectories=false; panel.allowsMultipleSelection=false
        panel.message=L("Choose a previously saved IS-12 reference.bin. Identity, checksum and temperature must still validate before acquisition.")
        panel.beginSheetModal(for:window) { response in
            guard response == .OK, let source=panel.url else { return }
            do {
                let data=try Data(contentsOf:source)
                guard data.count==12401, data.prefix(8)==Data("IS12REF1".utf8) else { throw CocoaError(.fileReadCorruptFile) }
                let destination=self.state.appendingPathComponent("reference-\(UUID().uuidString).bin")
                try data.write(to:destination,options:.withoutOverwriting); self.reference=destination; self.referenceValid=nil
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:destination.path)
                try JSONSerialization.data(withJSONObject:["reference":destination.path]).write(to:self.state.appendingPathComponent("settings.json"),options:.atomic)
                self.status.stringValue=L("Reference imported. Connect scanner to check readiness."); self.updateControls()
            } catch { self.status.stringValue=error.localizedDescription }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard process != nil else { return .terminateNow }
        quitting = true; cancelOperation(); return .terminateLater
    }
}
