import Foundation
import GRDB
import MonitorCore
import MonitorStore
import Testing

extension QuotaSummaryTests {
    @Test func matchesFullPoliciesForInterleavedWindowsAndResetSequences() throws {
        for seed in 0..<8 {
            let fixture = try UsageLimitFixture()
            defer { fixture.remove() }
            let store = try UsageStore(url: fixture.database)
            let observations = (1...80).map { index -> UsageLimitSnapshotObservation in
                let time = Double((index * 37 + seed) % 31)
                let reset: Double? = index.isMultiple(of: 7) ? nil : Double((index + seed) % 3 * 1_000)
                let windows = UsageLimitWindowSlot.allCases.enumerated().compactMap { offset, slot in
                    (index + offset).isMultiple(of: 5) ? nil : UsageLimitWindowObservation(
                        slot: slot, windowMinutes: offset == 1 ? 10_080 : 300,
                        usedPercent: index.isMultiple(of: 11) ? nil : Double(index),
                        resetsAt: reset.map(Date.init(timeIntervalSince1970:))
                    )
                }
                return snapshot("\(seed)-\(index)", at: time, line: index, limit: "limit-\(index % 2)",
                                state: index.isMultiple(of: 11) ? .partial : .observed, windows: windows)
            }
            try replace(store, source: fixture.source, snapshots: observations)
            _ = try parity(store)
        }
    }

    @Test func unchangedSourceScopeDoesNotRebuildOldQuotaOnAppend() throws {
        let fixture = try UsageLimitFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        var initial = ParsedRollout()
        initial.usageLimitSnapshots = [snapshot("old", at: 1, line: 1)]
        let checkpoint = Data([1])
        try store.apply(source: fixture.source, update: SourceImport(
            rollout: initial, checkpoint: checkpoint, mode: .replaced, bytesRead: 1
        ), expectedCheckpoint: nil)
        let writer = try DatabaseQueue(path: fixture.database.path)
        try writer.write { database in
            try database.execute(sql: """
                CREATE TRIGGER reject_old_projection BEFORE INSERT ON quota_projection_windows
                WHEN NEW.event_identity = 'old' BEGIN SELECT RAISE(ABORT, 'old event rebuilt'); END
                """)
        }
        var appended = ParsedRollout()
        appended.usageLimitSnapshots = [snapshot("new", at: 2, line: 2)]
        try store.apply(source: fixture.source, update: SourceImport(
            rollout: appended, checkpoint: Data([2]), mode: .appended, bytesRead: 1
        ), expectedCheckpoint: checkpoint)
        #expect(try parity(store).report.coverage.supportedWindowObservations == 2)
    }
}
