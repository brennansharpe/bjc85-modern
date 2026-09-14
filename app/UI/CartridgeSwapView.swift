import AppKit
@MainActor enum CartridgeSwapView {
    static func sheet() -> NSAlert {
        let alert=NSAlert(); alert.messageText=L("Install the print cartridge")
        alert.informativeText=L("Remove the IS-12 and install the BC-11e. Load plain paper. Continue only when the cartridge is installed and the printer is idle. Scanner discovery will stop and the native print queue will resume.")
        alert.addButton(withTitle:L("BC-11e installed — continue")); alert.addButton(withTitle:L("Cancel"))
        return alert
    }
}
