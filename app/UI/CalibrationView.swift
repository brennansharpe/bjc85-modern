import AppKit
enum CalibrationView {
    static func sheet(reference: URL?,valid: Bool? = nil) -> NSAlert {
        let alert=NSAlert(); alert.messageText=L("White-Level Calibration")
        var information=L("Load one clean, blank white sheet. The IS-12 measures it to correct sensor shading. This is an experimental plain-paper reference; it does not establish Canon-reference colour accuracy.")
        if let reference {
            information += valid == true ? L("\n\nSerial, head and temperature validation passed at the last connection.") :
                valid == false ? L("\n\nThe reference did not pass current device/temperature validation. Recalibration is required.") : L("\n\nConnect the scanner to validate the saved reference.")
            let date=(try? reference.resourceValues(forKeys:[.contentModificationDateKey]))?.contentModificationDate
            information += LF("\n\nSaved reference: %@. Serial, head and temperature are checked by the native helper before paper is fed.",date?.formatted(date:.abbreviated,time:.shortened) ?? L("date unknown"))
        } else { information += L("\n\nNo reference has been saved.") }
        alert.informativeText=information; alert.addButton(withTitle:L("Calibrate loaded sheet")); alert.addButton(withTitle:L("Cancel"))
        return alert
    }
}
