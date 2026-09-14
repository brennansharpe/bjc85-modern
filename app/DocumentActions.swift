import AppKit
import ImageIO
import UniformTypeIdentifiers

extension UtilityWindowController {
    func persistDocument() {
        guard let document, let store else { return }
        processing.perform(work: { try store.save(document) }) { [weak self] result in
            if case .failure(let error)=result { self?.savingError=error.localizedDescription; self?.report(error) }
        }
    }
    func changeEdits(_ change: (inout DocumentEdits) -> Void) {
        guard var value=document, !documentBusy, scanController?.active == nil else { return }
        let previous=value.edits; change(&value.edits)
        guard previous != value.edits else { return }
        editUndo.registerUndo(withTarget:self) { target in target.replaceEdits(previous) }
        value.revision += 1; document=value; syncEdits(); persistDocument(); refreshPreview(); updateControls()
    }
    func replaceEdits(_ edits: DocumentEdits) { changeEdits { $0=edits } }
    func syncEdits() {
        guard let document else { return }
        let edits=document.edits
        model.region=edits.region; model.adjustments=edits.adjustments
        brightness.doubleValue=edits.adjustments.brightness; contrast.doubleValue=edits.adjustments.contrast
        threshold.integerValue=edits.threshold; invert.state=edits.adjustments.invert ? .on : .off
        filter.selectItem(at:ScanFilter.allCases.firstIndex(of:edits.adjustments.filter) ?? 0)
        mode.selectItem(at:ScanImageType.allCases.firstIndex(of:edits.imageType) ?? 0)
        // Avoid recursively creating an edit when projecting model selection.
        let callback=layout.canvas.changed; layout.canvas.changed=nil; layout.canvas.region=edits.region; layout.canvas.changed=callback
    }
    func refreshPreview() {
        guard let document, let store, !documentBusy else { return }
        previewTicket?.cancel()
        let ticket=ProcessingTicket(); previewTicket=ticket
        do {
            let snapshot=try store.snapshot(document)
            processingCount += 1; updateControls()
            processing.preview(snapshot,ticket:ticket) { [weak self] result in
                self?.processingCount -= 1; self?.updateControls()
                guard let self, self.previewTicket?.id == ticket.id, self.document?.id == document.id, self.document?.revision == document.revision else { return }
                if case .success(let image)=result { self.layout.canvas.image=NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height)) }
                else if !ticket.cancelled, case .failure(let error)=result { self.report(error) }
            }
        } catch { report(error) }
    }
    @objc func undoEdit() { if let text=window?.firstResponder as? NSTextView { text.undoManager?.undo() } else { editUndo.undo() } }
    @objc func redoEdit() { if let text=window?.firstResponder as? NSTextView { text.undoManager?.redo() } else { editUndo.redo() } }
    func windowWillReturnUndoManager(_ window:NSWindow) -> UndoManager? { editUndo }
    @objc func adjustmentsChanged() {
        let adjustments=ScanAdjustments(brightness:brightness.doubleValue,contrast:contrast.doubleValue,invert:invert.state == .on,filter:ScanFilter.allCases[filter.indexOfSelectedItem])
        model.adjustments=adjustments; model.scan.threshold=threshold.integerValue
        changeEdits { $0.adjustments=adjustments; $0.threshold=threshold.integerValue }
    }
    @objc func scanSettingsChanged() {
        model.scan.imageType=ScanImageType.allCases[mode.indexOfSelectedItem]; model.scan.dpi=ScanSettings.resolutions[resolution.indexOfSelectedItem]
        preset.selectItem(at:CanonPreset.all.count); presetNote.stringValue=model.scan.unavailableReason ?? "Custom scan settings"
        changeEdits { $0.imageType=model.scan.imageType }; updateControls()
    }
    @objc func presetChanged() {
        guard preset.indexOfSelectedItem < CanonPreset.all.count else { return }
        let value=CanonPreset.all[preset.indexOfSelectedItem]; model.choose(value)
        mode.selectItem(at:ScanImageType.allCases.firstIndex(of:model.scan.imageType)!); resolution.selectItem(at:ScanSettings.resolutions.firstIndex(of:model.scan.dpi)!)
        presetNote.stringValue=value.qualificationNote
        changeEdits { $0.imageType=value.settings.imageType; $0.threshold=value.settings.threshold }; updateControls()
    }
    @objc func bottomFirstChanged() { /* Acquisition preference; never rewrites a completed document. */ }
    @objc func resetAdjustments() { changeEdits { $0.adjustments = .init(); $0.threshold=128 } }
    @objc func clearCrop() { changeEdits { $0.region = .fullPage } }
    @objc func rotatePage() {
        changeEdits { edits in
            let r=edits.region
            edits.rotation=(edits.rotation+1)%4
            edits.region=ScanRegion(x:max(0,1-r.y-r.height),y:r.x,width:r.height,height:r.width)
        }
    }
    @objc func cropDimensions() {
        guard let window, let document else { return }
        let w=layout.canvas.physicalSize.width, h=layout.canvas.physicalSize.height, r=document.edits.region
        let formatter=dimensionFormatter()
        let fields=[r.x*w,r.y*h,r.width*w,r.height*h].map { value -> NSTextField in
            let field=NSTextField(string:formatter.string(from:NSNumber(value:value)) ?? ""); field.formatter=formatter; return field
        }
        let names=["Left","Top","Width","Height"]
        let form=RootView.column(zip(names,fields).map { label,field in
            field.setAccessibilityLabel("\(label) in inches"); field.widthAnchor.constraint(equalToConstant:100).isActive=true
            return NSStackView(views:[RootView.label(label+" (in)"),field])
        })
        let alert=NSAlert(); alert.messageText="Crop dimensions"; alert.informativeText=LF("Select an area within %.2f × %.2f inches. This crops the acquired page on your Mac.",w,h)
        form.frame=NSRect(x:0,y:0,width:290,height:140); alert.accessoryView=form
        alert.addButton(withTitle:"Apply"); alert.addButton(withTitle:"Cancel")
        alert.beginSheetModal(for:window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self, self.document?.id == document.id else { return }
            let numbers=fields.compactMap { formatter.number(from:$0.stringValue)?.doubleValue }
            guard numbers.count==4 else { self.layout.status.stringValue="Enter four valid dimensions in inches."; return }
            let region=ScanRegion(x:numbers[0]/w,y:numbers[1]/h,width:numbers[2]/w,height:numbers[3]/h)
            guard region.isValid else { self.layout.status.stringValue="The selection must fit within the page. Open Crop Dimensions to correct it."; return }
            self.changeEdits { $0.region=region }; self.window?.makeFirstResponder(self.layout.canvas)
        }
    }
    @objc func openImage() {
        guard !documentBusy, scanController?.active == nil, let window else { return }
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.png,.tiff,.jpeg,.pdf]; panel.allowsMultipleSelection=false
        panel.message="Open an image as a retained document. A scanner connection is not required."
        panel.beginSheetModal(for:window) { [weak self] response in if response == .OK, let source=panel.url { self?.importImage(source) } }
    }
    func importImage(_ source:URL, acquisition:ScanAcquisition? = nil, edits:DocumentEdits = .init(), completion:((ScanDocument) -> Void)? = nil, failure:((Error) -> Void)? = nil) {
        guard let store else { return }
        previewTicket?.cancel(); documentBusy=true; updateControls()
        let previous=document
        processing.perform(work: {
            // Close protects even unexported revisions; it does not discard.
            let value=try store.importImage(source,acquisition:acquisition,edits:edits)
            if let previous { try store.close(previous) }; try store.activate(value.id)
            return value
        }) { [weak self] result in
            guard let self else { return }; self.documentBusy=false
            do {
                self.document=try result.get(); self.editUndo.removeAllActions(); self.syncEdits(); self.refreshPreview()
                self.layout.status.stringValue=self.fixture ? "Fixture · Synthetic document retained · No physical jobs" : "Document retained. Edit, export more than once, or print when the device is ready."
                completion?(self.document!); self.applyFixturePresentation()
            } catch { self.report(error); failure?(error) }
            self.updateControls()
        }
    }
    @objc func exportDocument() {
        guard let document, exportTicket == nil, !documentBusy, let window else { return }
        let panel=NSSavePanel(); savePanel=panel; panel.allowedContentTypes=[.png,.tiff,.pdf]; panel.canCreateDirectories=true; panel.isExtensionHidden=false
        panel.nameFieldStringValue="IS-12 scan.png"
        let formats=NSPopUpButton(); formats.addItems(withTitles:["PNG","TIFF","PDF"]); formats.setAccessibilityLabel("Export format"); formats.target=self; formats.action=#selector(exportFormatChanged(_:)); panel.accessoryView=formats
        panel.beginSheetModal(for:window) { [weak self] response in
            guard let self else { return }; self.savePanel=nil
            guard response == .OK, let destination=panel.url, self.document?.id == document.id else { return }
            self.export(to:destination)
        }
    }
    @objc func exportFormatChanged(_ sender:NSPopUpButton) {
        let extensions=["png","tiff","pdf"], types:[UTType]=[.png,.tiff,.pdf]
        guard let savePanel else { return }; savePanel.allowedContentTypes=[types[sender.indexOfSelectedItem]]
        savePanel.nameFieldStringValue=(savePanel.nameFieldStringValue as NSString).deletingPathExtension+"."+extensions[sender.indexOfSelectedItem]
    }
    func export(to destination:URL) {
        guard let document, let store else { return }
        let ticket=ProcessingTicket(); exportTicket=ticket; layout.status.stringValue="Exporting revision \(document.revision)…"; updateControls()
        do {
            let snapshot=try store.snapshot(document)
            processing.export(snapshot,to:destination,runtime:root,ticket:ticket) { [weak self] result in
                guard let self, self.exportTicket?.id == ticket.id else { return }; self.exportTicket=nil
                do {
                    let receipt=try result.get()
                    if self.document?.id == document.id { self.document?.exports.append(receipt); self.persistDocument() }
                    else {
                        self.processing.perform(work: { var saved=try store.load(document.id); saved.exports.append(receipt); try store.save(saved) }) { [weak self] value in if case .failure(let error)=value { self?.report(error) } }
                    }
                    self.layout.status.stringValue="Exported \(destination.lastPathComponent). The editable document is retained."
                } catch is CancellationError { self.layout.status.stringValue="Export canceled. The document and previous output are retained." }
                catch { self.report(error) }
                self.updateControls()
            }
        } catch { exportTicket=nil; report(error) }
    }
    @objc func cancelExport() { exportTicket?.cancel(); layout.status.stringValue="Stopping export before output replacement…" }
    @objc func newDocument() { closeDocument() }
    @objc func closeDocument() {
        guard let document, let store, scanController?.active == nil, !documentBusy else { return }
        previewTicket?.cancel(); documentBusy=true
        processing.perform(work: { try store.close(document) }) { [weak self] result in
            guard let self else { return }; self.documentBusy=false
            do { try result.get(); self.document=nil; self.layout.canvas.image=nil; self.editUndo.removeAllActions(); self.layout.status.stringValue="Document closed and retained. Use File → Retained Documents to reopen it."; self.window?.makeFirstResponder(self.layout.canvas) }
            catch { self.report(error) }; self.updateControls()
        }
    }
    @objc func discardDocument() {
        guard let document, let window, scanController?.active == nil, exportTicket == nil else { return }
        let alert=NSAlert(); alert.messageText="Discard this retained document?"; alert.informativeText="This removes its private master and edits. Exported files stay in their chosen folders. A document retained by Copy must be released in Copy first."
        alert.addButton(withTitle:"Keep Document"); alert.addButton(withTitle:"Discard")
        alert.beginSheetModal(for:window) { [weak self] response in
            guard response == .alertSecondButtonReturn, let self, self.document?.id == document.id else { return }
            self.previewTicket?.cancel(); self.documentBusy=true
            let store=self.store!
            self.processing.perform(work: { try store.discard(document.id) }) { [weak self] result in
                guard let self else { return }; self.documentBusy=false
                do { try result.get(); self.document=nil; self.layout.canvas.image=nil; self.editUndo.removeAllActions() } catch { self.report(error) }; self.updateControls()
            }
        }
    }
    @objc func showRetainedDocuments() {
        guard let store, let window else { return }
        processing.perform(work: { try store.all() }) { [weak self] result in
            guard let self else { return }
            do {
                let documents=try result.get(); let alert=NSAlert(); alert.messageText="Retained documents"
                let choices=NSPopUpButton(); choices.addItems(withTitles:documents.map { "\($0.acquisition.acquired.formatted(date:.abbreviated,time:.shortened)) · \($0.acquisition.source)\($0.needsExport ? " · not exported" : "")" })
                choices.frame=NSRect(x:0,y:0,width:360,height:32); choices.setAccessibilityLabel("Retained document")
                alert.accessoryView=choices; alert.addButton(withTitle:"Open"); alert.addButton(withTitle:"Cancel"); alert.buttons[0].isEnabled = !documents.isEmpty
                alert.beginSheetModal(for:window) { response in if response == .alertFirstButtonReturn, documents.indices.contains(choices.indexOfSelectedItem) { self.reopenDocument(documents[choices.indexOfSelectedItem].id) } }
            } catch { self.report(error) }
        }
    }
    func reopenDocument(_ id:UUID) {
        guard let store, !documentBusy, scanController?.active == nil else { return }
        let previous=document; documentBusy=true
        processing.perform(work: { let value=try store.load(id); if let previous { try store.close(previous) }; try store.activate(id); return value }) { [weak self] result in
            guard let self else { return }; self.documentBusy=false
            do {
                self.document=try result.get(); self.document?.closedAt=nil; self.editUndo.removeAllActions(); self.syncEdits(); self.refreshPreview(); self.persistDocument()
                self.layout.status.stringValue="Retained document reopened. No physical operation resumed."
                self.window?.makeFirstResponder(self.layout.canvas)
            } catch { self.report(error) }; self.updateControls()
        }
    }
    func windowShouldClose(_ sender:NSWindow) -> Bool {
        if scanController?.active != nil || documentBusy || exportTicket != nil { layout.status.stringValue="Finish or cancel the current operation before closing the window."; return false }
        return true // Persistent session is restored on next launch.
    }
    func prepareToQuit() -> NSApplication.TerminateReply {
        guard savingError == nil else { layout.status.stringValue="The session could not be saved. Export the document before quitting. \(savingError!)"; return .terminateCancel }
        guard scanController?.active == nil, !documentBusy, exportTicket == nil, !serviceBusy else { layout.status.stringValue="Finish or cancel the current operation before quitting."; return .terminateCancel }
        // Drain all queued metadata writes without blocking AppKit. Print jobs
        // remain in their native queue, with references saved for reconciliation.
        processing.perform(work: {}) { [weak self] _ in NSApp.reply(toApplicationShouldTerminate:self?.savingError == nil) }
        return .terminateLater
    }
}
