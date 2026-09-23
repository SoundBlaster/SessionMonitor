import CryptoKit
import Foundation
import GRDB
import MonitorCore

extension UsageStore {
    static func accountScopePredicate(_ alias: String = "") -> String {
        let profile = alias.isEmpty ? "account_profile_id" : "\(alias).account_profile_id"
        return """
            AND (? = 'allAccounts'
                 OR (? = 'profile' AND \(profile) = ?)
                 OR (? = 'unknownOrMixed' AND \(profile) IS NULL))
            """
    }

    static func registerAccountProfileMigration(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("account-profile-provenance-v1") { database in
            try database.execute(sql: """
                CREATE TABLE account_profiles (
                    profile_id TEXT PRIMARY KEY NOT NULL,
                    label TEXT NOT NULL
                );
                CREATE TABLE account_source_roots (
                    source_root TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES account_profiles(profile_id),
                    mapping_state TEXT NOT NULL CHECK(mapping_state IN ('assigned', 'mixed')),
                    observed_identity_key TEXT
                );
                CREATE TABLE source_account_scope (
                    source TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT REFERENCES account_profiles(profile_id),
                    scope_key TEXT NOT NULL,
                    state TEXT NOT NULL CHECK(state IN ('assigned', 'explicitIdentity', 'unknown', 'mixed')),
                    account_id TEXT,
                    user_id TEXT
                );
                """)
            try database.execute(sql: """
                INSERT INTO source_account_scope(source, scope_key, state)
                SELECT source, 'unknown:legacy', 'unknown' FROM (
                    SELECT source FROM source_records
                    UNION SELECT source FROM source_timeline_events
                    UNION SELECT source FROM source_legacy_estimates
                    UNION SELECT source FROM source_usage_limit_snapshots
                )
                WHERE 1
                ON CONFLICT(source) DO NOTHING
                """)
            try database.execute(sql: "DROP VIEW confirmed")
            try createConfirmedView(database)
        }
    }

    private static func createConfirmedView(_ database: Database) throws {
        try database.execute(sql: """
            CREATE VIEW confirmed AS
                SELECT records.response, records.session, records.turn,
                       MIN(records.timestamp) AS timestamp, records.model, records.input,
                       records.cached, records.output, records.cache_write, records.reasoning, records.total,
                       scope.profile_id AS account_profile_id, scope.scope_key AS account_scope_key,
                       scope.state AS account_scope_state
                FROM source_records AS records
                JOIN source_account_scope AS scope ON scope.source = records.source
                GROUP BY scope.scope_key, records.response
                HAVING COUNT(DISTINCT records.fingerprint) = 1
            """)
    }

    /// Maps one homogeneous source root. Multiple explicit source identities keep the root mixed.
    public func assignAccountProfile(sourceRoot: URL, profileID: String, label: String) throws -> AccountProfile {
        let root = Self.canonicalPath(sourceRoot)
        return try database.write { database in
            let overlap = try String.fetchOne(database, sql: """
                SELECT source_root FROM account_source_roots
                WHERE source_root != ? AND (
                    substr(source_root, 1, length(?) + 1) = ? || '/'
                    OR substr(?, 1, length(source_root) + 1) = source_root || '/'
                ) LIMIT 1
                """, arguments: [root, root, root, root])
            if let overlap { throw AccountProfileStoreError.overlappingRoots(overlap) }

            try database.execute(sql: """
                INSERT INTO account_profiles(profile_id, label) VALUES (?, ?)
                ON CONFLICT(profile_id) DO UPDATE SET label = excluded.label
                """, arguments: [profileID, label.trimmingCharacters(in: .whitespacesAndNewlines)])
            let identities = try Row.fetchAll(database, sql: """
                SELECT source, account_id, user_id FROM source_account_scope
                WHERE source = ? OR substr(source, 1, length(?) + 1) = ? || '/'
                """, arguments: [root, root, root])
            let keys = Set(identities.compactMap { row -> String? in
                let identity = SourceAccountIdentity(accountID: row["account_id"], userID: row["user_id"])
                return identity.deduplicationKey
            })
            let isMixed = keys.count > 1
            let observed = keys.count == 1 ? keys.first : nil
            try database.execute(sql: """
                INSERT INTO account_source_roots(source_root, profile_id, mapping_state, observed_identity_key)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(source_root) DO UPDATE SET profile_id = excluded.profile_id,
                    mapping_state = excluded.mapping_state, observed_identity_key = excluded.observed_identity_key
                """, arguments: [root, profileID, isMixed ? "mixed" : "assigned", observed])

            for row in identities {
                let source: String = row["source"]
                let identity = SourceAccountIdentity(accountID: row["account_id"], userID: row["user_id"])
                let identityKey = identity.deduplicationKey.map(Self.identityScopeKey)
                let key = isMixed ? (identityKey ?? Self.unknownScopeKey(source)) : "profile:\(profileID)"
                try database.execute(sql: """
                    UPDATE source_account_scope SET profile_id = ?, scope_key = ?, state = ? WHERE source = ?
                    """, arguments: [isMixed ? nil : profileID, key, isMixed ? "mixed" : "assigned", source])
            }
            try Self.advanceWatermark(database)
            return AccountProfile(
                id: profileID, label: label.trimmingCharacters(in: .whitespacesAndNewlines), sourceRoot: root,
                mappingState: isMixed ? .mixed : .assigned
            )
        }
    }

    public func accountProfiles() throws -> [AccountProfile] {
        try database.read { database in
            try Row.fetchAll(database, sql: """
                SELECT profiles.profile_id, profiles.label, roots.source_root, roots.observed_identity_key,
                       roots.mapping_state
                FROM account_source_roots AS roots
                JOIN account_profiles AS profiles ON profiles.profile_id = roots.profile_id
                ORDER BY profiles.label COLLATE NOCASE, roots.source_root
                """).map { row in
                AccountProfile(
                    id: row["profile_id"], label: row["label"], sourceRoot: row["source_root"],
                    mappingState: AccountProfileMappingState(rawValue: row["mapping_state"]) ?? .mixed
                )
            }
        }
    }

    // swiftlint:disable:next function_body_length
    static func updateAccountScope(source: String, identity: SourceAccountIdentity?, database: Database) throws {
        let root = try Row.fetchOne(database, sql: """
            SELECT source_root, profile_id, mapping_state, observed_identity_key
            FROM account_source_roots
            WHERE source_root = ? OR substr(?, 1, length(source_root) + 1) = source_root || '/'
            ORDER BY length(source_root) DESC LIMIT 1
            """, arguments: [source, source])
        let identityKey = identity?.deduplicationKey
        if let root {
            let path: String = root["source_root"]
            let profileID: String = root["profile_id"]
            let state: String = root["mapping_state"]
            let observed: String? = root["observed_identity_key"]
            if state == "assigned", let observed, let identityKey, observed != identityKey {
                try database.execute(sql: """
                    UPDATE account_source_roots SET mapping_state = 'mixed' WHERE source_root = ?
                    """, arguments: [path])
                try markRootSourcesMixed(path, database: database)
                try upsertAccountScope(
                    source: source,
                    binding: AccountSourceScopeBinding(
                        profileID: nil, scopeKey: identityScopeKey(identityKey), state: "mixed", identity: identity
                    ), database: database
                )
                return
            }
            if state == "assigned", observed == nil, let identityKey {
                try database.execute(sql: """
                    UPDATE account_source_roots SET observed_identity_key = ? WHERE source_root = ?
                    """, arguments: [identityKey, path])
            }
            if state == "mixed" {
                let key = identityKey.map(identityScopeKey) ?? unknownScopeKey(source)
                try upsertAccountScope(
                    source: source,
                    binding: AccountSourceScopeBinding(profileID: nil, scopeKey: key, state: "mixed",
                                                        identity: identity), database: database
                )
            } else {
                try upsertAccountScope(
                    source: source,
                    binding: AccountSourceScopeBinding(profileID: profileID, scopeKey: "profile:\(profileID)",
                                                        state: "assigned", identity: identity), database: database
                )
            }
            return
        }
        let key = identityKey.map(identityScopeKey) ?? unknownScopeKey(source)
        try upsertAccountScope(
            source: source,
            binding: AccountSourceScopeBinding(
                profileID: nil, scopeKey: key,
                state: identityKey == nil ? "unknown" : "explicitIdentity", identity: identity
            ), database: database
        )
    }

    private static func markRootSourcesMixed(_ root: String, database: Database) throws {
        let sources = try Row.fetchAll(database, sql: """
            SELECT source, account_id, user_id FROM source_account_scope
            WHERE source = ? OR substr(source, 1, length(?) + 1) = ? || '/'
            """, arguments: [root, root, root])
        for row in sources {
            let source: String = row["source"]
            let identity = SourceAccountIdentity(accountID: row["account_id"], userID: row["user_id"])
            let key = identity.deduplicationKey.map(identityScopeKey) ?? unknownScopeKey(source)
            try database.execute(sql: """
                UPDATE source_account_scope SET profile_id = NULL, scope_key = ?, state = 'mixed'
                WHERE source = ?
                """, arguments: [key, source])
        }
    }

    private static func upsertAccountScope(
        source: String, binding: AccountSourceScopeBinding, database: Database
    ) throws {
        try database.execute(sql: """
            INSERT INTO source_account_scope(source, profile_id, scope_key, state, account_id, user_id)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(source) DO UPDATE SET profile_id = excluded.profile_id,
                scope_key = excluded.scope_key, state = excluded.state,
                account_id = excluded.account_id,
                user_id = excluded.user_id
            """, arguments: [source, binding.profileID, binding.scopeKey, binding.state,
                              binding.identity?.accountID, binding.identity?.userID])
    }

    private static func identityScopeKey(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        return "identity:\(digest)"
    }

    private static func unknownScopeKey(_ source: String) -> String {
        let root = URL(fileURLWithPath: source).standardizedFileURL.deletingLastPathComponent().path
        return "unknown:\(root)"
    }

    static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

private struct AccountSourceScopeBinding {
    let profileID: String?
    let scopeKey: String
    let state: String
    let identity: SourceAccountIdentity?
}

public enum AccountProfileStoreError: Error, LocalizedError {
    case overlappingRoots(String)

    public var errorDescription: String? {
        switch self {
        case let .overlappingRoots(root): "Source roots may not overlap an existing mapping: \(root)"
        }
    }
}
