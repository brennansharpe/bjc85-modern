import Foundation
import Darwin

/// Separate admission lock: services/helpers take shared ownership for a whole
/// job; transitions take exclusive ownership. Never hold the USB lock while
/// waiting for a child that needs USB. Lock order is admission, then USB.
final class DeviceAdmission {
    private let descriptor: Int32
    static var path: String {
        if ProcessInfo.processInfo.environment["BJC85_OFFLINE_TEST"] == "1", let p = ProcessInfo.processInfo.environment["BJC85_ADMISSION_PATH"] { return p }
        return "/tmp/bjc85-admission-\(getuid()).lock"
    }
    init(exclusive: Bool, path: String = DeviceAdmission.path) throws {
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(.EACCES) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_nlink == 1, info.st_mode & 0o077 == 0 else { close(fd); throw POSIXError(.EACCES) }
        guard flock(fd, (exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB) == 0 else { let e = errno; close(fd); throw POSIXError(POSIXErrorCode(rawValue:e) ?? .EACCES) }
        descriptor = fd
    }
    deinit { close(descriptor) }
}
enum SharedDeviceState {
    enum State: Sendable { case available, busy, recoveryRequired }
    static var leasePath: String {
        if ProcessInfo.processInfo.environment["BJC85_OFFLINE_TEST"] == "1", let p = ProcessInfo.processInfo.environment["BJC85_USB_LEASE_PATH"] { return p }
        return "/tmp/bjc85-usb-\(getuid()).lock"
    }
    static func inspect(_ root: URL, leasePath: String = SharedDeviceState.leasePath, admissionPath: String = DeviceAdmission.path) -> State {
        // An admission error is never reported as availability. Holding this
        // lock makes marker inspection consistent with native finalization.
        let admission: DeviceAdmission
        do { admission = try DeviceAdmission(exclusive:true, path:admissionPath) }
        catch let error as POSIXError { return error.code == .EWOULDBLOCK ? .busy : .recoveryRequired }
        catch { return .recoveryRequired }
        return withExtendedLifetime(admission) { inspectUSB(root, leasePath:leasePath) }
    }
    /// Caller owns exclusive admission during a service transition.
    static func inspectUSB(_ root: URL, leasePath: String = SharedDeviceState.leasePath) -> State {
        let fd = open(leasePath, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return .recoveryRequired }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd,&info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_nlink == 1, info.st_mode & 0o077 == 0 else { return .recoveryRequired }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 { return errno == EWOULDBLOCK ? .busy : .recoveryRequired }
        defer { flock(fd,LOCK_UN) }
        // All records, including malformed/empty/symlinked records, block reuse.
        // Root permission errors fail closed, even if a marker cannot be read.
        var rootInfo = stat()
        guard lstat(root.path,&rootInfo) == 0, rootInfo.st_mode & S_IFMT == S_IFDIR,
              rootInfo.st_uid == getuid(), rootInfo.st_mode & 0o077 == 0 else { return .recoveryRequired }
        for name in ["recovery-required.json", ".state/print-spool/usb-recovery-required.txt"] {
            var marker = stat()
            if lstat(root.appendingPathComponent(name).path,&marker) == 0 || errno != ENOENT { return .recoveryRequired }
        }
        return .available
    }
}
