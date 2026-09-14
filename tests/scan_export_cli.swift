import Foundation

@main enum ExportCheck {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw NSError(domain: "BJC85", code: 2, userInfo: [NSLocalizedDescriptionKey: "Usage: scan-export INPUT.png OUTPUT.png|tiff|pdf"])
        }
        try ScanExport.write(source: URL(fileURLWithPath: CommandLine.arguments[1]),
                             destination: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
