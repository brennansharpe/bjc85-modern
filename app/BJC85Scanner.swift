import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin

// An arriving image must fit the available pane, never resize the app window.
private final class ScanImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

// Development application: the protocol process and all dependencies are native.
// One process owns USB at a time; partial captures remain available after failure.
@main
@MainActor
final class ScannerApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let preview = ScanImageView()
    private let previewQueue = DispatchQueue(label: "local.bjc85.live-preview", qos: .userInitiated)
    private var livePreview: LiveScanPreview?
    private var liveSize = (width: 0, height: 0, rows: 0)
    private var previewRevision = 0
    private var previewUnavailable = false
    private var cancelling = false
    private let status = NSTextField(wrappingLabelWithString: "Connect the BJC-85 with the IS-12 installed.")
    private let referenceStatus = NSTextField(wrappingLabelWithString: "No white reference saved.")
    private let resolution = NSPopUpButton()
    private let mode = NSPopUpButton()
    private let rotate = NSButton(checkboxWithTitle: "Sheet was fed bottom first", target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private let connect = NSButton(title: "Connect scanner", target: nil, action: nil)
    private let calibrate = NSButton(title: "Calibrate white sheet", target: nil, action: nil)
    private let scan = NSButton(title: "Scan page", target: nil, action: nil)
    private let cancel = NSButton(title: "Cancel", target: nil, action: nil)
    private let save = NSButton(title: "Save image…", target: nil, action: nil)
    private let files = NSButton(title: "Show files", target: nil, action: nil)
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
        guard let project = Bundle.main.object(forInfoDictionaryKey: "BJC85ProjectRoot") as? String else {
            NSApplication.shared.terminate(nil); return
        }
        root = URL(fileURLWithPath: project, isDirectory: true)
        state = root.appendingPathComponent(".state/scanner-app", isDirectory: true)
        helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/bjc85-is12")
        do {
            try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            if let data = try? Data(contentsOf: state.appendingPathComponent("settings.json")),
               let settings = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let path = settings["reference"], FileManager.default.fileExists(atPath: path) {
                reference = URL(fileURLWithPath: path)
            } else {
                let first = root.appendingPathComponent(".state/is12-calibration-001/reference.bin")
                if FileManager.default.fileExists(atPath: first.path) { reference = first }
            }
        } catch { status.stringValue = "Cannot create the scanner's output folder: \(error.localizedDescription)" }
        makeWindow()
        updateControls()
        // Offline display mode does not open USB, pause queues, or feed paper.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--preview"), index + 1 < arguments.count {
            let url = URL(fileURLWithPath: arguments[index + 1])
            preview.image = NSImage(contentsOf: url)
            latestDPI = Int((try? ScanExport.dpi(of: url))?.rounded() ?? 90)
            status.stringValue = "Saved scan · \(latestDPI) dpi"
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
        appMenu.addItem(withTitle: "Quit BJC-85 Scanner", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; menu.addItem(item); NSApp.mainMenu = menu
        let deviceItem = NSMenuItem(title: "Device", action: nil, keyEquivalent: "")
        let deviceMenu = NSMenu(title: "Device")
        deviceMenu.addItem(withTitle: "Open Image Capture", action: #selector(openImageCapture), keyEquivalent: "")
        deviceMenu.addItem(withTitle: "Switch to printing…", action: #selector(preparePrinting), keyEquivalent: "")
        deviceItem.submenu = deviceMenu; menu.addItem(deviceItem)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 750),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "BJC-85 Scanner"
        window.minSize = NSSize(width: 820, height: 620)
        window.center()
        let title = NSTextField(labelWithString: "Canon IS-12")
        title.font = .systemFont(ofSize: 25, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: "Native scanning for your BJC-85")
        subtitle.textColor = .secondaryLabelColor
        let help = NSTextField(wrappingLabelWithString: "Install the IS-12 before connecting. Load one sheet for each scan. Connecting pauses the BJC-85 print queue.")
        help.font = .systemFont(ofSize: 12)
        resolution.addItems(withTitles: ["90 dpi", "180 dpi", "360 dpi"])
        resolution.setAccessibilityLabel("Scan resolution")
        mode.addItems(withTitles: ["Colour", "Grayscale", "Black and white"])
        mode.setAccessibilityLabel("Scan mode")
        rotate.state = .on
        rotate.target = self; rotate.action = #selector(refreshPreview)
        connect.target = self; connect.action = #selector(connectScanner)
        calibrate.target = self; calibrate.action = #selector(calibrateSheet)
        scan.target = self; scan.action = #selector(scanPage)
        scan.keyEquivalent = "\r"
        cancel.target = self; cancel.action = #selector(cancelOperation)
        save.target = self; save.action = #selector(saveImage)
        files.target = self; files.action = #selector(showFiles)
        referenceStatus.font = .systemFont(ofSize: 12)
        referenceStatus.textColor = .secondaryLabelColor
        let calibrationHelp = NSTextField(wrappingLabelWithString: "Use a clean white sheet for calibration. This corrects uneven shading; colour accuracy with ordinary paper is unverified.")
        calibrationHelp.font = .systemFont(ofSize: 12)
        calibrationHelp.textColor = .secondaryLabelColor
        progress.style = .bar; progress.isIndeterminate = true
        progress.isDisplayedWhenStopped = false
        let controls = NSStackView(views: [title, subtitle, space(10), help, connect, space(14),
                                          mode, resolution, rotate,
                                          scan, cancel, space(14), referenceStatus, calibrationHelp, calibrate,
                                          space(14), progress, status, space(14), save, files])
        controls.orientation = .vertical; controls.alignment = .leading; controls.spacing = 10
        for control in [connect, mode, resolution, scan, cancel, calibrate, save, files] as [NSView] {
            control.widthAnchor.constraint(equalToConstant: 244).isActive = true
        }
        controls.widthAnchor.constraint(equalToConstant: 258).isActive = true
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.setAccessibilityLabel("Scanned page preview")
        preview.wantsLayer = true
        preview.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        let body = NSStackView(views: [controls, preview])
        body.orientation = .horizontal; body.alignment = .top; body.spacing = 24
        body.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            body.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            body.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            body.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -24),
            preview.heightAnchor.constraint(equalTo: body.heightAnchor),
            preview.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),
            progress.widthAnchor.constraint(equalToConstant: 244)
        ])
    }

    private func space(_ height: CGFloat) -> NSView {
        let view = NSView(); view.heightAnchor.constraint(equalToConstant: height).isActive = true; return view
    }

    private func updateControls() {
        connect.isEnabled = !busy
        calibrate.isEnabled = connected && !busy
        scan.isEnabled = connected && reference != nil && !busy
        cancel.isEnabled = busy && process != nil
        resolution.isEnabled = !busy
        mode.isEnabled = !busy
        save.isEnabled = latestScan != nil && !busy
        files.isEnabled = !busy
        referenceStatus.stringValue = reference == nil ? "No white reference saved." : "White-paper reference saved."
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
        guard !busy else { return }
        busy = true; connected = false; status.stringValue = "Preparing scanner connection…"; updateControls()
        let installScript = root.appendingPathComponent("scripts/install-scanner-service.sh").path
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            do {
                let queue = try Self.command("/usr/bin/lpstat", ["-p", "BJC85_Native"])
                if queue.0 == 0 {
                    let jobs = try Self.command("/usr/bin/lpstat", ["-W", "not-completed", "-o", "BJC85_Native"])
                    if jobs.0 != 0 || !jobs.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        failure = "Finish or cancel the pending BJC-85 print jobs before scanning."
                    } else {
                        let paused = try Self.command("/usr/sbin/cupsdisable", ["-r", "IS-12 scanner installed; restore BC-11e before printing.", "BJC85_Native"])
                        if paused.0 != 0 { failure = "Could not pause the BJC-85 print queue. \(paused.1)" }
                    }
                }
                if failure == nil {
                    let label = "gui/\(getuid())/local.bjc85.native-print"
                    let service = try Self.command("/bin/launchctl", ["print", label])
                    if service.0 == 0 {
                        let stopped = try Self.command("/bin/launchctl", ["bootout", label])
                        if stopped.0 != 0 { failure = "Could not stop the print service. \(stopped.1)" }
                    }
                }
                if failure == nil {
                    let enabled = try Self.command("/bin/sh", [installScript, "--scanner-installed"])
                    if enabled.0 != 0 { failure = "Could not enable macOS scanning. \(enabled.1)" }
                }
            } catch { failure = error.localizedDescription }
            let result = failure
            DispatchQueue.main.async {
                self.busy = false
                if let result { self.status.stringValue = result; self.updateControls() }
                else { self.start("connect", arguments: ["status", "--scanner-installed", "--enter-scanner-mode"], directory: nil) }
            }
        }
    }

    @objc private func calibrateSheet() {
        guard connected && !busy else { return }
        let directory = state.appendingPathComponent("reference-\(UUID().uuidString)", isDirectory: true)
        start("calibrate", arguments: ["calibrate", "--scanner-installed", "--plain-paper-reference", directory.path], directory: directory)
    }

    @objc private func scanPage() {
        guard connected && !busy, let reference else { return }
        requestedDPI = [90,180,360][resolution.indexOfSelectedItem]
        requestedMode = ["color", "gray", "bw"][mode.indexOfSelectedItem]
        let directory = state.appendingPathComponent("scan-\(UUID().uuidString)", isDirectory: true)
        start("scan", arguments: ["scan", "--scanner-installed", "--calibration", reference.path,
                                 "--dpi", String(requestedDPI), "--mode", requestedMode,
                                 "--live-preview", directory.path], directory: directory)
    }

    private func start(_ kind: String, arguments: [String], directory: URL?) {
        guard !busy else { return }
        operation = kind; operationDirectory = directory
        cancelling = false
        if kind == "scan", let directory {
            latestScan = nil; preview.image = nil
            livePreview = LiveScanPreview(directory: directory)
            liveSize = (0, 0, 0); previewUnavailable = false; previewRevision += 1
        }
        pending.removeAll(); tail = ""; busy = true
        status.stringValue = kind == "calibrate" ? "Measuring the blank white sheet…" : kind == "scan" ? "Starting scan…" : "Checking IS-12…"
        progress.isIndeterminate = true
        progress.doubleValue = 0
        let log = state.appendingPathComponent("\(kind)-\(UUID().uuidString).jsonl")
        let task = Process(), pipe = Pipe()
        do {
            guard FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw NSError(domain: "BJC85", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create operation log."])
            }
            logHandle = try FileHandle(forWritingTo: log)
            task.executableURL = helper; task.arguments = arguments; task.currentDirectoryURL = root
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
            try? logHandle?.close(); logHandle = nil
            status.stringValue = "Could not start: \(error.localizedDescription)"
        }
        updateControls()
    }

    private func receive(_ data: Data) {
        do { try logHandle?.write(contentsOf: data) }
        catch { status.stringValue = "Cannot save operation log; stopping."; process?.interrupt() }
        pending.append(data)
        while let end = pending.firstIndex(of: 10) {
            let line = pending.prefix(upTo: end)
            pending.removeSubrange(...end)
            if let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                let event = record["event"] as? String
                if event == "head_check", record["matches_canon_bjc85_is12_checks"] as? Bool == true { connected = true }
                if event == "scan_preview", operation == "scan", !cancelling,
                   let width = record["width"] as? Int, let height = record["height"] as? Int,
                   let rows = record["rows"] as? Int, width > 0, width <= 750,
                   height > 0, height <= 1250, rows > 0, rows <= height {
                    liveSize = (width, height, rows)
                    let percentage = min(99, rows * 100 / height)
                    progress.isIndeterminate = false; progress.doubleValue = Double(percentage)
                    status.stringValue = rows == height ? "Finishing scan…" : "Scanning at \(requestedDPI) dpi · \(percentage)%"
                    refreshLivePreview()
                }
                if event == "scan_preview_unavailable" { previewUnavailable = true }
                if event == "scan_progress", let count = record["image_bytes"] as? Int, operation == "scan",
                   !cancelling, liveSize.rows == 0 || previewUnavailable {
                    let bytesPerPixel = requestedMode == "color" ? 3.0 : 1.0
                    let expected = Double(requestedDPI * 8) * Double(requestedDPI) * 10.8 * bytesPerPixel
                    let percentage = min(99, Int(Double(count) / expected * 100))
                    progress.isIndeterminate = false; progress.doubleValue = Double(percentage)
                    status.stringValue = "Scanning at \(requestedDPI) dpi · \(percentage)%"
                }
            } else {
                let text = String(decoding: line, as: UTF8.self)
                if !text.isEmpty { tail = String((tail + text + "\n").suffix(1400)) }
            }
        }
    }

    private func finished(_ code: Int32) {
        process = nil; outputPipe = nil; busy = false
        try? logHandle?.synchronize(); try? logHandle?.close(); logHandle = nil
        if code == 0 {
            if operation == "scan", let directory = operationDirectory {
                livePreview = nil; previewRevision += 1
                latestDPI = requestedDPI
                latestScan = directory; refreshPreview()
                status.stringValue = "Scan complete · \(latestDPI) dpi · white-paper correction"
            } else if operation == "calibrate", let directory = operationDirectory {
                reference = directory.appendingPathComponent("reference.bin")
                if let data = try? JSONSerialization.data(withJSONObject: ["reference": reference!.path], options: .prettyPrinted) {
                    try? data.write(to: state.appendingPathComponent("settings.json"), options: .atomic)
                }
                status.stringValue = "White reference saved. Load your document, then choose Scan page."
            } else {
                status.stringValue = connected ? "IS-12 connected. Ready to scan." : "Connected device did not pass the IS-12 check."
            }
        } else {
            connected = false
            status.stringValue = cancelling ? "Scan cancelled. The preview is partial; captured data is retained in Show files. Reconnect before scanning." :
                tail.isEmpty ? "Operation stopped. Captured data is retained in Show files. Reconnect before trying again." : tail
        }
        updateControls()
        if quitting { NSApp.reply(toApplicationShouldTerminate: true) }
    }

    @objc private func cancelOperation() {
        cancelling = true; previewRevision += 1
        process?.interrupt()
        cancel.isEnabled = false
        status.stringValue = "Stopping and retaining the captured data…"
    }

    @objc private func refreshPreview() {
        if livePreview != nil { refreshLivePreview(); return }
        guard let directory = latestScan else { return }
        preview.image = NSImage(contentsOf: directory.appendingPathComponent(rotate.state == .on ? "scan-upright.png" : "scan-raw.png"))
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
        guard !busy else { return }
        let alert = NSAlert()
        alert.messageText = "Install the BC-11e before enabling printing"
        alert.informativeText = "Finish any scan in Image Capture, replace the IS-12 with the BC-11e, and load paper. Enabling printing stops the scanner service and resumes the Canon BJC-85 Native print queue."
        alert.addButton(withTitle: "BC-11e installed — enable printing")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            self.busy = true; self.status.stringValue = "Preparing printing…"; self.updateControls()
            let script = self.root.appendingPathComponent("scripts/resume-printing.sh").path
            DispatchQueue.global(qos: .userInitiated).async {
                let result: (Int32, String)
                do { result = try Self.command("/bin/sh", [script, "--bc11e-installed"]) }
                catch { result = (1, error.localizedDescription) }
                DispatchQueue.main.async {
                    self.busy = false
                    if result.0 == 0 {
                        self.connected = false
                        self.status.stringValue = "Printing enabled. Choose Canon BJC-85 Native in the Print dialog."
                    } else { self.status.stringValue = result.1 }
                    self.updateControls()
                }
            }
        }
    }

    @objc private func saveImage() {
        guard let directory = latestScan else { return }
        let source = directory.appendingPathComponent(rotate.state == .on ? "scan-upright.png" : "scan-raw.png")
        let panel = NSSavePanel()
        savePanel = panel
        panel.allowedContentTypes = [.png, .tiff, .pdf]
        panel.canCreateDirectories = true; panel.isExtensionHidden = false
        panel.nameFieldStringValue = "IS-12 scan.png"
        let formats = NSPopUpButton()
        formats.addItems(withTitles: ["PNG", "TIFF", "PDF"])
        formats.target = self; formats.action = #selector(saveFormatChanged(_:))
        panel.accessoryView = formats
        panel.beginSheetModal(for: window) { response in
            defer { self.savePanel = nil }
            guard response == .OK, let destination = panel.url else { return }
            do {
                try ScanExport.write(source: source, destination: destination)
                self.status.stringValue = "Saved \(destination.lastPathComponent)"
            } catch { self.status.stringValue = "Could not save: \(error.localizedDescription)" }
        }
    }

    @objc private func saveFormatChanged(_ sender: NSPopUpButton) {
        guard let panel = savePanel else { return }
        let types: [UTType] = [.png, .tiff, .pdf]
        panel.allowedContentTypes = [types[sender.indexOfSelectedItem]]
        let stem = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.nameFieldStringValue = stem + "." + ["png", "tiff", "pdf"][sender.indexOfSelectedItem]
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard process != nil else { return .terminateNow }
        quitting = true; cancelOperation(); return .terminateLater
    }
}
