import AppKit
enum MaintenanceView {
    static func panel() -> NSAlert {
        let alert=NSAlert(); alert.messageText=L("BJC-85 maintenance")
        alert.informativeText=L("Scanner status and white calibration are available from the Scan workspace.\n\nFor the printer's built-in nozzle check, follow the BJC-85 manual (printed page 55). The last physical check produced CMY with no black.\n\nNative cleaning, deep cleaning, alignment and ink-level commands remain unavailable until their protocol and hardware behaviour are verified.")
        alert.addButton(withTitle:L("Done")); return alert
    }
}
