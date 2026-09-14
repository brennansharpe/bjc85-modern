import Foundation
struct PrintSettings: Codable, Equatable, Sendable {
    var paper = "Letter", colour = true, copies = 1
    var quality = 4 // IPP enum: draft 3, normal 4, high 5.
    var isValid: Bool { ["Letter", "A4"].contains(paper) && (1...999).contains(copies) && (3...5).contains(quality) }
    func arguments(for document: URL) throws -> [String] {
        guard isValid else { throw CocoaError(.validationMissingMandatoryProperty) }
        return ["-d", "BJC85_Native", "-n", String(copies), "-o", "media=\(paper)",
                "-o", "print-color-mode=\(colour ? "color" : "monochrome")", "-o", "printer-resolution=360dpi",
                "-o", "print-quality=\(quality)", document.path]
    }
}
