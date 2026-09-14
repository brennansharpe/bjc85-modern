import AppKit
@MainActor enum ScanSettingsView {
    static func slider(label: String,minimum: Double,maximum: Double,value: Double,target: AnyObject,action: Selector) -> NSSlider {
        let slider=NSSlider(value:value,minValue:minimum,maxValue:maximum,target:target,action:action)
        slider.setAccessibilityLabel(label); slider.isContinuous=false
        return slider
    }
}
