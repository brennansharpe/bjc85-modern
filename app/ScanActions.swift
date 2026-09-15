import AppKit

extension UtilityWindowController {
    @objc func connectScanner() {
        guard connect.isEnabled, !fixture, let scanController else { return }
        serviceBusy=true; layout.status.stringValue="Checking service availability…"; updateControls()
        let bundle=Bundle.main.bundleURL, runtime=root, ref=reference ?? state.appendingPathComponent("reference.bin")
        processing.perform(work: { try ServiceController.prepareScanner(bundle:bundle,runtime:runtime,reference:ref) }) { [weak self] result in
            guard let self else { return }; self.serviceBusy=false
            do {
                try result.get(); self.lastAvailability=nil; self.model.copy.needsCartridgeValidation()
                var args=["status","--scanner-installed","--enter-scanner-mode"]
                if let reference=self.reference { args += ["--reference",reference.path] }
                let request=ScanOperationRequest(id:UUID(),copyAttempt:nil,kind:"status",arguments:args,directory:nil,log:self.state.appendingPathComponent("status-\(UUID().uuidString).jsonl"))
                self.pending.removeAll(); self.lastOutcome=nil
                self.layout.status.stringValue="Checking IS-12 readiness…"
                _=scanController.start(request,needsQuiescence:false)
            } catch { self.report(error) }
            self.updateControls()
        }
    }
    @objc func scanPage() { isPrescan=false; confirmScan(copy:false) }
    @objc func prescanPage() { isPrescan=true; confirmScan(copy:false) }
    @objc func copyOriginal() { isPrescan=false; confirmScan(copy:true) }
    func confirmScan(copy:Bool) {
        guard scan.isEnabled, let window, !copy || copyControls.settings.settings.isValid else { return }
        let alert=NSAlert(); alert.messageText=isPrescan ? "Prescan the loaded original?" : "Scan the loaded original?"
        alert.informativeText = hasPrescan && !isPrescan ? "Prescan ejected the sheet. Reload the same original in the same orientation before continuing. The selected area is cropped on your Mac." : "Load one sheet with the IS-12 installed. This starts physical acquisition. The current document and its edits remain retained."
        alert.addButton(withTitle:hasPrescan && !isPrescan ? "Original reloaded — Scan" : "Scan"); alert.addButton(withTitle:"Cancel")
        alert.beginSheetModal(for:window) { [weak self] response in if response == .alertFirstButtonReturn { self?.acquire(copy:copy) } }
    }
    func acquire(copy:Bool) {
        guard scan.isEnabled, let reference, let scanController else { return }
        let id=UUID()
        if copy && !model.copy.beginScan(id:id) { return }
        guard model.coordinator.requestScan() else { model.copy.scanStopped(safely:true,attempt:id); updateControls(); return }
        activeCopyAttempt=copy ? id : nil
        let requestedDPI=isPrescan ? 90 : model.scan.dpi
        let edits=DocumentEdits(rotation:bottomFirst.state == .on ? 2 : 0,region:model.region,adjustments:model.adjustments,imageType:model.scan.imageType,threshold:model.scan.threshold)
        let mode=(isPrescan ? model.scan.previewType : model.scan.imageType).helperMode
        let capture=ScanCapture(acquisition:ScanAcquisition(acquired:Date(),dpi:Double(requestedDPI),width:requestedDPI*8,height:requestedDPI*108/10,
            source:isPrescan ? "IS-12 prescan" : "IS-12 scan",mode:mode,whiteReference:reference.path),edits:edits,prescan:isPrescan)
        let directory=state.appendingPathComponent("scan-\(UUID().uuidString)")
        let request=ScanOperationRequest(id:id,copyAttempt:copy ? id : nil,kind:"scan",arguments:["scan","--scanner-installed","--calibration",reference.path,"--dpi",String(requestedDPI),"--mode",mode,"--live-preview",directory.path],directory:directory,log:state.appendingPathComponent("scan-\(id).jsonl"),capture:capture)
        pending.removeAll(); lastOutcome=nil; livePreview=LiveScanPreview(directory:directory)
        layout.status.stringValue="Preparing acquisition…"; layout.progress.isIndeterminate=true
        _=scanController.start(request); updateControls()
    }
    @objc func calibrateSheet() {
        guard calibrate.isEnabled, let window else { return }
        CalibrationView.sheet(reference:reference,valid:referenceValid).beginSheetModal(for:window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self, self.model.coordinator.requestScan(calibration:true) else { return }
            let id=UUID(), directory=self.state.appendingPathComponent("white-\(UUID().uuidString)")
            self.pending.removeAll(); self.lastOutcome=nil
            self.layout.status.stringValue="Preparing white-sheet measurement…"
            _=self.scanController.start(.init(id:id,copyAttempt:nil,kind:"calibrate",arguments:["calibrate","--scanner-installed","--plain-paper-reference",directory.path],directory:directory,log:self.state.appendingPathComponent("calibrate-\(id).jsonl")))
            self.updateControls()
        }
    }
    func receive(_ id:UUID, _ data:Data) {
        guard scanController.active?.id == id else { return }
        pending.append(data)
        while let end=pending.firstIndex(of:10) {
            let line=Data(pending.prefix(upTo:end)); pending.removeSubrange(...end)
            guard let record=try? JSONSerialization.jsonObject(with:line) as? [String:Any] else { continue }
            let event=record["event"] as? String
            if event == "readiness", let readiness=try? JSONDecoder().decode(ScannerReadiness.self,from:line) {
                lastAvailability=nil
                referenceValid=readiness.reference_valid; model.coordinator.observe(readiness,hasReference:referenceValid == true)
            }
            if event == "operation_outcome", let value=record["outcome"] as? String { lastOutcome=OperationOutcome(rawValue:value) }
            if event == "scan_preview", let width=record["width"] as? Int, let height=record["height"] as? Int,
               let rows=record["rows"] as? Int, width>0,width<=750,height>0,height<=1250,rows>0,rows<=height,let live=livePreview,model.coordinator.state != .cancelling {
                layout.progress.isIndeterminate=false; layout.progress.maxValue=Double(height); layout.progress.doubleValue=Double(rows)
                layout.status.stringValue="Live acquisition preview · \(rows) of \(height) preview rows · final host adjustments pending"
                let rotated=scanController.active?.capture?.edits.rotation == 2
                // At most one active and one queued preview. Stale frames cannot
                // replace a restored/new completed document.
                previewTicket?.cancel(); let ticket=ProcessingTicket(); previewTicket=ticket
                processing.perform(ticket:ticket,work: { try live.update(width:width,height:height,rows:rows,rotate180:rotated) }) { [weak self] result in
                    guard let self,self.scanController.active?.id==id,self.previewTicket?.id==ticket.id else { return }
                    if case .success(let image)=result { self.layout.canvas.image=NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height)) }
                }
            }
        }
        if pending.count>1_048_576 { scanController.cancel(); layout.status.stringValue="Invalid helper output. Stopping acquisition and retaining evidence." }
    }
    func scanFinished(_ completion:ScanOperationCompletion) {
        previewTicket?.cancel(); livePreview=nil; layout.progress.isIndeterminate=true
        let request=completion.request
        if let directory=request.directory, completion.launched {
            processing.perform(work: {
                if FileManager.default.fileExists(atPath:directory.path), FileManager.default.fileExists(atPath:request.log.path) {
                    try FileManager.default.moveItem(at:request.log,to:directory.appendingPathComponent("driver.jsonl"))
                }
            }) { [weak self] result in if case .failure(let error)=result { self?.report(error) } }
        }
        let outcome: OperationOutcome? = completion.launched ? lastOutcome : .preflightFailedSafe
        if !completion.launched { model.coordinator.preflightRefused() }
        else if request.kind != "status" { model.coordinator.finish(outcome,hasReference:referenceValid == true) }
        else if outcome?.permitsNextOperation != true { model.coordinator.requireRecovery() }
        if request.kind == "status" {
            layout.status.stringValue=completion.failure ?? (model.coordinator.state == .scannerReady ? "IS-12 ready. Load one original before choosing Scan." : "Readiness check finished. Review the device state and saved white reference.")
            updateControls(); return
        }
        if completion.exitCode == 0 && outcome == .completedSafe, let directory=request.directory {
            if request.kind == "scan" {
                guard let capture=request.capture else {
                    model.copy.scanStopped(safely:true,attempt:request.copyAttempt); activeCopyAttempt=nil
                    layout.status.stringValue="Acquisition metadata is missing. The completed capture is preserved in private files."; updateControls(); return
                }
                importImage(directory.appendingPathComponent("scan-raw.png"),acquisition:capture.acquisition,edits:capture.edits,captureDirectory:directory) { [weak self] document in
                    guard let self else { return }
                    self.hasPrescan=capture.prescan
                    if let attempt=request.copyAttempt, self.model.copy.retain(self.store.master(document.id),document:document.id,attempt:attempt) {
                        self.saveCopySession()
                        self.layout.navigation.selectRowIndexes(IndexSet(integer:2),byExtendingSelection:false)
                    }
                    self.activeCopyAttempt=nil
                    let keep=self.model.retainDiagnosticCaptures, protected=self.store.directory
                    self.processing.perform(work: {
                        try Data(document.id.uuidString.utf8).write(to:directory.appendingPathComponent("document-imported"),options:.atomic)
                        try PrivacyRetention.removeExportedCapture(directory,retainDiagnostics:keep,outcome:outcome,protected:[protected])
                    }) { [weak self] result in if case .failure(let error)=result { self?.report(error) } }
                } failure: { [weak self] error in
                    self?.model.copy.scanStopped(safely:true,attempt:request.copyAttempt); self?.activeCopyAttempt=nil
                    self?.layout.status.stringValue="The scan completed, but document import failed. Its capture is retained in private files. "+error.localizedDescription
                    self?.updateControls()
                }
            } else if request.kind == "calibrate" {
                reference=directory.appendingPathComponent("reference.bin"); referenceValid=nil; saveReference(); layout.status.stringValue="White reference saved. Connect scanner to validate it before acquisition."
            }
        } else {
            model.copy.scanStopped(safely:outcome?.permitsNextOperation == true,attempt:request.copyAttempt)
            // Clear the Copy association on every terminal path. A later ordinary
            // scan is never inferred to be the result of this attempt.
            activeCopyAttempt=nil
            if let message=completion.failure { layout.status.stringValue=message+" The document is retained; retry when the service is idle." }
            else { layout.status.stringValue=outcome == .cancelledSafe ? "Acquisition canceled safely. Connect scanner to revalidate before retrying." : "Acquisition stopped. Keep the capture and inspect device status before retrying." }
            refreshPreview()
        }
        updateControls()
    }
    @objc func cancelPhysical() {
        if scanController?.active != nil { model.coordinator.cancel(); layout.status.stringValue="Stopping acquisition and retaining capture evidence…"; scanController.cancel() }
        else if latestJob?.result == .pending, let tracker { processing.perform(work: { try tracker.cancel() }) { [weak self] result in if case .failure(let error)=result { self?.report(error) }; self?.recheckJob() } }
        updateControls()
    }
    @objc func recheckDevice() {
        guard !busy, !fixture else { return }
        processing.perform(work: { [root] in SharedDeviceState.inspect(root) }) { [weak self] result in
            guard let self else { return }
            if case .success(let value)=result {
                self.lastAvailability=value
                switch value {
                case .recoveryRequired: self.model.coordinator.requireRecovery()
                case .busy: self.layout.status.stringValue="Another native operation owns the device. Wait for that job to finish."
                case .available: self.layout.status.stringValue="No active lease or recovery marker. Connect scanner to verify readiness; printer cartridge still requires confirmation."
                }
            }; self.updateControls()
        }
    }
    func saveReference() {
        guard let reference else { return }
        persistResource("reference") { [state] in try DiskReceiptStorage().replace(try JSONEncoder().encode(["reference":reference.path]),at:state.appendingPathComponent("settings.json")) }
    }
    @objc func importReference() {
        guard !busy, !fixture, let window else { return }
        let panel=NSOpenPanel(); panel.message="Choose a native reference.bin. The helper must validate its checksum, device identity, and temperature before scanning."
        panel.beginSheetModal(for:window) { [weak self] response in
            guard response == .OK, let source=panel.url, let self else { return }
            let destination=self.state.appendingPathComponent("reference-\(UUID().uuidString).bin")
            self.processing.perform(work: {
                let data=try Data(contentsOf:source)
                guard data.count==12401,data.prefix(8)==Data("IS12REF1".utf8) else { throw CocoaError(.fileReadCorruptFile) }
                try data.write(to:destination,options:.withoutOverwriting); try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:destination.path)
                return destination
            }) { [weak self] result in
                guard let self else { return }; do { self.reference=try result.get(); self.referenceValid=nil; self.saveReference(); self.layout.status.stringValue="Reference imported. Connect scanner to validate it." } catch { self.report(error) }; self.updateControls()
            }
        }
    }
}
