import Foundation
import Observation

@MainActor
@Observable
final class SharedIndexLocationModel {
    private(set) var connection: SharedIndexConnection?
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    @ObservationIgnored private var attemptedRestore = false
    @ObservationIgnored private let restore: @Sendable () async throws -> SharedIndexConnection
    @ObservationIgnored private let select: @Sendable (URL) async throws -> SharedIndexConnection

    var isReady: Bool { connection != nil }
    var needsRestart: Bool {
        guard let connection else { return false }
        return connection.databaseURL.deletingLastPathComponent().standardizedFileURL
            != connection.selectedDirectory.standardizedFileURL
    }

    init(restore: @escaping @Sendable () async throws -> SharedIndexConnection,
         select: @escaping @Sendable (URL) async throws -> SharedIndexConnection) {
        self.restore = restore
        self.select = select
    }

    func restoreIfNeeded() async {
        guard !attemptedRestore, !isBusy else { return }
        attemptedRestore = true
        await perform { try await self.restore() }
    }

    func selectDirectory(_ directory: URL) async {
        guard !isBusy else { return }
        attemptedRestore = true
        await perform { try await self.select(directory) }
    }

    private func perform(_ operation: () async throws -> SharedIndexConnection) async {
        isBusy = true
        defer { isBusy = false }
        do {
            connection = try await operation()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
