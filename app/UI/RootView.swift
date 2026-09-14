import AppKit
@MainActor enum RootView {
    static func column(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView(views:views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing; return stack
    }
    static func label(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString:text); field.font = .systemFont(ofSize:12); field.textColor = .secondaryLabelColor; return field
    }
}
