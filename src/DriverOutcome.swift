import Foundation

enum OperationOutcome: String, Codable {
    case completedSafe, cancelledSafe, preflightFailedSafe, recoveryRequired
    var permitsNextOperation: Bool { self != .recoveryRequired }
}

struct ScannerReadiness: Decodable {
    let kind: String
    let transport_ok: Bool
    let replies_ok: Bool
    let head_matches: Bool
    let ready: Bool
    let temperature_raw: Int?
    var reference_valid: Bool? = nil
    var reference_temperature_raw: Int? = nil
    var canScan: Bool { kind == "ready" && transport_ok && replies_ok && head_matches && ready }
}

struct DriverOutcome {
    var readiness: ScannerReadiness?
    var outcome: OperationOutcome?
    // Bounded streaming parser: raw scan logs can be large and contain images.
    static func read(_ url: URL) -> DriverOutcome {
        var result = DriverOutcome(), pending = Data()
        guard let file = try? FileHandle(forReadingFrom: url) else { return result }
        defer { try? file.close() }
        while let bytes = try? file.read(upToCount: 65536), !bytes.isEmpty {
            pending.append(bytes)
            while let end = pending.firstIndex(of: 10) {
                let line = Data(pending.prefix(upTo: end)); pending.removeSubrange(...end)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if object["event"] as? String == "readiness" {
                    result.readiness = try? JSONDecoder().decode(ScannerReadiness.self, from: line)
                } else if object["event"] as? String == "operation_outcome",
                          let value = object["outcome"] as? String {
                    result.outcome = OperationOutcome(rawValue: value)
                }
            }
            if pending.count > 1024 * 1024 { return DriverOutcome() }
        }
        return result
    }

    static func journalPermitsRestart(_ directory: URL) -> Bool {
        let start = directory.appendingPathComponent("acquisition-started.json")
        guard FileManager.default.fileExists(atPath: start.path) else { return true }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("acquisition-ended.json")),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = value["outcome"] as? String, let outcome = OperationOutcome(rawValue: name) else { return false }
        return outcome.permitsNextOperation
    }
}
