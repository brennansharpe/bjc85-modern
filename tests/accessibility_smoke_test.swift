import AppKit
@main @MainActor struct AccessibilityTests {
    static func main() {
        _=NSApplication.shared
        let preview=ScanWorkspaceView(frame:NSRect(x:0,y:0,width:600,height:700))
        precondition(preview.acceptsFirstResponder && preview.accessibilityLabel() != nil)
        precondition(preview.isAccessibilityElement() && preview.accessibilityRole() == .image)
        precondition(preview.accessibilityHelp()!.contains("Arrow"))
        preview.region=ScanRegion(x:0.1,y:0.1,width:0.5,height:0.5)
        precondition((preview.accessibilityValue() as? String)?.contains("Crop") == true)
        let printView=PrintSettingsView(); precondition(printView.paper.accessibilityLabel()=="Print paper size")
        let copy=CopyWorkflowView(); precondition(copy.reprint.title.contains("Reprint"))
        print("Constructed views expose crop values, keyboard focus and labelled controls. VoiceOver acceptance is separate.")
    }
}
