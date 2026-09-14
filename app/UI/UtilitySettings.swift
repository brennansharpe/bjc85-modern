import AppKit

extension UtilityWindowController {
    @objc func showSettings() {
        if let settingsWindow { settingsWindow.showWindow(nil); return }
        let panel=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:340),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        panel.title="Settings"; panel.center()
        let retain=NSButton(checkboxWithTitle:"Retain diagnostic captures",target:self,action:#selector(retentionChanged(_:)))
        retain.state=model.retainDiagnosticCaptures ? .on : .off
        let content=RootView.column([title("Privacy & storage"),retain,
            RootView.label("Completed captures are expendable after their document master is retained. Unexported documents, Copy images, active workers, and unresolved recovery evidence are protected."),
            RootView.label("Closed, exported documents may expire after 7 days. Unexported documents stay until you discard them. Storage is limited to 100 documents / 2 GB; new imports stop at the limit."),
            button("Delete completed diagnostics…",#selector(deleteDiagnostics)),button("Show private files",#selector(showFiles))],spacing:16)
        content.translatesAutoresizingMaskIntoConstraints=false; panel.contentView!.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo:panel.contentView!.leadingAnchor,constant:24),content.trailingAnchor.constraint(equalTo:panel.contentView!.trailingAnchor,constant:-24),content.topAnchor.constraint(equalTo:panel.contentView!.topAnchor,constant:24)])
        for child in content.arrangedSubviews where child is NSTextField { child.widthAnchor.constraint(equalTo:content.widthAnchor).isActive=true }
        settingsWindow=NSWindowController(window:panel); settingsWindow?.showWindow(nil)
    }
    @objc func retentionChanged(_ sender:NSButton) {
        let retained=sender.state == .on, flag=root.appendingPathComponent("retain-diagnostics")
        processing.perform(work: {
            if retained { try Data().write(to:flag,options:.atomic); try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:flag.path) }
            else if FileManager.default.fileExists(atPath:flag.path) { try FileManager.default.removeItem(at:flag) }
        }) { [weak self] result in
            guard let self else { return }; do { try result.get(); self.model.retainDiagnosticCaptures=retained } catch { sender.state=self.model.retainDiagnosticCaptures ? .on : .off; self.report(error) }
        }
    }
    @objc func deleteDiagnostics() {
        guard !busy, !documentBusy, let store else { layout.status.stringValue="Wait for the active operation before deleting diagnostics."; return }
        let alert=NSAlert(); alert.messageText="Delete completed diagnostic captures?"
        alert.informativeText="Retained documents, exports, calibration, Copy, and recovery evidence are preserved. Legacy captures without an imported document receipt are also preserved."
        alert.addButton(withTitle:"Cancel"); alert.addButton(withTitle:"Delete Diagnostics")
        alert.beginSheetModal(for:settingsWindow?.window ?? window!) { [weak self] response in
            guard response == .alertSecondButtonReturn, let self else { return }
            let root=self.root, state=self.state
            self.processing.perform(work: {
                // Fail closed on global recovery. No recursive directory deletion.
                guard !FileManager.default.fileExists(atPath:root.appendingPathComponent("recovery-required.json").path) else { throw DocumentError.busy }
                for directory in try FileManager.default.contentsOfDirectory(at:state,includingPropertiesForKeys:nil) where directory.lastPathComponent.hasPrefix("scan-") {
                    guard FileManager.default.fileExists(atPath:directory.appendingPathComponent("document-imported").path),
                          let data=try? Data(contentsOf:directory.appendingPathComponent("outcome.json")),
                          let values=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
                          let name=values["outcome"] as? String, let outcome=OperationOutcome(rawValue:name) else { continue }
                    try PrivacyRetention.removeExportedCapture(directory,retainDiagnostics:false,outcome:outcome,protected:[store.directory])
                }
                try store.purgeExportedClosed()
            }) { [weak self] result in
                do { try result.get(); self?.layout.status.stringValue="Completed diagnostics deleted. The current document is retained." } catch { self?.report(error) }
            }
        }
    }
}
