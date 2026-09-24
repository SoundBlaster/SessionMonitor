import Foundation
import GRDB
import MonitorCore

extension UsageStore {
    public func report(since: Date?, until: Date?) throws -> UsageReport {
        try database.read { try Self.report($0, since: since, until: until, accountScope: .allAccounts) }
    }
}
