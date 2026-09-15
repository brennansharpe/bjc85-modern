import Foundation
import Darwin

protocol ReceiptStorage {
    func read(_ file: URL) throws -> Data?
    func replace(_ data: Data, at file: URL) throws
    func restore(_ data: Data?, at file: URL) throws
}
/// Private atomic replacement with file and parent-directory durability.
/// Injection points exercise failures after replacement, without using hardware.
struct DiskReceiptStorage: ReceiptStorage {
    var checkpoint: (String) throws -> Void = { _ in }
    func read(_ file: URL) throws -> Data? {
        if !FileManager.default.fileExists(atPath:file.path) { return nil }
        return try Data(contentsOf:file)
    }
    private func syncDirectory(_ file: URL) throws {
        let fd=open(file.deletingLastPathComponent().path,O_RDONLY)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { Darwin.close(fd) }
        guard fsync(fd)==0 else { throw CocoaError(.fileWriteUnknown) }
    }
    func replace(_ data: Data, at file: URL) throws {
        try checkpoint("beforeWrite")
        let temp=file.deletingLastPathComponent().appendingPathComponent(".receipt-\(UUID())")
        defer { try? FileManager.default.removeItem(at:temp) }
        let fd=open(temp.path,O_WRONLY|O_CREAT|O_EXCL,0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        try handle.write(contentsOf:data); try handle.synchronize(); try handle.close()
        guard rename(temp.path,file.path)==0 else { throw CocoaError(.fileWriteUnknown) }
        try checkpoint("afterReplace")
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
        try checkpoint("afterAttributes")
        try syncDirectory(file)
        try checkpoint("afterSync")
    }
    func restore(_ data: Data?, at file: URL) throws {
        if try read(file)==data {
            // A prior restore may have replaced/removed the file but failed its
            // durability step. Equality alone is not proof of durable rollback.
            if data != nil {
                let handle=try FileHandle(forWritingTo:file)
                try handle.synchronize(); try handle.close()
            }
            if FileManager.default.fileExists(atPath:file.deletingLastPathComponent().path) { try syncDirectory(file) }
            return
        }
        if let data { try replace(data,at:file) }
        else { try FileManager.default.removeItem(at:file); try syncDirectory(file) }
        guard try read(file)==data else { throw CocoaError(.fileWriteUnknown) }
    }
}
