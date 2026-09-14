import AppKit
final class PrintSettingsView: NSStackView {
    let paper=NSPopUpButton(), colour=NSButton(checkboxWithTitle:L("Colour printing"),target:nil,action:nil)
    let copies=NSTextField(string:"1")
    let quality=NSPopUpButton()
    var settings: PrintSettings { PrintSettings(paper:paper.indexOfSelectedItem==1 ? "A4" : "Letter",colour:colour.state == .on,copies:Int(copies.stringValue) ?? 0,quality:quality.indexOfSelectedItem+3) }
    init() {
        super.init(frame:.zero); orientation = .vertical; alignment = .leading; spacing=10
        paper.addItems(withTitles:[L("Letter"),L("A4")]); paper.setAccessibilityLabel(L("Print paper size"))
        quality.addItems(withTitles:[L("Draft"),L("Normal"),L("High")]); quality.selectItem(at:1); quality.setAccessibilityLabel(L("Print quality"))
        colour.state = .on; copies.setAccessibilityLabel(L("Number of copies"))
        for view in [RootView.label(L("Paper size")),paper,RootView.label(L("Copies (1–999)")),copies,colour,RootView.label(L("Print quality")),quality,
                     RootView.label(L("BC-11e · plain paper · automatic feed · 360 dpi\nLetter colour is physically verified. A4, multiple copies and monochrome still need physical acceptance. The current black ink channel needs attention."))] { addArrangedSubview(view) }
        copies.widthAnchor.constraint(equalToConstant:100).isActive=true
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
}
