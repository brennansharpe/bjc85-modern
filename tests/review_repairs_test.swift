import AppKit
import ImageIO

final class ReviewQueue: PrintQueueAccess {
    var calls=0
    var fail=false
    var accepted: (() -> Void)?
    func submit(_ image:URL,settings:PrintSettings) throws -> Int {
        calls += 1; accepted?(); if fail { throw CocoaError(.fileReadUnknown) }; return 19
    }
    func query(destination:String,id:Int) throws -> QueueJobStatus { .init(result:.unknown,reasons:["fixture history absent"]) }
    func cancel(destination:String,id:Int) throws { }
}
final class ReviewFault { var stage:String?; var enabled=true }
final class ReviewScannerServices: ScannerServices {
    func quiesce(completion:@escaping @MainActor @Sendable (Result<Void,Error>)->Void) { completion(.success(())) }
}
final class ReviewScannerRunner: ScannerProcess {
    var launches=0
    var beforeLaunch:() -> Void = {}
    func launch(arguments:[String],log:URL,receive:@escaping @MainActor @Sendable (Data)->Void,completion:@escaping @MainActor @Sendable (Int32,Bool)->Void) throws { beforeLaunch(); launches += 1; completion(0,false) }
    func cancel() {}
}
@main @MainActor struct ReviewRepairs {
    static func main() throws {
        let fm=FileManager.default, root=fm.temporaryDirectory.appendingPathComponent("review-repairs-\(UUID())")
        try fm.createDirectory(at:root,withIntermediateDirectories:true); defer { try? fm.removeItem(at:root) }
        for stage in ["beforeWrite","afterReplace","afterAttributes","afterSync"] {
            let fault=ReviewFault(); fault.stage=stage
            let storage=DiskReceiptStorage(checkpoint:{ point in if fault.enabled && point==fault.stage { throw CocoaError(.fileWriteUnknown) } })
            let queue=ReviewQueue(), file=root.appendingPathComponent(stage+".json")
            let tracker=try PrintJobTracker(file:file,queue:queue,storage:storage)
            do { _=try tracker.submit(root,settings:.init(),document:nil,copy:false,attempt:UUID()); preconditionFailure() } catch { }
            precondition(queue.calls==0 && tracker.record==nil && !fm.fileExists(atPath:file.path))
            fault.enabled=false
            let job=try tracker.submit(root,settings:.init(),document:nil,copy:false,attempt:UUID())
            precondition(queue.calls==1 && job.result == .pending)
            let restarted=try PrintJobTracker(file:file,queue:queue)
            do { _=try restarted.submit(root,settings:.init(),document:nil,copy:false,attempt:UUID()); preconditionFailure() } catch { }
            precondition(queue.calls==1)
        }
        let missing=root.appendingPathComponent("missing/receipt.json"), q=ReviewQueue()
        let same=try PrintJobTracker(file:missing,queue:q)
        do { _=try same.submit(root,settings:.init(),document:nil,copy:false,attempt:UUID()); preconditionFailure() } catch { }
        precondition(q.calls==0 && same.record==nil)
        try fm.createDirectory(at:missing.deletingLastPathComponent(),withIntermediateDirectories:true)
        _=try same.submit(root,settings:.init(),document:nil,copy:false,attempt:UUID()); precondition(q.calls==1)
        for ambiguous in [false,true] {
            let fault=ReviewFault(); fault.enabled=false; let queue=ReviewQueue(); queue.fail=ambiguous
            queue.accepted={ fault.enabled=true }
            let storage=DiskReceiptStorage(checkpoint:{ point in if fault.enabled && point=="beforeWrite" { throw CocoaError(.fileWriteUnknown) } })
            let file=root.appendingPathComponent("post-\(ambiguous).json")
            let tracker=try PrintJobTracker(file:file,queue:queue,storage:storage)
            let job=try tracker.submit(root,settings:.init(),document:nil,copy:false,attempt:UUID())
            precondition(job.outstanding && job.result == .unknown)
            fault.enabled=false
            do { _=try tracker.submit(root,settings:.init(),document:nil,copy:false,attempt:UUID()); preconditionFailure() } catch { }
            let restarted=try PrintJobTracker(file:file,queue:queue)
            precondition(restarted.record?.outstanding == true && queue.calls==1)
        }
        print("PASS APP-02: zero handoffs on four storage failures; same-instance repaired retry; restart and post-acceptance no replay")

        let source=root.appendingPathComponent("source.png")
        let bytes=Data([255,0,0,255, 0,255,0,255, 0,0,255,255, 255,255,0,255])
        let image=CGImage(width:2,height:2,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:8,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:CGDataProvider(data:bytes as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        try ScanProcessing.writePNG(image:image,dpi:90,destination:source)
        let original=try Data(contentsOf:source), runtime=root.appendingPathComponent("runtime")
        let store=try ScanDocumentStore(runtime:runtime,documentLimit:2,byteLimit:100_000)
        let healthy=try store.importImage(source), second=try store.importImage(source)
        do { _=try store.importImage(source); preconditionFailure() } catch DocumentError.quota { }
        let captures=runtime.appendingPathComponent(".state/scanner-app")
        try fm.createDirectory(at:captures,withIntermediateDirectories:true)
        let captureFolder=captures.appendingPathComponent("scan-fixture")
        try fm.createDirectory(at:captureFolder,withIntermediateDirectories:true)
        try original.write(to:captureFolder.appendingPathComponent("scan-raw.png"))
        try JSONSerialization.data(withJSONObject:["schema_version":1,"outcome":"completedSafe","image_complete":true]).write(to:captureFolder.appendingPathComponent("outcome.json"))
        let facts=ScanAcquisition(acquired:Date(timeIntervalSince1970:10),dpi:90,width:2,height:2,source:"Fixture prescan",mode:"colour",whiteReference:nil)
        let edits=DocumentEdits(rotation:0,region:ScanRegion(x:0,y:0,width:0.5,height:1),adjustments:ScanAdjustments(brightness:0.1),imageType:.grayscale,threshold:110)
        let intent=CaptureIntent(schema:1,documentID:UUID(),copyAttempt:nil,capture:ScanCapture(acquisition:facts,edits:edits,prescan:true))
        try DiskReceiptStorage().replace(try JSONEncoder().encode(intent),at:CaptureIntent.file(for:captureFolder))
        try store.recoverCompletedCaptures()
        let healthyCount=try store.all().count
        precondition(healthyCount==2 && store.recoveryWarnings.count==1)
        precondition(tryData(captureFolder.appendingPathComponent("scan-raw.png"))==original)
        try store.discard(second.id)
        store.recoveryCheckpoint={ _ in throw CocoaError(.fileWriteUnknown) }
        try store.recoverCompletedCaptures()
        let imported=try store.load(intent.documentID)
        precondition(imported.edits==edits && imported.acquisition==facts)
        store.recoveryCheckpoint={ _ in }
        for _ in 0..<2 { let restart=try ScanDocumentStore(runtime:runtime,documentLimit:2); try restart.recoverCompletedCaptures(); let list=try restart.all(); precondition(list.count==2) }
        precondition(tryData(captureFolder.appendingPathComponent("scan-raw.png"))==original)
        try Data("broken".utf8).write(to:store.directory.appendingPathComponent("active.json"))
        try Data("broken".utf8).write(to:store.folder(imported.id).appendingPathComponent("document.json"))
        let partial=UUID(); try fm.createDirectory(at:store.folder(partial),withIntermediateDirectories:true)
        let list=try store.all(); precondition(list.map(\.id)==[healthy.id] && store.damagedEntries.count==2)
        let tiny=try ScanDocumentStore(runtime:runtime,byteLimit:1)
        do { _=try tiny.importImage(source); preconditionFailure() } catch DocumentError.quota { }
        try store.discard(healthy.id)
        precondition(tryData(source)==original)
        let runner=ReviewScannerRunner(), services=ReviewScannerServices()
        let acquisitionDirectory=captures.appendingPathComponent("scan-acquisition")
        let request=ScanOperationRequest(id:UUID(),copyAttempt:UUID(),kind:"scan",arguments:[],directory:acquisitionDirectory,log:captures.appendingPathComponent("fixture.log"),capture:ScanCapture(acquisition:facts,edits:edits,prescan:true))
        let refusedController=ScanOperationController(services:services,runner:runner,persistIntent:{ _ in throw CocoaError(.fileWriteUnknown) })
        precondition(refusedController.start(request)); precondition(runner.launches==0)
        runner.beforeLaunch={
            precondition(!fm.fileExists(atPath:acquisitionDirectory.path))
            let persisted=try! JSONDecoder().decode(CaptureIntent.self,from:Data(contentsOf:CaptureIntent.file(for:acquisitionDirectory)))
            precondition(persisted.documentID==request.id && persisted.copyAttempt==request.copyAttempt && persisted.capture.edits==edits && persisted.capture.prescan)
        }
        let safeController=ScanOperationController(services:services,runner:runner)
        precondition(safeController.start(request)); precondition(runner.launches==1)
        for rotation in [0,2] {
            let recoveredStore=try ScanDocumentStore(runtime:root.appendingPathComponent("orientation-\(rotation)"))
            let directory=recoveredStore.runtime.appendingPathComponent(".state/scanner-app/scan-fixture")
            try fm.createDirectory(at:directory,withIntermediateDirectories:true)
            try original.write(to:directory.appendingPathComponent("scan-raw.png"))
            try JSONSerialization.data(withJSONObject:["schema_version":1,"outcome":"completedSafe","image_complete":true]).write(to:directory.appendingPathComponent("outcome.json"))
            var oriented=edits; oriented.rotation=rotation
            let metadata=CaptureIntent(schema:1,documentID:UUID(),copyAttempt:nil,capture:ScanCapture(acquisition:facts,edits:oriented,prescan:false))
            try DiskReceiptStorage().replace(try JSONEncoder().encode(metadata),at:CaptureIntent.file(for:directory))
            try recoveredStore.recoverCompletedCaptures(); try recoveredStore.recoverCompletedCaptures()
            let restored=try recoveredStore.load(metadata.documentID)
            precondition(restored.edits==oriented && tryData(directory.appendingPathComponent("scan-raw.png"))==original)
        }
        do { _=try store.importImage(source); preconditionFailure() } catch DocumentError.quota { }
        let tinyNew=try ScanDocumentStore(runtime:root.appendingPathComponent("tiny-new"),byteLimit:1)
        do { _=try tinyNew.importImage(source); preconditionFailure() } catch DocumentError.quota { }
        let tinyList=try tinyNew.all(); precondition(tinyList.isEmpty && tryData(source)==original)
        for (name,completed,intentData) in [("malformed",true,Data("{}".utf8)),("incomplete",false,try JSONEncoder().encode(intent))] {
            let invalidStore=try ScanDocumentStore(runtime:root.appendingPathComponent("invalid-"+name))
            let directory=invalidStore.runtime.appendingPathComponent(".state/scanner-app/scan-fixture")
            try fm.createDirectory(at:directory,withIntermediateDirectories:true)
            try original.write(to:directory.appendingPathComponent("scan-raw.png"))
            try JSONSerialization.data(withJSONObject:["schema_version":1,"outcome":"completedSafe","image_complete":completed]).write(to:directory.appendingPathComponent("outcome.json"))
            try intentData.write(to:CaptureIntent.file(for:directory))
            try invalidStore.recoverCompletedCaptures(); let list=try invalidStore.all()
            precondition(list.isEmpty && tryData(directory.appendingPathComponent("scan-raw.png"))==original)
        }
        print("PASS APP-01/capture intent: quota-deferred recovery, healthy listing amid corrupt/partial entries and pointer, unchanged evidence, receipt crash and two idempotent restarts")

        let copyStore=try ScanDocumentStore(runtime:root.appendingPathComponent("copy-runtime"))
        try fm.createDirectory(at:copyStore.runtime.appendingPathComponent(".state/scanner-app"),withIntermediateDirectories:true)
        let copyDoc=try copyStore.importImage(source)
        var copy=CopyWorkflow(); copy.retain(copyStore.master(copyDoc.id),document:copyDoc.id)
        for point in ["beforeSession","afterSession","afterMarker"] {
            copyStore.ownershipCheckpoint={ if $0==point { throw CocoaError(.fileWriteUnknown) } }
            do { try copyStore.commitCopy(copy) } catch { }
            copyStore.ownershipCheckpoint={ _ in }
            try copyStore.commitCopy(copy)
            for _ in 0..<2 {
                var restored=CopyWorkflow(); try restored.restoreSession(from:copyStore.runtime.appendingPathComponent(".state/scanner-app/copy-session.json"),within:copyStore.runtime)
                try copyStore.reconcileCopyOwnership(restored)
                let retained=try copyStore.load(copyDoc.id); precondition(retained.retainedCopies.contains(copyDoc.id))
            }
        }
        precondition(copy.reset()); try copyStore.commitCopy(copy)
        let released=try copyStore.load(copyDoc.id); precondition(released.retainedCopies.isEmpty)
        for destination in ["missing","overwritten","moved","inaccessible","valid","older-revision"] {
            let output=root.appendingPathComponent("export-"+destination)
            try original.write(to:output)
            if destination=="missing" { try fm.removeItem(at:output) }
            if destination=="overwritten" { try Data("replacement".utf8).write(to:output) }
            if destination=="moved" { try fm.moveItem(at:output,to:root.appendingPathComponent("moved-elsewhere")) }
            if destination=="inaccessible" { try fm.setAttributes([.posixPermissions:0],ofItemAtPath:output.path) }
            var value=released; if destination=="older-revision" { value.revision=1 }
            value.exports=[DocumentExport(destination:output,revision:0,date:Date(timeIntervalSince1970:0))]
            try copyStore.close(value,now:Date(timeIntervalSince1970:0)); try copyStore.purgeExportedClosed()
            precondition(fm.fileExists(atPath:copyStore.master(value.id).path))
        }
        try copyStore.discard(released.id)
        for boundary in ["beforeSession","afterSession","afterMarker"] {
            let legacyStore=try ScanDocumentStore(runtime:root.appendingPathComponent("legacy-"+boundary))
            let state=legacyStore.runtime.appendingPathComponent(".state/scanner-app")
            let legacyFolder=state.appendingPathComponent("copy-fixture")
            try fm.createDirectory(at:legacyFolder,withIntermediateDirectories:true)
            let pdf=legacyFolder.appendingPathComponent("copy.pdf")
            try ScanExport.write(source:source,destination:pdf)
            let pdfBytes=tryData(pdf), session=state.appendingPathComponent("copy-session.json")
            try JSONEncoder().encode(pdf).write(to:session)
            var legacy=CopyWorkflow(); try legacy.restoreSession(from:session,within:legacyStore.runtime)
            legacyStore.ownershipCheckpoint={ if $0==boundary { throw CocoaError(.fileWriteUnknown) } }
            do { _=try legacyStore.migrateLegacyCopy(legacy) } catch { }
            legacyStore.ownershipCheckpoint={ _ in }
            for _ in 0..<2 {
                var restored=CopyWorkflow(); try restored.restoreSession(from:session,within:legacyStore.runtime)
                restored=try legacyStore.migrateLegacyCopy(restored); try legacyStore.reconcileCopyOwnership(restored)
                let documents=try legacyStore.all(); precondition(documents.count==1 && restored.documentID==documents[0].id && tryData(pdf)==pdfBytes)
            }
        }
        let guardedStore=try ScanDocumentStore(runtime:root.appendingPathComponent("unknown-copy"))
        let guardedDoc=try guardedStore.importImage(source), guardedState=guardedStore.runtime.appendingPathComponent(".state/scanner-app")
        try fm.createDirectory(at:guardedState,withIntermediateDirectories:true)
        var guarded=CopyWorkflow(); guarded.retain(guardedStore.master(guardedDoc.id),document:guardedDoc.id)
        _=guarded.printerConfirmed(); let attempt=UUID(); _=guarded.beginPrint(id:attempt)
        let unknown=PrintJobRecord(attempt:attempt,document:guardedDoc.id,isCopy:true,destination:"BJC85_Native",created:Date(),jobID:19,result:.unknown,reasons:["fixture"])
        try DiskReceiptStorage().replace(try JSONEncoder().encode(unknown),at:guardedState.appendingPathComponent("print-job.json"))
        do { try guardedStore.discard(guardedDoc.id); preconditionFailure() } catch DocumentError.busy { }
        try guardedStore.commitCopy(guarded)
        for _ in 0..<2 {
            var restored=CopyWorkflow(); try restored.restoreSession(from:guardedState.appendingPathComponent("copy-session.json"),within:guardedStore.runtime)
            try guardedStore.reconcileCopyOwnership(restored); precondition(!restored.reset())
            do { try guardedStore.discard(guardedDoc.id); preconditionFailure() } catch DocumentError.busy { }
        }
        print("PASS Copy ownership/disposal: interrupted authoritative writes reconcile twice; exports never cause automatic master deletion; explicit disposal works")

        var ledger=PersistenceStatus(); let failure=CocoaError(.fileWriteUnknown)
        let a=ledger.begin("document-a"); ledger.finish(a,error:failure)
        let other=ledger.begin("export-b"); ledger.finish(other,error:nil); precondition(!ledger.isSaved)
        let retry=ledger.begin("document-a"), newer=ledger.begin("document-a")
        ledger.finish(newer,error:failure); ledger.finish(retry,error:nil); precondition(!ledger.isSaved)
        let copyTicket=ledger.begin("copy"); ledger.finish(copyTicket,error:failure)
        let repair=ledger.begin("document-a"); ledger.finish(repair,error:nil); precondition(!ledger.isSaved)
        let copyRepair=ledger.begin("copy"); ledger.finish(copyRepair,error:nil); precondition(ledger.isSaved)
        _=NSApplication.shared
        setenv("BJC85_FIXTURE_DIRECTORY",root.appendingPathComponent("ui-runtime").path,1)
        let utility=UtilityWindowController()
        func drain(_ done:() -> Bool) {
            let deadline=Date().addingTimeInterval(15)
            while !done() && Date()<deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
            precondition(done())
        }
        drain { utility.tracker != nil }
        let uiStore=utility.store!, uiDoc=try uiStore.importImage(source)
        utility.document=uiDoc
        let uiFault=ReviewFault()
        uiStore.metadataCheckpoint={ if uiFault.enabled { throw CocoaError(.fileWriteUnknown) } }
        utility.persistDocument(); drain { utility.persistence.pending.isEmpty }
        precondition(!utility.persistence.isSaved)
        utility.persistResource("unrelated") { }
        drain { utility.persistence.pending.isEmpty }; precondition(!utility.persistence.isSaved)
        var quitReply:Bool?
        utility.terminationReply={ quitReply=$0 }
        precondition(utility.prepareToQuit() == .terminateLater)
        drain { quitReply != nil }; precondition(quitReply==false)
        uiFault.enabled=false; quitReply=nil
        utility.restorationWarnings=["Historical fixture warning"]
        precondition(utility.prepareToQuit() == .terminateLater)
        drain { quitReply != nil }; precondition(quitReply==true && utility.persistence.isSaved)
        utility.document?.revision += 1; utility.persistDocument(); quitReply=nil
        precondition(utility.prepareToQuit() == .terminateLater)
        drain { quitReply != nil }; precondition(quitReply==true)
        var closed=false
        let closeObserver=NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:utility.window,queue:.main) { _ in closed=true }
        precondition(!utility.windowShouldClose(utility.window!))
        drain { closed }
        NotificationCenter.default.removeObserver(closeObserver)
        utility.window?.orderOut(nil)
        print("PASS APP-04: scoped persistence failure/retry, repeated and stale completions, unrelated export and Copy failure")

        for type in ["public.tiff","public.jpeg"] {
            let file=root.appendingPathComponent(type=="public.tiff" ? "normal.tiff" : "normal.jpg")
            let destination=CGImageDestinationCreateWithURL(file as CFURL,type as CFString,1,nil)!
            CGImageDestinationAddImage(destination,image,nil); precondition(CGImageDestinationFinalize(destination))
            let (decoded,_)=try RasterImport.decode(file); precondition(decoded.width==2 && decoded.height==2)
        }
        var decodes=0
        _=try RasterImport.decode(source,decoder:{ input in decodes += 1; return CGImageSourceCreateImageAtIndex(input,0,nil) })
        precondition(decodes==1)
        for dimensions in [(Double.nan,2.0,8.0),(0,2,8),(20_001,2,8),(20_000,20_000,16),(Double.greatestFiniteMagnitude,2,8),(2,2,32)] {
            do { try RasterImport.validate(width:dimensions.0,height:dimensions.1,depth:dimensions.2); preconditionFailure() } catch { }
        }
        let malformed=root.appendingPathComponent("bad.png"); try Data("not an image".utf8).write(to:malformed)
        do { _=try RasterImport.decode(malformed,decoder:{ _ in decodes += 1; return image }); preconditionFailure() } catch { }
        precondition(decodes==1 && tryData(source)==original)
        // A tiny PNG container advertises an oversized raster. Independent
        // header validation rejects it without relying on ImageIO metadata.
        var huge=original
        func put(_ value:UInt32,_ offset:Int) { for i in 0..<4 { huge[offset+i]=UInt8((value >> (24-8*i)) & 255) } }
        put(20_000,16); put(20_000,20)
        var crc:UInt32=0xffffffff
        for byte in huge[12..<29] { crc ^= UInt32(byte); for _ in 0..<8 { crc=(crc >> 1) ^ ((crc & 1)==1 ? 0xedb88320 : 0) } }
        put(crc ^ 0xffffffff,29)
        let hugeFile=root.appendingPathComponent("huge.png"); try huge.write(to:hugeFile)
        let header=try RasterImport.dimensions(huge,type:"public.png"); precondition(header.0==20_000)
        let rasterStore=try ScanDocumentStore(runtime:root.appendingPathComponent("raster-runtime"))
        rasterStore.decodeRaster={ try RasterImport.decode($0,decoder:{ _ in decodes += 1; return image }) }
        do { _=try rasterStore.importImage(hugeFile); preconditionFailure() } catch { }
        let empty=try rasterStore.all(); precondition(empty.isEmpty && decodes==1 && tryData(hugeFile)==huge)
        _=try RasterImport.decode(source,decoder:{ input in
            try! Data("replaced".utf8).write(to:source)
            return CGImageSourceCreateImageAtIndex(input,0,nil)
        })
        try original.write(to:source)
        print("PASS APP-05: actual raster import, metadata bounds and malformed input before decoder entry")
    }
    static func tryData(_ url:URL) -> Data { (try? Data(contentsOf:url)) ?? Data() }
}
