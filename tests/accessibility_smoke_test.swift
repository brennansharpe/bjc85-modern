import AppKit
@main @MainActor struct AccessibilityTests {
    static func main() {
        _=NSApplication.shared
        let preview=ScanWorkspaceView(frame:NSRect(x:0,y:0,width:600,height:700))
        precondition(preview.acceptsFirstResponder && preview.accessibilityLabel() != nil)
        precondition(preview.isAccessibilityElement() && preview.accessibilityRole() == .image)
        precondition((preview.accessibilityValue() as? String)?.contains("No document") == true)
        preview.image=NSImage(size:NSSize(width:2880,height:3888))
        precondition(preview.accessibilityHelp()!.contains("Arrow"))
        preview.region=ScanRegion(x:0.1,y:0.1,width:0.5,height:0.5)
        precondition((preview.accessibilityValue() as? String)?.contains("Crop") == true)
        precondition(preview.clipsToBounds, "A zoomed page must not draw into surrounding controls")
        precondition((preview.accessibilityValue() as? String)?.contains("Fit Page") == true)
        preview.actualPixels=true
        precondition(preview.accessibilityHelp()!.contains("pan"))
        precondition((preview.accessibilityValue() as? String)?.contains("100 percent") == true)
        let printView=PrintSettingsView(); precondition(printView.paper.accessibilityLabel()=="Print paper size")
        let copy=CopyWorkflowView(); precondition(copy.reprint.title.contains("Reprint"))
        let window=UtilityWindow(contentRect:NSRect(x:0,y:0,width:320,height:200),styleMask:[.titled],backing:.buffered,defer:false)
        let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:320,height:200))
        let body=FlippedView(frame:NSRect(x:0,y:0,width:300,height:1200))
        let control=NSSlider(frame:NSRect(x:20,y:1000,width:200,height:24))
        body.addSubview(control); scroll.documentView=body; window.contentView=scroll
        precondition(!body.visibleRect.intersects(control.frame))
        precondition(window.makeFirstResponder(control))
        precondition(body.visibleRect.contains(control.frame), "Keyboard focus must scroll an offscreen inspector control into view")
        print("Constructed views expose crop values, keyboard focus and labelled controls. VoiceOver acceptance is separate.")
    }
}
