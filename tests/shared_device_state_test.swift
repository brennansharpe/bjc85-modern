import Foundation
import Darwin
@main struct SharedTests {
    static func main() throws {
        let fm=FileManager.default, root=fm.temporaryDirectory.appendingPathComponent("bjc85-lock-test-\(UUID())")
        try fm.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]); defer { try? fm.removeItem(at:root) }
        let lease=root.appendingPathComponent("usb.lock").path, admission=root.appendingPathComponent("admission.lock").path
        func inspect() -> SharedDeviceState.State { SharedDeviceState.inspect(root,leasePath:lease,admissionPath:admission) }
        precondition(inspect() == .available)
        let fd=open(lease,O_RDWR); precondition(fd>=0); defer { close(fd) }
        precondition(flock(fd,LOCK_EX|LOCK_NB)==0); precondition(inspect() == .busy)
        let marker=root.appendingPathComponent("recovery-required.json")
        try Data("malformed".utf8).write(to:marker); precondition(inspect() == .busy)
        flock(fd,LOCK_UN); precondition(inspect() == .recoveryRequired)
        try fm.removeItem(at:marker); precondition(inspect() == .available)
        try fm.createSymbolicLink(at:marker,withDestinationURL:root.appendingPathComponent("missing")); precondition(inspect() == .recoveryRequired); try fm.removeItem(at:marker)
        var job:DeviceAdmission?=try DeviceAdmission(exclusive:false,path:admission)
        precondition(inspect() == .busy)
        do { _=try DeviceAdmission(exclusive:true,path:admission); preconditionFailure() } catch { }
        withExtendedLifetime(job) {}; job=nil; precondition(inspect() == .available)
        var transition:DeviceAdmission?=try DeviceAdmission(exclusive:true,path:admission)
        do { _=try DeviceAdmission(exclusive:false,path:admission); preconditionFailure() } catch { }
        withExtendedLifetime(transition) {}; transition=nil; precondition(inspect() == .available)
        try fm.setAttributes([.posixPermissions:0o644],ofItemAtPath:lease); precondition(inspect() == .recoveryRequired)
        try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:lease)
        let id=try LocalServiceIdentity.load(root:root), again=try LocalServiceIdentity.load(root:root); precondition(id==again)
        let other=try LocalServiceIdentity.load(root:root.appendingPathComponent("other")); precondition(id != other)
        print("PASS: lease contention without/with marker, marker finalization and malformed/symlink fail-closed, permissions, competing job/transition admission and release, stable private per-install identity.")
    }
}
