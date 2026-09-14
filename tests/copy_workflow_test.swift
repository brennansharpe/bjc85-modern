import Foundation
@main struct CopyTests {
    static func main() throws {
        var copy=CopyWorkflow(); let page=URL(fileURLWithPath:"/tmp/retained-page.pdf")
        precondition(copy.beginScan()); precondition(!copy.beginScan())
        copy.retain(page); precondition(copy.beginPrint()==nil)
        precondition(copy.printerConfirmed()); precondition(copy.beginPrint()==page)
        precondition(!copy.reset()); copy.completed(safely:true)
        precondition(copy.beginPrint()==page); copy.completed(safely:true)
        precondition(copy.reset() && copy.image==nil)
        precondition(copy.beginScan()); copy.scanStopped(safely:false)
        precondition(copy.stage == .recoveryRequired && !copy.reset())
        let fm=FileManager.default, root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory=root.appendingPathComponent("copy-test")
        try fm.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:root) }
        let document=directory.appendingPathComponent("copy.pdf"), session=root.appendingPathComponent("copy-session.json")
        try Data("retained completed image".utf8).write(to:document)
        var saved=CopyWorkflow(); saved.retain(document); try saved.saveSession(to:session)
        var restarted=CopyWorkflow(); try restarted.restoreSession(from:session,within:root)
        precondition(restarted.image==document && restarted.stage == .awaitingPrintCartridge)
        precondition(restarted.beginPrint()==nil)
        precondition(restarted.printerConfirmed() && restarted.beginPrint()==document)
        restarted.completed(safely:true); precondition(restarted.reset()); try restarted.saveSession(to:session)
        precondition(!fm.fileExists(atPath:session.path))
        print("Copy retains the same image across confirmed swap and reprint, with recovery preserved.")
    }
}
