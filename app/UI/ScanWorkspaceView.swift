import AppKit
// The selection is normalized in the displayed image's top-left coordinate space.
// Source crop uses those same edges, independent of fit size, dpi, or zoom.
final class ScanWorkspaceView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var region = ScanRegion.fullPage { didSet { needsDisplay = true; changed?(region) } }
    var changed: ((ScanRegion) -> Void)?
    var zoom = 1.0 { didSet { needsDisplay = true } }
    private var anchor: CGPoint?, original: ScanRegion?, moving = false
    override var acceptsFirstResponder: Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric,height: NSView.noIntrinsicMetric) }
    override func accessibilityLabel() -> String? { L("Scanned page and crop selection") }
    override func accessibilityValue() -> Any? {
        LF("Crop: %.2f, %.2f inches; %.2f × %.2f inches",region.x*8,region.y*10.8,region.width*8,region.height*10.8)
    }
    override func accessibilityHelp() -> String? { L("Drag to select or move a region. Arrow keys move it; Shift moves ten pixels. Clear Selection restores the page.") }
    private var page: CGRect {
        let size = image?.size ?? NSSize(width: 8,height: 10.8)
        let scale = max(0.01,min((bounds.width-44)/size.width,(bounds.height-44)/size.height))*zoom
        return CGRect(x: (bounds.width-size.width*scale)/2,y: (bounds.height-size.height*scale)/2,width: size.width*scale,height: size.height*scale)
    }
    private func display(_ selection: ScanRegion) -> CGRect {
        CGRect(x: page.minX+selection.x*page.width,y: page.maxY-(selection.y+selection.height)*page.height,
               width: selection.width*page.width,height: selection.height*page.height)
    }
    private func normalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(1,max(0,(point.x-page.minX)/page.width)),y:min(1,max(0,(page.maxY-point.y)/page.height)))
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); bounds.fill()
        NSColor.white.setFill(); page.fill()
        if let image { image.draw(in:page) }
        else {
            let label = L("Your page appears here\nPrescan to select a region")
            let style = NSMutableParagraphStyle(); style.alignment = .center
            label.draw(in: CGRect(x: page.minX+12,y: page.midY-25,width: page.width-24,height:60),
                       withAttributes: [.font:NSFont.systemFont(ofSize:15),.foregroundColor:NSColor.secondaryLabelColor,.paragraphStyle:style])
        }
        if region != .fullPage {
            let rect = display(region)
            let shade = NSBezierPath(rect:page); shade.appendRect(rect); shade.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.22).setFill(); shade.fill()
            NSColor.white.setStroke(); let border = NSBezierPath(rect:rect); border.lineWidth = 4; border.stroke()
            NSColor.controlAccentColor.setStroke(); border.lineWidth = 2; border.stroke()
            for p in [CGPoint(x:rect.minX,y:rect.minY),CGPoint(x:rect.maxX,y:rect.minY),CGPoint(x:rect.minX,y:rect.maxY),CGPoint(x:rect.maxX,y:rect.maxY)] {
                NSColor.controlAccentColor.setFill(); CGRect(x:p.x-4,y:p.y-4,width:8,height:8).fill()
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow,from:nil)
        guard page.contains(point), image != nil else { return }
        anchor = normalized(point); original = region
        let rect = display(region)
        moving = region != .fullPage && rect.insetBy(dx:12,dy:12).contains(point)
        if region != .fullPage && !moving && rect.insetBy(dx:-12,dy:-12).contains(point) {
            anchor = CGPoint(x:point.x<rect.midX ? region.x+region.width : region.x,
                             y:point.y>rect.midY ? region.y+region.height : region.y)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor, let original else { return }
        let point = normalized(convert(event.locationInWindow,from:nil))
        if moving { var next=original; next.nudge(dx:point.x-anchor.x,dy:point.y-anchor.y); region=next }
        else {
            let next = ScanRegion(x:min(anchor.x,point.x),y:min(anchor.y,point.y),width:abs(point.x-anchor.x),height:abs(point.y-anchor.y))
            if next.width>=1.0/2880 && next.height>=1.0/3888 { region=next }
        }
    }
    override func mouseUp(with event: NSEvent) { anchor=nil; original=nil }
    override func keyDown(with event: NSEvent) {
        let step = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
        switch event.keyCode {
        case 123: region.nudge(dx:-step/2880,dy:0)
        case 124: region.nudge(dx:step/2880,dy:0)
        case 125: region.nudge(dx:0,dy:step/3888)
        case 126: region.nudge(dx:0,dy:-step/3888)
        default: super.keyDown(with:event)
        }
    }
}
