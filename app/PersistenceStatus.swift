import Foundation

/// Main-thread ledger. A completion can resolve only its resource and exact
/// generation; stale writes never clear newer failures or pending work.
struct PersistenceStatus {
    struct Ticket: Equatable { let resource:String; let generation:Int }
    private var generations:[String:Int]=[:]
    private(set) var pending:Set<String>=[]
    private(set) var failures:[String:String]=[:]
    var isSaved:Bool { pending.isEmpty && failures.isEmpty }
    mutating func begin(_ resource:String) -> Ticket {
        generations[resource,default:0] += 1; pending.insert(resource)
        return Ticket(resource:resource,generation:generations[resource]!)
    }
    mutating func finish(_ ticket:Ticket, error:Error?) {
        guard generations[ticket.resource]==ticket.generation else { return }
        pending.remove(ticket.resource)
        if let error { failures[ticket.resource]=error.localizedDescription }
        else { failures.removeValue(forKey:ticket.resource) }
    }
}
