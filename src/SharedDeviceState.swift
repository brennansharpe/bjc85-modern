import Foundation
import Darwin
enum SharedDeviceState {
    enum State { case available, busy, recoveryRequired }
    private static func markerExists(_ path: String) -> Bool {
        var info=stat()
        // lstat also sees a broken symlink; permission/read errors fail closed.
        return lstat(path,&info) == 0 || errno != ENOENT
    }
    static func inspect(_ root: URL) -> State {
        let marker=root.appendingPathComponent("recovery-required.json")
        guard markerExists(marker.path) else { return .available }
        let descriptor=open("/tmp/bjc85-usb-\(getuid()).lock",O_RDWR|O_NOFOLLOW|O_CLOEXEC)
        guard descriptor>=0 else { return .recoveryRequired }
        defer { close(descriptor) }
        if flock(descriptor,LOCK_EX|LOCK_NB) != 0 { return errno == EWOULDBLOCK ? .busy : .recoveryRequired }
        defer { flock(descriptor,LOCK_UN) }
        return markerExists(marker.path) ? .recoveryRequired : .available
    }
}
