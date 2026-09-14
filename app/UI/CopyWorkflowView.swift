import AppKit
final class CopyWorkflowView: NSStackView {
    let copy=NSButton(title:L("Copy loaded original"),target:nil,action:nil)
    let reprint=NSButton(title:L("Reprint retained image"),target:nil,action:nil)
    let reset=NSButton(title:L("Reset copy session"),target:nil,action:nil)
    let swap=NSButton(title:L("Continue after cartridge swap…"),target:nil,action:nil)
    let information=RootView.label(L("Scan with IS-12 → retain image → replace cartridge → print. Reprint uses the retained image without another scan."))
    let settings=PrintSettingsView()
    let brightness=NSSlider(value:0,minValue:-1,maxValue:1,target:nil,action:nil)
    init() { super.init(frame:.zero); orientation = .vertical; alignment = .leading; spacing=12
        brightness.setAccessibilityLabel(L("Copy brightness"))
        for view in [information,settings,RootView.label(L("Copy brightness")),brightness,copy,swap,reprint,reset] { addArrangedSubview(view) }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
}
