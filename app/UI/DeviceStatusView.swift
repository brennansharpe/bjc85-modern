import AppKit
final class DeviceStatusView: NSTextField {
    convenience init() { self.init(wrappingLabelWithString: L("Not connected")); font = .systemFont(ofSize:13,weight:.medium) }
    func show(_ state: DeviceState) { stringValue=state.label; setAccessibilityValue(state.label) }
}
