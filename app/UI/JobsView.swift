import AppKit
enum JobsView {
    static func open() { NSWorkspace.shared.open(URL(string:"http://localhost:8631/")!) }
}
