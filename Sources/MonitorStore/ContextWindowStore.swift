import Foundation
import GRDB
import MonitorCore

/// Presentation evidence only (SM-727): the usable context window a source reported after a canonical
/// response. It is keyed like the other per-source tables and never contributes to accounting.
extension UsageStore {
    static func registerContextWindowMigration(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("context-windows-v1") { database in
            try database.execute(sql: """
                CREATE TABLE source_context_windows (
                    source TEXT NOT NULL, line INTEGER NOT NULL, response TEXT NOT NULL, session TEXT NOT NULL,
                    window INTEGER NOT NULL CHECK(window > 0),
                    PRIMARY KEY(source, line)
                );
                CREATE INDEX context_window_responses ON source_context_windows(response);
                """)
        }
    }

    static func insertContextWindows(_ windows: [ContextWindowObservation], source: String,
                                     database: Database) throws {
        for window in windows {
            try database.execute(sql: """
                INSERT INTO source_context_windows VALUES (?, ?, ?, ?, ?)
                """, arguments: [source, window.sourceLine, window.responseID, window.sessionID,
                                  window.contextWindowTokens])
        }
    }
}
