import AppKit
import ImageIO

@main @MainActor struct WorkerTests {
    static func main() throws {
        let fm=FileManager.default, root=fm.temporaryDirectory.appendingPathComponent("bjc85-worker-\(UUID())")
        try fm.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]); defer { try? fm.removeItem(at:root) }
        let source=URL(fileURLWithPath:CommandLine.arguments.last!)
        let store=try ScanDocumentStore(runtime:root.appendingPathComponent("runtime"))
        var document=try store.importImage(source)
        document.edits.adjustments.filter = .sharpen; document.revision=1; try store.save(document)
        let snapshot=try store.snapshot(document), service=ImageProcessingService(), ticket=ProcessingTicket()
        let output=root.appendingPathComponent("retained.tiff")
        var completed=false, failure:Error?, receipt:DocumentExport?
        let start=DispatchTime.now().uptimeNanoseconds
        var ticks=0, last=start, maxGap:UInt64=0
        let timer=DispatchSource.makeTimerSource(queue:.main)
        timer.schedule(deadline:.now(),repeating:0.02)
        timer.setEventHandler { let time=DispatchTime.now().uptimeNanoseconds; maxGap=max(maxGap,time-last);last=time;ticks += 1 }
        timer.resume()
        service.export(snapshot,to:output,runtime:store.runtime,ticket:ticket) { result in
            do { receipt=try result.get() } catch { failure=error }; completed=true
        }
        document.edits.adjustments.brightness=0.2; document.revision=2
        let obsolete=ProcessingTicket(); service.preview(try store.snapshot(document),ticket:obsolete) { _ in }; obsolete.cancel()
        let deadline=Date().addingTimeInterval(120)
        while !completed && Date()<deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
        timer.cancel()
        if let failure { throw failure }
        precondition(completed && receipt?.revision==1 && document.revision==2 && fm.isReadableFile(atPath:output.path))
        precondition(ticks>1,"Main run loop was starved by processing")
        let elapsed=Double(DispatchTime.now().uptimeNanoseconds-start)/1e9
        print("MEASURED full-resolution sharpen + TIFF export: \(String(format:"%.3f",elapsed)) seconds; main-run-loop ticks: \(ticks); maximum heartbeat gap: \(String(format:"%.3f",Double(maxGap)/1e6)) ms")
        print("PASS: off-main processing assertion, immutable committed export revision despite edit/obsolete preview cancellation, source pin retained through completion.")
        // Measure the most expensive enabled spatial filter on the full image.
        var slow=snapshot.document; slow.edits.adjustments.filter = .despeckle
        let slowSnapshot=try store.snapshot(slow), slowTicket=ProcessingTicket()
        var slowDone=false, slowSeconds=0.0
        service.perform(work: {
            let begin=DispatchTime.now().uptimeNanoseconds
            let image=try ImageProcessingService.render(slowSnapshot,ticket:slowTicket)
            precondition(image.width==snapshot.document.acquisition.width && image.height==snapshot.document.acquisition.height)
            return Double(DispatchTime.now().uptimeNanoseconds-begin)/1e9
        }) { result in do { slowSeconds=try result.get() } catch { failure=error }; slowDone=true }
        while !slowDone && Date()<deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
        if let failure { throw failure }; precondition(slowDone)
        print("MEASURED full-resolution decode + despeckle: \(String(format:"%.3f",slowSeconds)) seconds")
    }
}
