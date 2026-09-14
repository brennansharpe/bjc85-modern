import AppKit
@MainActor enum JobsView {
    static func open() {
        let center=URL(fileURLWithPath:"/System/Applications/Utilities/Print Center.app")
        if FileManager.default.fileExists(atPath:center.path) { NSWorkspace.shared.open(center) }
        else { NSWorkspace.shared.open(URL(string:"http://localhost:631/jobs/")!) }
    }
}
