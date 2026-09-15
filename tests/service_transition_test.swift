import Foundation
final class AdmissionToken { }
@main struct ServiceTests {
    static func main() throws {
        let fm=FileManager.default, root=fm.temporaryDirectory.appendingPathComponent("bjc85-service-test-\(UUID())")
        try fm.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]); defer { try? fm.removeItem(at:root) }
        for scenario in ["busy","pending-print","active-scanner","timeout","launch-failure","ready"] {
            var commands:[String]=[]
            let service=ServiceTransitionController(command:{ path,args in
                let value=([path]+args).joined(separator:" "); commands.append(value)
                if scenario=="timeout" && path.contains("curl") { throw CocoaError(.fileReadUnknown) }
                if scenario=="launch-failure" && args.first=="bootstrap" { return .init(code:1,output:"fixture launch failure") }
                if path.hasSuffix("lpstat") { return .init(code:0,output:args.contains("-v") ? "device for BJC85_Native: ipp://localhost:8631/ipp/print" : scenario=="pending-print" ? "BJC85_Native-12 owner 1024" : "") }
                if path.hasSuffix("curl") { return .init(code:scenario=="active-scanner" ? 22 : 0,output:args.last?.contains("utility/idle") == true ? "idle" : "ready") }
                return .init(code:0,output:"")
            },admission:{ AdmissionToken() },availability:{ _ in scenario=="busy" ? .busy : .available },agentsDirectory:root.appendingPathComponent(scenario),wait:{ _ in })
            do {
                try service.preparePrinter(bundle:root,runtime:root)
                precondition(scenario=="ready")
                precondition(commands.contains { $0.contains("bootstrap") } && commands.contains { $0.contains("lpadmin") })
            } catch {
                precondition(scenario != "ready")
                if ["busy","pending-print","active-scanner","timeout"].contains(scenario) { precondition(!commands.contains { $0.contains("bootout") || $0.contains("lpadmin") }) }
            }
        }
        let canonical="ipp://localhost:8631/ipp/print"
        for uri in [canonical+"-unrelated",canonical+"?x",canonical+"#x",canonical+"/", "ipp://localhost:8632/ipp/print", "ipp://localhost.invalid:8631/ipp/print", "ipp://127.0.0.1:8631/ipp/print", "ipps://localhost:8631/ipp/print", "ipp://user@localhost:8631/ipp/print", "ipp://localhost:8631/ipp/%70rint",canonical+"\ndevice for BJC85_Native: "+canonical] {
            var mutations=0
            let controller=ServiceTransitionController(command:{ path,args in
                if path.hasSuffix("lpstat") { return .init(code:0,output:"device for BJC85_Native: "+uri+"\n") }
                mutations += 1; return .init(code:0,output:"")
            },admission:{ AdmissionToken() },availability:{ _ in .available },agentsDirectory:root,wait:{ _ in })
            do { try controller.preparePrinter(bundle:root,runtime:root); preconditionFailure() } catch { }
            precondition(mutations==0)
        }
        for final in ["changed","inspection-error","busy","absent"] {
            var inspections=0, reconfigured=0
            let controller=ServiceTransitionController(command:{ path,args in
                if path.hasSuffix("lpstat") && args.first=="-v" {
                    inspections += 1
                    if inspections>1 {
                        if final=="inspection-error" { return .init(code:1,output:"fixture inspection failed") }
                        if final=="absent" { return .init(code:1,output:"lpstat: Unknown destination \"BJC85_Native\".") }
                    }
                    return .init(code:0,output:"device for BJC85_Native: "+canonical+(inspections>1 && final=="changed" ? "-foreign" : ""))
                }
                if path.hasSuffix("lpstat") { return .init(code:0,output:inspections>1 && final=="busy" ? "fixture job" : "") }
                if path.hasSuffix("lpadmin") { reconfigured += 1 }
                if path.hasSuffix("launchctl") && args.first=="print" { return .init(code:1,output:"") }
                return .init(code:0,output:"")
            },admission:{ AdmissionToken() },availability:{ _ in .available },agentsDirectory:root.appendingPathComponent(final),wait:{ _ in })
            do { try controller.preparePrinter(bundle:root,runtime:root); precondition(final=="absent") }
            catch { precondition(final != "absent") }
            precondition(reconfigured == (final=="absent" ? 1 : 0))
        }
        print("PASS APP-03: exact ownership, deceptive components, no initial mutations, changed ownership/errors/busy final boundary, known absent queue")
        do { try ServiceController.preparePrinter(bundle:root,runtime:root); preconditionFailure("offline test reached production services") } catch { }
        print("PASS: actual ServiceTransitionController busy lease, another queued job, active scanner, status timeout, bootstrap failure, successful isolated transition; production adapter rejects offline tests.")
    }
}
