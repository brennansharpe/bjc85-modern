import AppKit

/// Keep keyboard focus visible when an inspector is taller than the window.
final class UtilityWindow: NSWindow {
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let accepted = super.makeFirstResponder(responder)
        if accepted, let view = responder as? NSView {
            // A text field's shared field editor has its own clip view; scroll
            // the owning control in the task inspector instead.
            let owner = (view as? NSTextView)?.delegate as? NSView
            let target = owner ?? view
            target.scrollToVisible(target.bounds.insetBy(dx:-4,dy:-4))
        }
        return accepted
    }
}

/// Native split-view chrome; document pixels are drawn by an opaque canvas.
final class WorkspaceLayout: NSSplitViewController, NSTableViewDataSource, NSTableViewDelegate {
    let navigation = NSTableView()
    let canvas = ScanWorkspaceView()
    let status = NSTextField(wrappingLabelWithString: "Open an image or connect the IS-12 to begin.")
    let device = DeviceStatusView()
    let documentTitle = NSTextField(labelWithString: "No document")
    let progress = NSProgressIndicator()
    let cancel = NSButton(title: "Cancel acquisition", target: nil, action: nil)
    let cancelExport = NSButton(title: "Cancel export", target: nil, action: nil)
    let dimensions = RootView.label("")
    let inspectorHost = NSViewController()
    private let inspectorStack = NSStackView()
    var selected: ((Int) -> Void)?
    let workspaces = ["Scan", "Print", "Copy", "Device"]
    let symbols = ["scanner", "printer", "doc.on.doc", "externaldrive.connected.to.line.below"]
    override func loadView() {
        super.loadView()
        navigation.addTableColumn(NSTableColumn(identifier: .init("workspace")))
        navigation.headerView = nil; navigation.style = .sourceList
        navigation.dataSource = self; navigation.delegate = self; navigation.rowHeight = 34
        navigation.setAccessibilityLabel("Workspaces")
        let sidebarScroll = NSScrollView(); sidebarScroll.documentView = navigation; sidebarScroll.hasVerticalScroller = true; sidebarScroll.drawsBackground = false
        let sidebar = NSViewController(); sidebar.view = sidebarScroll
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 145; sidebarItem.maximumThickness = 210
        addSplitViewItem(sidebarItem)
        let content = NSViewController(); content.view = NSView()
        documentTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        documentTitle.lineBreakMode = .byTruncatingMiddle
        status.font = .systemFont(ofSize: 12); status.isSelectable = true
        status.setAccessibilityLabel("Operation status")
        progress.style = .bar; progress.isIndeterminate = true; progress.isDisplayedWhenStopped = false
        progress.setAccessibilityLabel("Operation progress")
        cancel.isHidden = true; cancelExport.isHidden = true
        let actions = NSStackView(views: [cancel,cancelExport]); actions.orientation = .horizontal
        let header = RootView.column([device,status,progress,actions], spacing: 6)
        let footer = NSStackView(views:[documentTitle, dimensions]); footer.orientation = .vertical; footer.alignment = .leading; footer.spacing = 4
        for child in [header,canvas,footer] { child.translatesAutoresizingMaskIntoConstraints = false; content.view.addSubview(child) }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo:content.view.safeAreaLayoutGuide.leadingAnchor,constant:18),
            header.trailingAnchor.constraint(equalTo:content.view.safeAreaLayoutGuide.trailingAnchor,constant:-18),
            header.topAnchor.constraint(equalTo:content.view.safeAreaLayoutGuide.topAnchor,constant:12),
            status.widthAnchor.constraint(equalTo:header.widthAnchor),
            progress.widthAnchor.constraint(equalTo:header.widthAnchor),
            canvas.topAnchor.constraint(equalTo:header.bottomAnchor,constant:12),
            // macOS 26+ inspectors can overlay content; fit the page inside
            // the unobscured safe area rather than underneath the inspector.
            canvas.leadingAnchor.constraint(equalTo:content.view.safeAreaLayoutGuide.leadingAnchor),canvas.trailingAnchor.constraint(equalTo:content.view.safeAreaLayoutGuide.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo:footer.topAnchor,constant:-12),
            footer.leadingAnchor.constraint(equalTo:content.view.safeAreaLayoutGuide.leadingAnchor,constant:18),
            footer.trailingAnchor.constraint(equalTo:content.view.safeAreaLayoutGuide.trailingAnchor,constant:-18),
            footer.bottomAnchor.constraint(equalTo:content.view.safeAreaLayoutGuide.bottomAnchor,constant:-12)
        ])
        let contentItem = NSSplitViewItem(viewController:content)
        contentItem.minimumThickness = 320
        if #available(macOS 26.0, *) { contentItem.automaticallyAdjustsSafeAreaInsets = true }
        addSplitViewItem(contentItem)
        inspectorStack.orientation = .vertical; inspectorStack.alignment = .leading; inspectorStack.spacing = 16
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        let wrapper = FlippedView(); scroll.documentView = wrapper
        wrapper.translatesAutoresizingMaskIntoConstraints = false; inspectorStack.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(inspectorStack)
        NSLayoutConstraint.activate([
            wrapper.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),
            wrapper.topAnchor.constraint(equalTo:scroll.contentView.topAnchor),
            inspectorStack.leadingAnchor.constraint(equalTo:wrapper.leadingAnchor,constant:16),
            inspectorStack.trailingAnchor.constraint(equalTo:wrapper.trailingAnchor,constant:-16),
            inspectorStack.topAnchor.constraint(equalTo:wrapper.topAnchor,constant:16),
            inspectorStack.bottomAnchor.constraint(equalTo:wrapper.bottomAnchor,constant:-16)
        ])
        inspectorHost.view = scroll
        let inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorHost)
        inspectorItem.minimumThickness = 285; inspectorItem.maximumThickness = 360; inspectorItem.canCollapse = true
        addSplitViewItem(inspectorItem)
        navigation.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
    }
    func showInspector(_ view: NSView) {
        for child in inspectorStack.arrangedSubviews { inspectorStack.removeArrangedSubview(child); child.removeFromSuperview() }
        inspectorStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo:inspectorStack.widthAnchor).isActive = true
        self.view.window?.recalculateKeyViewLoop()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { workspaces.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView(), label = NSTextField(labelWithString: workspaces[row])
        let icon = NSImageView(image: NSImage(systemSymbolName:symbols[row],accessibilityDescription:nil) ?? NSImage())
        cell.textField=label; cell.imageView=icon
        for child in [icon,label] { child.translatesAutoresizingMaskIntoConstraints=false; cell.addSubview(child) }
        NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:6), icon.centerYAnchor.constraint(equalTo:cell.centerYAnchor),icon.widthAnchor.constraint(equalToConstant:18),
            label.leadingAnchor.constraint(equalTo:icon.trailingAnchor,constant:9),label.centerYAnchor.constraint(equalTo:cell.centerYAnchor),label.trailingAnchor.constraint(lessThanOrEqualTo:cell.trailingAnchor,constant:-4)])
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) { if navigation.selectedRow >= 0 { selected?(navigation.selectedRow) } }
}
final class FlippedView: NSView { override var isFlipped: Bool { true } }
final class InspectorSection: NSStackView {
    init(_ title: String, views: [NSView], expanded: Bool = true) {
        super.init(frame:.zero); orientation = .vertical; alignment = .leading; spacing = 9
        let body = RootView.column(views, spacing:8)
        let button = NSButton(title:"",target:nil,action:nil)
        button.setButtonType(.pushOnPushOff); button.bezelStyle = .disclosure; button.state = expanded ? .on : .off
        let heading = NSStackView(views:[button,NSTextField(labelWithString:title)])
        addArrangedSubview(heading); addArrangedSubview(body); body.isHidden = !expanded
        button.target = self; button.action = #selector(toggle(_:)); button.setAccessibilityLabel(title)
        body.widthAnchor.constraint(equalTo:widthAnchor).isActive=true
        for child in views where child is NSTextField || child is NSSlider || child is NSStackView { child.widthAnchor.constraint(equalTo:body.widthAnchor).isActive=true }
    }
    @objc private func toggle(_ sender: NSButton) { arrangedSubviews.last?.isHidden = sender.state != .on }
    required init?(coder:NSCoder) { fatalError() }
}
