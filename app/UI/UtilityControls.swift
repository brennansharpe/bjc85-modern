import AppKit

extension UtilityWindowController {
    func button(_ title:String, _ action:Selector) -> NSButton {
        let button=NSButton(title:title,target:self,action:action); actionButtons.append(button); return button
    }
    func makeControls() {
        for (control,action) in [(connect,#selector(connectScanner)),(scan,#selector(scanPage)),(prescan,#selector(prescanPage)),(calibrate,#selector(calibrateSheet)),(printButton,#selector(printDocument)),(swap,#selector(preparePrinting)),(layout.cancel,#selector(cancelPhysical)),(layout.cancelExport,#selector(cancelExport))] { control.target=self; control.action=action }
        preset.addItems(withTitles:CanonPreset.all.map(\.name)+["Custom"]); preset.selectItem(at:1); preset.setAccessibilityLabel("Scan preset")
        mode.addItems(withTitles:ScanImageType.allCases.map(\.label)); mode.setAccessibilityLabel("Output mode")
        resolution.addItems(withTitles:ScanSettings.resolutions.map { "\($0) dpi" }); resolution.selectItem(at:4); resolution.setAccessibilityLabel("Acquisition resolution")
        for dpi in [200,300] { resolution.item(at:ScanSettings.resolutions.firstIndex(of:dpi)!)?.isEnabled=false }
        resolution.autoenablesItems=false; mode.autoenablesItems=false; mode.item(at:3)?.isEnabled=false
        preset.autoenablesItems=false
        for (index,item) in CanonPreset.all.enumerated() where item.settings.unavailableReason != nil { preset.item(at:index)?.isEnabled=false }
        preset.target=self; preset.action=#selector(presetChanged)
        for control in [mode,resolution] { control.target=self; control.action=#selector(scanSettingsChanged) }
        for (slider,label) in [(brightness,"Brightness"),(contrast,"Contrast"),(threshold,"B&W threshold")] { slider.isContinuous=false; slider.setAccessibilityLabel(label); slider.target=self; slider.action=#selector(adjustmentsChanged) }
        filter.addItems(withTitles:["None","Sharpen","Soften","Despeckle"]); filter.setAccessibilityLabel("Spatial filter"); filter.target=self; filter.action=#selector(adjustmentsChanged)
        invert.target=self; invert.action=#selector(adjustmentsChanged)
        bottomFirst.state = .on; bottomFirst.target=self; bottomFirst.action=#selector(bottomFirstChanged)
        presetNote.stringValue=CanonPreset.all[1].qualificationNote
        let scanPanel = RootView.column([
            InspectorSection("Acquire",views:[RootView.label("Preset"),preset,presetNote,RootView.label("Output mode"),mode,RootView.label("Resolution for next scan"),resolution,bottomFirst,scan,prescan,
                RootView.label("Prescan ejects the sheet. Reload the same original before a final scan. Live acquisition preview omits final host adjustments.")]),
            InspectorSection("Crop & orientation",views:[button("Crop dimensions…",#selector(cropDimensions)),button("Clear selection",#selector(clearCrop)),button("Rotate clockwise",#selector(rotatePage)),
                RootView.label("Selection is host cropping after full-page acquisition. The lossless master stays unchanged.")]),
            InspectorSection("Adjustments",views:[RootView.label("Brightness"),brightness,RootView.label("Contrast"),contrast,RootView.label("B&W threshold"),threshold,filter,invert,button("Reset adjustments",#selector(resetAdjustments))]),
            InspectorSection("Calibration",views:[referenceLabel,calibrate,RootView.label("Experimental ordinary-paper shading correction. It does not establish Canon-reference colour accuracy.")],expanded:false)
        ],spacing:16)
        let printPanel = RootView.column([title("Print document"),printSettings,printButton,swap,jobLabel,button("Recheck job status",#selector(recheckJob)),button("Open queue details",#selector(openJobs)),
            RootView.label("Settings apply to this document. Other apps keep their normal Command-P dialog. Queue completion does not verify ink on paper.")],spacing:14)
        copyControls.copy.target=self; copyControls.copy.action=#selector(copyOriginal)
        copyControls.swap.target=self; copyControls.swap.action=#selector(preparePrinting)
        copyControls.reprint.target=self; copyControls.reprint.action=#selector(printCopy)
        copyControls.reset.target=self; copyControls.reset.action=#selector(resetCopy)
        copyControls.edit.target=self; copyControls.edit.action=#selector(editCopy)
        let copyPanel = RootView.column([title("Copy"),copyControls,button("Recheck job status",#selector(recheckJob)),button("Open queue details",#selector(openJobs))],spacing:14)
        let devicePanel = RootView.column([title("Device"),connect,button("Prepare printing…",#selector(preparePrinting)),button("Open Image Capture",#selector(openImageCapture)),
            RootView.label("Scanner readiness is detected by native status replies. A BC-11e print cartridge is operator-confirmed; no automatic cartridge or ink-level detection is claimed."),
            button("Import white reference…",#selector(importReference)),button("Calibration guidance…",#selector(calibrationGuidance)),button("Show private files",#selector(showFiles)),
            title("Recovery & maintenance"),RootView.label("If recovery is required, preserve the capture and inspect the printer before any further physical work. Restarting never clears a recovery marker."),button("Recheck device availability",#selector(recheckDevice)),
            RootView.label("Cleaning, deep cleaning, alignment and ink levels are unavailable until verified. The historical black-ink delivery fault is separate from driver outcomes."),
            RootView.label("Independent BJC-85 / IS-12 utility. No Canon endorsement, executables, or artwork.")],spacing:14)
        panels=[scanPanel,printPanel,copyPanel,devicePanel]
        printSettings.changed = { [weak self] in self?.updateControls() }
        copyControls.settings.changed = { [weak self] in self?.updateControls() }
    }
    func title(_ text:String) -> NSTextField { let view=NSTextField(labelWithString:text); view.font = .systemFont(ofSize:16,weight:.semibold); return view }
    func makeMenus() {
        let menu=NSMenu(); NSApp.mainMenu=menu
        func submenu(_ title:String, entries:[(String,Selector?,String)]) -> NSMenu {
            let item=NSMenuItem(title:title,action:nil,keyEquivalent:""), child=NSMenu(title:title); item.submenu=child; menu.addItem(item)
            for (name,action,key) in entries {
                if name.isEmpty { child.addItem(.separator()) }
                else { let entry=child.addItem(withTitle:name,action:action,keyEquivalent:key); entry.target=self }
            }
            return child
        }
        let application=submenu("BJC-85 Utility",entries:[("About BJC-85 Utility",#selector(about),""),("Settings…",#selector(showSettings),","),("",nil,""),("Hide BJC-85 Utility",#selector(NSApplication.hide(_:)),"h"),("Quit BJC-85 Utility",#selector(NSApplication.terminate(_:)),"q")])
        application.items.last?.target=NSApp; application.items[3].target=NSApp
        _=submenu("File",entries:[("New document",#selector(newDocument),"n"),("Open image…",#selector(openImage),"o"),("Retained documents…",#selector(showRetainedDocuments),""),("Retry Saving",#selector(retryPersistence),""),("Retry Recovery",#selector(retryRecovery),""),("Export…",#selector(exportDocument),"s"),("Print document…",#selector(printDocument),"p"),("",nil,""),("Close",#selector(closeCurrentWindowOrDocument),"w"),("Discard document…",#selector(discardDocument),"")])
        let edit=submenu("Edit",entries:[("Undo",#selector(undoEdit),"z"),("Redo",#selector(redoEdit),"Z"),("",nil,""),("Cut",#selector(NSText.cut(_:)),"x"),("Copy",#selector(NSText.copy(_:)),"c"),("Paste",#selector(NSText.paste(_:)),"v"),("Select All",#selector(NSText.selectAll(_:)),"a")])
        for entry in edit.items.dropFirst(3) { entry.target=nil }
        _=submenu("View",entries:[("Fit Page",#selector(fitPage),"0"),("Actual Size (100%)",#selector(actualSize),"1"),("Zoom In",#selector(zoomIn),"+"),("Zoom Out",#selector(zoomOut),"-"),("Rotate Clockwise",#selector(rotatePage),"r"),("Crop Dimensions…",#selector(cropDimensions),""),("Toggle Sidebar",#selector(toggleSidebar),""),("Toggle Inspector",#selector(toggleInspector),"")])
        _=submenu("Device",entries:[("Connect Scanner",#selector(connectScanner),""),("Prepare Printing…",#selector(preparePrinting),""),("Cancel Physical Operation",#selector(cancelPhysical),"."),("Cancel Export",#selector(cancelExport),"")])
        let windows=submenu("Window",entries:[("Minimize",#selector(NSWindow.performMiniaturize(_:)),"m"),("Zoom",#selector(NSWindow.performZoom(_:)),"")]); for item in windows.items { item.target=window }; NSApp.windowsMenu=windows
        _=submenu("Help",entries:[("BJC-85 Utility Help",#selector(showHelp),"?"),("Show Private Files",#selector(showFiles),"")])
    }
    func toolbarAllowedItemIdentifiers(_ toolbar:NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar:NSToolbar) -> [NSToolbarItem.Identifier] { [.init("sidebar"),.init("open"),.flexibleSpace,.init("fit"),.init("actual"),.init("rotate"),.flexibleSpace,.init("export"),.init("print"),.init("inspector")] }
    func toolbar(_ toolbar:NSToolbar,itemForItemIdentifier id:NSToolbarItem.Identifier,willBeInsertedIntoToolbar:Bool) -> NSToolbarItem? {
        let items:[String:(String,String,Selector)] = ["sidebar":("Sidebar","sidebar.left",#selector(toggleSidebar)),"open":("Open Image","folder",#selector(openImage)),"fit":("Fit Page","arrow.up.left.and.arrow.down.right",#selector(fitPage)),"actual":("100%","1.magnifyingglass",#selector(actualSize)),"rotate":("Rotate","rotate.right",#selector(rotatePage)),"export":("Export","square.and.arrow.up",#selector(exportDocument)),"print":("Print","printer",#selector(printDocument)),"inspector":("Inspector","sidebar.right",#selector(toggleInspector))]
        guard let (label,symbol,action)=items[id.rawValue] else { return nil }
        let item=NSToolbarItem(itemIdentifier:id); item.label=label; item.toolTip=label; item.image=NSImage(systemSymbolName:symbol,accessibilityDescription:label); item.target=self; item.action=action; return item
    }
    func validateToolbarItem(_ item:NSToolbarItem) -> Bool { canPerform(item.action) }
    func validateMenuItem(_ menuItem:NSMenuItem) -> Bool { canPerform(menuItem.action) }
    func canPerform(_ action:Selector?) -> Bool {
        switch action {
        case #selector(printDocument): return printButton.isEnabled
        case #selector(connectScanner): return connect.isEnabled
        case #selector(preparePrinting): return swap.isEnabled
        case #selector(closeCurrentWindowOrDocument): return NSApp.keyWindow != nil && NSApp.keyWindow !== window || (!documentBusy && scanController?.active == nil)
        case #selector(openJobs),#selector(openImageCapture): return !fixture
        case #selector(importReference),#selector(recheckDevice): return !busy && !fixture
        case #selector(recheckJob): return latestJob != nil && !fixture
        case #selector(editCopy): return model.copy.documentID != nil && !documentBusy && scanController?.active == nil
        case #selector(deleteDiagnostics): return store != nil && !busy && !documentBusy
        case #selector(exportDocument): return document != nil && !documentBusy && exportTicket == nil
        case #selector(discardDocument): return document != nil && !documentBusy && scanController?.active == nil && exportTicket == nil
        case #selector(rotatePage),#selector(cropDimensions),#selector(clearCrop),#selector(closeDocument): return document != nil && !documentBusy && scanController?.active == nil
        case #selector(openImage),#selector(showRetainedDocuments): return !documentBusy && scanController?.active == nil
        case #selector(cancelPhysical): return scanController?.active != nil || latestJob?.result == .pending
        case #selector(cancelExport): return exportTicket != nil
        case #selector(undoEdit): return (window?.firstResponder as? NSTextView)?.undoManager?.canUndo ?? editUndo.canUndo
        case #selector(redoEdit): return (window?.firstResponder as? NSTextView)?.undoManager?.canRedo ?? editUndo.canRedo
        default: return true
        }
    }
    @objc func closeCurrentWindowOrDocument() {
        if let key=NSApp.keyWindow, key !== window { key.performClose(nil) }
        else if document != nil { closeDocument() }
        else { window?.performClose(nil) }
    }
    @objc func toggleSidebar() { layout.splitViewItems[0].isCollapsed.toggle() }
    @objc func toggleInspector() { layout.splitViewItems[2].isCollapsed.toggle() }
    @objc func fitPage() { layout.canvas.zoom=1; layout.canvas.actualPixels=false; layout.canvas.pan = .zero }
    @objc func actualSize() { layout.canvas.actualPixels=true; layout.canvas.zoom=1; layout.canvas.pan = .zero }
    @objc func zoomIn() { layout.canvas.zoom=min(8,layout.canvas.zoom*1.25) }
    @objc func zoomOut() { layout.canvas.zoom=max(0.25,layout.canvas.zoom/1.25) }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"BJC-85 Utility",.credits:NSAttributedString(string:"Independent BJC-85 / IS-12 project. No Canon endorsement.")]) }
    @objc func showHelp() { if let url=Bundle.main.url(forResource:"USER-GUIDE",withExtension:"md") { NSWorkspace.shared.open(url) } }
    @objc func showFiles() { NSWorkspace.shared.open(root) }
    @objc func openJobs() { if !fixture { JobsView.open() } }
    @objc func openImageCapture() { if !fixture { NSWorkspace.shared.open(URL(fileURLWithPath:"/System/Applications/Image Capture.app")) } }
    @objc func calibrationGuidance() { CalibrationView.sheet(reference:reference,valid:referenceValid).beginSheetModal(for:window!) { _ in } }
}
