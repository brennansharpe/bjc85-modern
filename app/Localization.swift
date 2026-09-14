import Foundation

// Keys and English (Canada) source text live in Resources/Localizable.xcstrings.
// Protocol identifiers and process arguments are deliberately separate from UI text.
func L(_ key: String) -> String { NSLocalizedString(key, bundle:.main, comment:"") }
func LF(_ key: String,_ arguments: CVarArg...) -> String {
    String(format:L(key),locale:Locale.current,arguments:arguments)
}
func dimensionFormatter() -> NumberFormatter {
    let formatter=NumberFormatter(); formatter.locale = .current; formatter.numberStyle = .decimal
    formatter.minimumFractionDigits=3; formatter.maximumFractionDigits=3
    formatter.usesGroupingSeparator=false; return formatter
}
