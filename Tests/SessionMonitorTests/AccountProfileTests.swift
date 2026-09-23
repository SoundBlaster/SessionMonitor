import Foundation
import GRDB
import CodexSource
import MonitorCore
import MonitorPolicies
import MonitorStore
import Testing

struct AccountProfileTests {
    @Test func rolloutAccountIdentityIsIndependentFromSessionOwnership() throws {
        let fixture = try UsageLimitFixture()
        defer { fixture.remove() }
        let metadata = try fixture.jsonlLine([
            "timestamp": "2026-09-20T10:00:00Z", "type": "session_meta",
            "payload": ["id": "session", "timestamp": "2026-09-20T10:00:00Z",
                        "creator_account_id": "account-id", "creator_user_id": "user-id"]
        ])
        let quota = try fixture.jsonlLine([
            "timestamp": "2026-09-20T10:01:00Z", "type": "event_msg",
            "payload": ["type": "token_count", "rate_limits": [
                "limit_id": "limit", "primary": [
                    "used_percent": 80, "resets_at": 1_790_422_316, "window_minutes": 300
                ]
            ]]
        ])
        try fixture.write(metadata + quota)

        let parsed = try RolloutDecoder().parse(fixture.file)
        let identity = try #require(parsed.accountIdentity)
        let quotaIdentity = try #require(parsed.usageLimitSnapshots.first?.accountIdentity)
        #expect(identity.accountID == "account-id")
        #expect(identity.userID == "user-id")
        #expect(quotaIdentity == identity)
        #expect(parsed.provenance?.sessionID == "session")
    }

    @Test func sameCanonicalAndQuotaIDsRemainDistinctAcrossProfilesButMirrorsDeduplicate() throws {
        let fixture = try AccountProfileFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        let identityA = SourceAccountIdentity(accountID: "account-A", userID: "user-A")
        let identityB = SourceAccountIdentity(accountID: "account-B", userID: "user-B")
        try store.replace(source: fixture.source("a/one.jsonl"), rollout: fixture.rollout(identity: identityA))
        try store.replace(source: fixture.source("a/mirror.jsonl"), rollout: fixture.rollout(identity: identityA))
        try store.replace(source: fixture.source("b/one.jsonl"), rollout: fixture.rollout(identity: identityB))

        _ = try store.assignAccountProfile(sourceRoot: fixture.directory.appending(path: "a"),
                                           profileID: "personal", label: "Personal")
        _ = try store.assignAccountProfile(sourceRoot: fixture.directory.appending(path: "b"),
                                           profileID: "work", label: "Work")

        let all = try #require(try store.snapshot(query: UsageQuery())).report
        let personalQuery = try UsageQuery(accountScope: UsageAccountScope(profileID: "personal"))
        let personal = try #require(try store.snapshot(query: personalQuery)).report
        let quota = try store.usageLimitSnapshots(query: UsageQuery(), generatedAt: fixture.date)
        let personalQuota = try store.usageLimitSnapshots(query: personalQuery, generatedAt: fixture.date)
        let allActivity = try store.activity(query: UsageQuery())
        let personalActivity = try store.activity(query: personalQuery)
        let personalTimeline = try store.timeline(sessionID: "session-collision", query: personalQuery)

        #expect(all.totals.requests == 2)
        #expect(personal.totals.requests == 1)
        #expect(personal.accountScope == personalQuery.accountScope)
        #expect(personal.sessions.map(\.id) == ["session-collision"])
        #expect(quota.snapshots.count == 2)
        #expect(quota.snapshots.allSatisfy { $0.accountProfileID != nil })
        #expect(quota.snapshots.first(where: { $0.accountProfileID == "personal" })?.duplicateSourceRecords == 1)
        #expect(quota.snapshots.first(where: { $0.accountProfileID == "work" })?.duplicateSourceRecords == 0)
        #expect(personalQuota.snapshots.count == 1)
        #expect(personalQuota.snapshots[0].accountProfileLabel == "Personal")
        #expect(personalQuota.snapshots[0].accountScopeState == .assigned)
        #expect(allActivity.totals.requests == 2)
        #expect(personalActivity.totals.requests == 1)
        #expect(allActivity.toolEvents.count == 2)
        #expect(personalActivity.toolEvents.count == 1)
        #expect(!personalTimeline.points.contains { $0.evidence == "fixture:account-B" })
    }

    @Test func existingDatabaseMigrationPreservesUsageAndAddsUnknownAccountScope() throws {
        let fixture = try AccountProfileFixture()
        defer { fixture.remove() }
        do {
            let store = try UsageStore(url: fixture.database)
            try store.replace(source: fixture.source("a/legacy.jsonl"), rollout: fixture.rollout(
                identity: SourceAccountIdentity(accountID: "known-account", userID: nil)
            ))
        }

        let oldDatabase = try DatabaseQueue(path: fixture.database.path)
        try oldDatabase.write { database in
            try database.execute(sql: "DROP VIEW confirmed")
            try database.execute(sql: "DROP TABLE source_account_scope")
            try database.execute(sql: "DROP TABLE account_source_roots")
            try database.execute(sql: "DROP TABLE account_profiles")
            try database.execute(sql: "ALTER TABLE source_usage_limit_snapshots DROP COLUMN account_id")
            try database.execute(sql: "ALTER TABLE source_usage_limit_snapshots DROP COLUMN user_id")
            try database.execute(sql: """
                CREATE VIEW confirmed AS
                SELECT response, session, turn, MIN(timestamp) AS timestamp, model, input, cached, output,
                       cache_write, reasoning, total
                FROM source_records GROUP BY response HAVING COUNT(DISTINCT fingerprint) = 1
                """)
            try database.execute(sql: """
                DELETE FROM grdb_migrations
                WHERE identifier IN ('account-profile-provenance-v1', 'usage-limit-account-identity-v1')
                """)
        }

        let migrated = try UsageStore(url: fixture.database)
        let report = try #require(try migrated.snapshot(query: UsageQuery())).report
        let quota = try migrated.usageLimitSnapshots(query: UsageQuery(), generatedAt: fixture.date)
        #expect(report.totals.requests == 1)
        #expect(try migrated.accountProfiles().isEmpty)
        #expect(quota.snapshots.count == 1)
        #expect(quota.snapshots[0].accountScopeState == .unknown)
        #expect(quota.snapshots[0].accountProfileID == nil)
    }

    @Test func assigningRootWithMultipleExplicitIdentitiesLeavesItMixed() throws {
        let fixture = try AccountProfileFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        try store.replace(source: fixture.source("mixed/first.jsonl"), rollout: fixture.rollout(
            identity: SourceAccountIdentity(accountID: "account-A", userID: nil)
        ))
        try store.replace(source: fixture.source("mixed/second.jsonl"), rollout: fixture.rollout(
            identity: SourceAccountIdentity(accountID: "account-B", userID: nil)
        ))

        let profile = try store.assignAccountProfile(sourceRoot: fixture.directory.appending(path: "mixed"),
                                                     profileID: "combined", label: "Combined")
        let all = try #require(try store.snapshot(query: UsageQuery())).report
        let unknownQuery = try UsageQuery(accountScope: .unknownOrMixed)
        let unknown = try #require(try store.snapshot(query: unknownQuery)).report
        let snapshots = try store.usageLimitSnapshots(query: unknownQuery, generatedAt: fixture.date)

        #expect(profile.mappingState == .mixed)
        #expect(all.totals.requests == 2)
        #expect(unknown.totals.requests == 2)
        #expect(snapshots.snapshots.count == 2)
        #expect(snapshots.snapshots.allSatisfy { $0.accountProfileID == nil })
        #expect(snapshots.snapshots.allSatisfy { $0.accountScopeState == .mixed })
    }

    @Test func overlappingProfileRootsAreRejected() throws {
        let fixture = try AccountProfileFixture()
        defer { fixture.remove() }
        let nestedRoot = fixture.directory.appending(path: "a/nested")
        try FileManager.default.createDirectory(at: nestedRoot, withIntermediateDirectories: true)
        let store = try UsageStore(url: fixture.database)
        _ = try store.assignAccountProfile(sourceRoot: fixture.directory.appending(path: "a"),
                                           profileID: "parent", label: "Parent")

        #expect(throws: (any Error).self) {
            _ = try store.assignAccountProfile(sourceRoot: nestedRoot, profileID: "child", label: "Child")
        }
    }

    @Test func assignmentSpecificationRejectsSecretLikeInvalidProfileLabelsAndIDs() {
        let policy = AccountProfilePolicy()
        #expect(throws: AccountProfileAssignmentError.invalidAssignment) {
            try policy.validate(AccountProfileAssignmentInput(profileID: "../private", label: "Personal",
                                                              sourceRoot: "/tmp/sessions"))
        }
        #expect(throws: AccountProfileAssignmentError.invalidAssignment) {
            try policy.validate(AccountProfileAssignmentInput(profileID: "personal", label: "\n",
                                                              sourceRoot: "/tmp/sessions"))
        }
        #expect(policy.resolve(identities: [
            SourceAccountIdentity(accountID: "a", userID: nil),
            SourceAccountIdentity(accountID: "b", userID: nil)
        ], mapping: nil) == .mixed)
    }
}

private struct AccountProfileFixture {
    let directory: URL
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    var database: URL { directory.appending(path: "usage.sqlite") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory.appending(path: "a"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory.appending(path: "b"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: directory.appending(path: "mixed"), withIntermediateDirectories: true
        )
    }

    func source(_ relative: String) -> String {
        directory.appending(path: relative).standardizedFileURL.path
    }

    func rollout(identity: SourceAccountIdentity) -> ParsedRollout {
        var rollout = ParsedRollout()
        rollout.accountIdentity = identity
        rollout.records = [UsageRecord(
            responseID: "response-collision", sessionID: "session-collision", turnID: "turn",
            timestamp: date, model: "gpt-test", inputTokens: 100, cachedInputTokens: 80,
            outputTokens: 10, sourceLine: 1
        )]
        rollout.timelineEvents = [TimelineSourceEvent(
            sessionID: "session-collision", timestamp: date, sourceLine: 3, kind: .tool,
            evidence: "fixture:\(identity.accountID ?? "unknown")", toolName: "exec_command",
            activityClass: .shell
        )]
        rollout.usageLimitSnapshots = [UsageLimitSnapshotObservation(
            eventIdentity: "quota-event-collision", timestamp: date, sourceLine: 2,
            sourceContextSessionID: "unrelated-session", sourceSchema: "fixture", state: .observed,
            scope: .unknown, limitID: "shared-limit", limitName: nil, planType: nil,
            accountIdentity: identity,
            windows: [UsageLimitWindowObservation(slot: .primary, windowMinutes: 300,
                                                  usedPercent: 75, resetsAt: date.addingTimeInterval(300))]
        )]
        return rollout
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
