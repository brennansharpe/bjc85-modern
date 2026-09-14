import AppKit

#if !BJC85_TESTING
@main
#endif
@MainActor
final class ScannerApp: NSObject, NSApplicationDelegate {
    private var controller: UtilityWindowController?
    static func main() {
        let app = NSApplication.shared, delegate = ScannerApp()
        app.delegate = delegate; app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = UtilityWindowController()
        controller?.showWindow(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller else { return .terminateNow }
        return controller.prepareToQuit()
    }
}
