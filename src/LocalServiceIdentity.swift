import Foundation
import Darwin
/// Random per-installation identity: stable across restarts, no hardware serial.
enum LocalServiceIdentity {
    static func load(root: URL) throws -> UUID {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let file=root.appendingPathComponent("service-identity")
        let fd=open(file.path,O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard fd>=0 else { throw CocoaError(.fileReadNoPermission) }
        defer { close(fd) }
        guard flock(fd,LOCK_EX)==0 else { throw CocoaError(.fileReadNoPermission) }
        defer { flock(fd,LOCK_UN) }
        var info=stat()
        guard fstat(fd,&info)==0, info.st_uid==getuid(), info.st_nlink==1, info.st_mode & 0o077 == 0 else { throw CocoaError(.fileReadNoPermission) }
        if info.st_size>0 {
            var bytes=[UInt8](repeating:0,count:64)
            let count=read(fd,&bytes,64)
            guard count>0, let id=UUID(uuidString:String(decoding:bytes.prefix(count),as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)) else { throw CocoaError(.fileReadCorruptFile) }
            return id
        }
        let id=UUID(), data=Data((id.uuidString+"\n").utf8)
        let count=data.withUnsafeBytes { write(fd,$0.baseAddress,data.count) }
        guard count==data.count, fsync(fd)==0 else { throw CocoaError(.fileWriteUnknown) }
        return id
    }
}
