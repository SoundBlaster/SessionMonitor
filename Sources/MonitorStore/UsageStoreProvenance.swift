import Foundation
import GRDB
import MonitorCore

extension UsageStore {
    static func checkpoint(source: String, database: Database) throws -> Data? {
        try Data.fetchOne(database, sql: "SELECT checkpoint FROM source_checkpoints WHERE source = ?",
                          arguments: [source])
    }

    static func hasMissingProvenance(source: String, database: Database) throws -> Bool {
        try Bool.fetchOne(database, sql: """
            SELECT EXISTS(
                SELECT 1 FROM source_records AS records
                WHERE records.source = ?
                  AND NOT EXISTS(
                      SELECT 1 FROM source_provenance AS provenance
                      WHERE provenance.source = records.source
                        AND provenance.session = records.session
                  )
            )
            """, arguments: [source]) ?? false
    }

    static func provenance(
        _ database: Database, sessionIDs: [String], accountScope: UsageAccountScope
    ) throws -> [String: SessionProvenance] {
        guard !sessionIDs.isEmpty else { return [:] }
        let scopePredicate = Self.accountScopePredicate()
        let rows = try Row.fetchAll(database, sql: """
            SELECT * FROM (
                SELECT provenance.*, scope.profile_id AS account_profile_id
                FROM source_provenance AS provenance
                JOIN source_account_scope AS scope ON scope.source = provenance.source
            )
            WHERE 1 \(scopePredicate)
            ORDER BY source, session
            """, arguments: [
                accountScope.kind.rawValue, accountScope.kind.rawValue, accountScope.profileID,
                accountScope.kind.rawValue
            ])
        let wanted = Set(sessionIDs)
        let titles = Self.uniqueSessionTitles(rows)
        var result: [String: SessionProvenance] = [:]
        for row in rows {
            let session: String = row["session"]
            guard wanted.contains(session) else { continue }
            let models = (try? JSONDecoder().decode([String].self, from: Data((row["models"] as String).utf8))) ?? []
            let efforts = (try? JSONDecoder().decode([String].self, from: Data((row["efforts"] as String).utf8))) ?? []
            let relationshipKind: String? = row["relationship_kind"]
            let relationship = relationshipKind.flatMap { kind in
                SessionRelationshipKind(rawValue: kind).map {
                    SessionRelationship(kind: $0, parentSessionID: row["parent_session"])
                }
            }
            let value = SessionProvenance(sessionID: session, rootSessionID: row["root_session"],
                                          displayName: row["display_name"], sessionTitle: titles[session],
                                          agentPath: row["agent_path"],
                                          originator: row["originator"], clientVersion: row["client_version"],
                                          modelProvider: row["model_provider"], models: models, efforts: efforts,
                                          relationship: relationship)
            if let existing = result[session] {
                result[session] = SessionProvenance(sessionID: session,
                    rootSessionID: existing.rootSessionID ?? value.rootSessionID,
                    displayName: existing.displayName ?? value.displayName, sessionTitle: value.sessionTitle,
                    agentPath: existing.agentPath ?? value.agentPath,
                    originator: existing.originator ?? value.originator,
                    clientVersion: existing.clientVersion ?? value.clientVersion,
                    modelProvider: existing.modelProvider ?? value.modelProvider,
                    models: Array(Set(existing.models).union(models)).sorted(),
                    efforts: Array(Set(existing.efforts).union(efforts)).sorted(),
                    relationship: existing.relationship ?? relationship)
            } else {
                result[session] = value
            }
        }
        return result
    }

    private static func uniqueSessionTitles(_ rows: [Row]) -> [String: String] {
        var titles: [String: Set<String>] = [:]
        for row in rows {
            let session: String = row["session"]
            if let title: String = row["session_title"] { titles[session, default: []].insert(title) }
        }
        return titles.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    static func insertProvenance(
        _ provenance: SessionProvenance, source: String, database: Database
    ) throws {
        let encoder = JSONEncoder()
        let models = try encoder.encode(provenance.models)
        let efforts = try encoder.encode(provenance.efforts)
        try database.execute(sql: """
            INSERT INTO source_provenance (
                source, session, root_session, display_name, agent_path, originator,
                client_version, model_provider, models, efforts, relationship_kind, parent_session
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source, session) DO UPDATE SET
                root_session = COALESCE(excluded.root_session, source_provenance.root_session),
                display_name = COALESCE(excluded.display_name, source_provenance.display_name),
                agent_path = COALESCE(excluded.agent_path, source_provenance.agent_path),
                originator = COALESCE(excluded.originator, source_provenance.originator),
                client_version = COALESCE(excluded.client_version, source_provenance.client_version),
                model_provider = COALESCE(excluded.model_provider, source_provenance.model_provider),
                models = excluded.models, efforts = excluded.efforts,
                relationship_kind = COALESCE(excluded.relationship_kind, source_provenance.relationship_kind),
                parent_session = COALESCE(excluded.parent_session, source_provenance.parent_session)
            """, arguments: [
                source, provenance.sessionID, provenance.rootSessionID, provenance.displayName,
                provenance.agentPath, provenance.originator, provenance.clientVersion,
                provenance.modelProvider, String(bytes: models, encoding: .utf8) ?? "[]",
                String(bytes: efforts, encoding: .utf8) ?? "[]", provenance.relationship?.kind.rawValue,
                provenance.relationship?.parentSessionID
            ])
    }

}
