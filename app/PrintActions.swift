import AppKit

extension UtilityWindowController {
    @objc func preparePrinting() {
        guard !busy, !fixture, model.coordinator.state != .recoveryRequired, let window else { return }
        if model.coordinator.state == .printerReady { _=model.copy.printerConfirmed(); saveCopySession(); updateControls(); return }
        // Opening or canceling the sheet has no coordinator side effect.
        let alert=CartridgeSwapView.sheet()
        alert.buttons[1].title="Cancel — no cartridge change"
        alert.addButton(withTitle:"Changed cartridge / unsure")
        alert.beginSheetModal(for:window) { [weak self] response in
            guard let self else { return }
            if response == .alertSecondButtonReturn { self.updateControls(); return }
            if response == .alertThirdButtonReturn {
                _=self.model.coordinator.requestPrint(); self.model.coordinator.cancelPrintCartridge(unchanged:false)
                self.referenceValid=nil; self.model.copy.needsCartridgeValidation()
                self.layout.status.stringValue="Cartridge state needs revalidation. Connect the scanner or confirm the print cartridge before continuing."; self.updateControls(); return
            }
            guard response == .alertFirstButtonReturn else { return }
            _=self.model.coordinator.requestPrint()
            self.serviceBusy=true; self.layout.status.stringValue="Preparing local print service…"; self.updateControls()
            let bundle=Bundle.main.bundleURL, runtime=self.root
            self.processing.perform(work: { try ServiceController.preparePrinter(bundle:bundle,runtime:runtime) }) { [weak self] result in
                guard let self else { return }; self.serviceBusy=false; self.referenceValid=nil
                do {
                    try result.get(); _=self.model.coordinator.confirmPrintCartridge(servicePrepared:true); _=self.model.copy.printerConfirmed(); self.saveCopySession()
                    self.layout.status.stringValue="Print cartridge confirmed by operator. Review settings, then choose Print."
                } catch { self.report(error) }
                self.updateControls()
            }
        }
    }
    @objc func printDocument() {
        guard printButton.isEnabled, let document else { return }
        guard model.coordinator.state == .printerReady else { preparePrinting(); return }
        submitDocument(document,copy:false,settings:printSettings.settings)
    }
    @objc func printCopy() {
        guard copyControls.reprint.isEnabled, let id=model.copy.documentID else {
            if model.copy.image != nil && model.copy.documentID == nil { layout.status.stringValue="This is a legacy retained PDF. Open it in Preview to print with the normal system dialog." }
            return
        }
        guard let document, document.id==id else { reopenDocument(id); return }
        submitDocument(document,copy:true,settings:copyControls.settings.settings)
    }
    func submitDocument(_ document:ScanDocument, copy:Bool, settings:PrintSettings) {
        guard settings.isValid, !busy, !documentBusy, !fixture, let store, let tracker, latestJob?.outstanding != true else { updateControls(); return }
        guard model.coordinator.state == .printerReady else { preparePrinting(); return }
        let attempt=UUID(), ticket=ProcessingTicket()
        do {
            let snapshot=try store.snapshot(document)
            documentBusy=true; layout.status.stringValue="Preparing revision \(document.revision) for printing…"; updateControls()
            let staging=state.appendingPathComponent("print-\(attempt).pdf")
            // Rendering does not yet mutate the physical operation or Copy state.
            processing.perform(ticket:ticket,work: {
                let image=try ImageProcessingService.render(snapshot,ticket:ticket)
                try ScanExport.write(image:image,dpi:document.acquisition.dpi,destination:staging)
                return staging
            }) { [weak self] result in
                guard let self else { return }; self.documentBusy=false
                do {
                    let pdf=try result.get()
                    guard self.model.coordinator.requestPrint() else { self.updateControls(); return }
                    if copy { guard self.model.copy.beginPrint(id:attempt) != nil else { self.model.coordinator.preflightRefused(); self.updateControls(); return } }
                    self.serviceBusy=true; self.saveCopySession(); self.updateControls()
                    self.processing.perform(work: { try tracker.submit(pdf,settings:settings,document:document.id,copy:copy,attempt:attempt,revision:document.revision) }) { [weak self] value in
                        guard let self else { return }; self.serviceBusy=false
                        do { self.latestJob=try value.get(); self.layout.status.stringValue=self.latestJob!.result.label; self.recheckJob() }
                        catch {
                            self.model.coordinator.preflightRefused()
                            if copy { self.model.copy.printFinished(.rejected,safe:true,attempt:attempt); self.saveCopySession() }
                            self.report(error)
                        }
                        self.updateControls()
                    }
                } catch { self.report(error) }
                self.updateControls()
            }
        } catch { report(error) }
    }
    @objc func recheckJob() {
        guard !fixture, let tracker else { updateControls(); return }
        jobTimer?.invalidate(); jobTimer=nil
        let runtime=root
        processing.perform(work: { (try tracker.reconcile(), SharedDeviceState.inspect(runtime)) }) { [weak self] result in
            guard let self else { return }
            do {
                let (record,safety)=try result.get(); guard let record else { return }
                if let previous=self.latestJob, previous.attempt != record.attempt { return }
                self.latestJob=record; self.lastAvailability=safety
                if record.result == .pending || safety == .busy {
                    self.layout.status.stringValue=record.result.label
                    self.jobTimer=Timer.scheduledTimer(withTimeInterval:2,repeats:false) { [weak self] _ in MainActor.assumeIsolated { self?.recheckJob() } }
                } else {
                    self.applyJobResult(record, safety:safety)
                    // Keep submission evidence for unknown/pending jobs. Safe
                    // terminal jobs can release their temporary rendered input.
                    if !record.outstanding && safety == .available {
                        let staging=self.state.appendingPathComponent("print-\(record.attempt).pdf")
                        self.processing.perform(work: { if FileManager.default.fileExists(atPath:staging.path) { try FileManager.default.removeItem(at:staging) } }) { _ in }
                    }
                }
            } catch { self.report(error) }
            self.updateControls()
        }
    }
    func applyJobResult(_ record:PrintJobRecord, safety:SharedDeviceState.State) {
        guard latestJob?.attempt == record.attempt || latestJob == nil else { return }
        latestJob=record; lastAvailability=safety
        if safety == .recoveryRequired { model.coordinator.requireRecovery() }
        else if safety == .available { model.coordinator.finish(.completedSafe,hasReference:false) }
        if record.isCopy { model.copy.printFinished(record.result,safe:safety == .available,attempt:record.attempt); saveCopySession() }
        layout.status.stringValue=record.result.label+(safety == .available ? " Device lease is idle." : " Device recovery required.")
        updateControls()
    }
    func saveCopySession() {
        let copy=model.copy, destination=state.appendingPathComponent("copy-session.json")
        processing.perform(work: { try copy.saveSession(to:destination) }) { [weak self] result in if case .failure(let error)=result { self?.savingError=error.localizedDescription; self?.report(error) } }
    }
    @objc func resetCopy() {
        guard copyControls.reset.isEnabled else { return }
        let retained=model.copy.documentID
        guard model.copy.reset() else { return }
        saveCopySession()
        if document?.id == retained, let retained { document?.retainedCopies.remove(retained); persistDocument() }
        else if let retained, let store { processing.perform(work: { var value=try store.load(retained); value.retainedCopies.remove(retained); try store.save(value) }) { [weak self] result in if case .failure(let error)=result { self?.report(error) } } }
        layout.status.stringValue="Copy session released. Its editable document remains in Retained Documents."; updateControls()
    }
    @objc func editCopy() {
        guard let id=model.copy.documentID else { return }
        if document?.id != id { reopenDocument(id) }
        layout.navigation.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
    }
}
