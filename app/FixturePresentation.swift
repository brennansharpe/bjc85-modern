import AppKit

extension UtilityWindowController {
    /// Presentation fixtures only. Native adapters independently reject fixture
    /// execution, even if a test changes a visible button or coordinator state.
    func applyFixturePresentation() {
        guard fixture else { return }
        let args=CommandLine.arguments
        if args.contains("--fixture-dark") { window?.appearance=NSAppearance(named:.darkAqua) }
        if args.contains("--fixture-small") { layout.splitViewItems[0].isCollapsed=true; window?.setContentSize(NSSize(width:760,height:570)) }
        if args.contains("--fixture-minimum"), let window { window.setFrame(NSRect(origin:window.frame.origin,size:window.minSize),display:true) }
        if args.contains("--fixture-default") { window?.setContentSize(NSSize(width:1140,height:780)) }
        if args.contains("--fixture-large") { window?.setContentSize(NSSize(width:1440,height:920)) }
        if let i=args.firstIndex(of:"--fixture-state"), i+1<args.count {
            switch args[i+1] {
            case "copy-ready", "invalid-copies":
                if let document, let store {
                    model.copy.retain(store.master(document.id),document:document.id)
                    _=model.coordinator.requestPrint(); _=model.coordinator.confirmPrintCartridge(servicePrepared:true); _=model.copy.printerConfirmed()
                    if args[i+1]=="invalid-copies" { copyControls.settings.copies.stringValue="0" }
                    layout.navigation.selectRowIndexes(IndexSet(integer:2),byExtendingSelection:false)
                }
            case "recovery": model.coordinator.requireRecovery(); layout.navigation.selectRowIndexes(IndexSet(integer:3),byExtendingSelection:false)
            case "busy": lastAvailability = .busy; layout.status.stringValue="Fixture · Another client is acquiring a page. Wait for it to finish before reconnecting."
            case "print": layout.navigation.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
            case "device": layout.navigation.selectRowIndexes(IndexSet(integer:3),byExtendingSelection:false)
            case "settings": showSettings()
            default: break
            }
        }
        if args.contains("--fixture-long-labels") { presetNote.stringValue="Fixture for expanded localized text: this acquisition preset preserves the original workflow terminology while clearly describing processing that has not been qualified on physical hardware." }
        updateControls()
    }
}
