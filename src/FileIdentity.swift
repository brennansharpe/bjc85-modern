import Foundation
import Darwin
/// Filesystem policy uses resolved paths AND inode identity (including hard links).
/// Managed storage is private; callers must not allow third-party mutation inside it.
enum FileIdentity {
    static func canonical(_ url: URL) -> URL {
        // Foundation leaves a symlinked parent unresolved when the final file
        // does not exist. Resolve the deepest existing ancestor with realpath,
        // then append only the missing components.
        var cursor=url, suffix:[String]=[]
        while true {
            if let resolved=realpath(cursor.path,nil) {
                defer { free(resolved) }
                var result=URL(fileURLWithPath:String(cString:resolved))
                for part in suffix.reversed() { result.appendPathComponent(part) }
                return result
            }
            if cursor.path == "/" { return url.standardizedFileURL }
            suffix.append(cursor.lastPathComponent); cursor.deleteLastPathComponent()
        }
    }
    static func same(_ a: URL, _ b: URL) -> Bool {
        if canonical(a) == canonical(b) { return true }
        var x = stat(), y = stat()
        return stat(a.path, &x) == 0 && stat(b.path, &y) == 0 && x.st_dev == y.st_dev && x.st_ino == y.st_ino
    }
    static func contains(_ root: URL, _ file: URL) -> Bool {
        let a = canonical(root).pathComponents, b = canonical(file).pathComponents
        return b.starts(with: a)
    }
    static func isProtected(_ file: URL, by references: [URL]) -> Bool {
        references.contains { contains($0, file) || same($0, file) }
    }
    static func validateExport(_ destination: URL, runtime: URL, protected: [URL]) throws {
        var destinationInfo=stat()
        if lstat(destination.path,&destinationInfo)==0 && destinationInfo.st_mode & S_IFMT == S_IFLNK {
            throw NSError(domain:"BJC85.Export",code:1,userInfo:[NSLocalizedDescriptionKey:"Choose a file destination directly instead of replacing a symbolic link."])
        }
        guard !contains(runtime, destination), !isProtected(destination, by: protected) else { throw NSError(domain: "BJC85.Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose an export folder outside the utility’s private document, diagnostic and recovery storage."]) }
        // Catch hard links to any managed file, not just the active master.
        if FileManager.default.fileExists(atPath: destination.path),
           let entries = FileManager.default.enumerator(at: runtime, includingPropertiesForKeys: nil) {
            for case let item as URL in entries where same(item, destination) { throw NSError(domain: "BJC85.Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose an export folder outside the utility’s private document, diagnostic and recovery storage."]) }
        }
    }
}
