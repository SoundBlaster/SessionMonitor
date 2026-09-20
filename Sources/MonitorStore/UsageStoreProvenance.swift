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

    static func provenance(_ database: Database, sessionIDs: [String]) throws -> [String: SessionProvenance] {
        guard !sessionIDs.isEmpty else { return [:] }
        let rows = try Row.fetchAll(database, sql: "SELECT * FROM source_provenance ORDER BY source, session")
        let wanted = Set(sessionIDs)
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
                                          displayName: row["display_name"], agentPath: row["agent_path"],
                                          originator: row["originator"], clientVersion: row["client_version"],
                                          modelProvider: row["model_provider"], models: models, efforts: efforts,
                                          relationship: relationship)
            if let existing = result[session] {
                result[session] = SessionProvenance(sessionID: session,
                    rootSessionID: existing.rootSessionID ?? value.rootSessionID,
                    displayName: existing.displayName ?? value.displayName,
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
}
