import Foundation
import MonitorCore
import Observation

/// A read-only snapshot capability: the menu cannot start an importer or watcher.
@MainActor
@Observable
final class MenuSummaryModel {
    private(set) var snapshot: UsageSnapshot?
    private(set) var errorMessage: String?
    private(set) var isObserving = false
    private(set) var isRefreshing = false

    @ObservationIgnored private let streamFactory:
        @Sendable () async throws -> AsyncThrowingStream<UsageSnapshot, Error>

    init(streamFactory: @escaping @Sendable () async throws -> AsyncThrowingStream<UsageSnapshot, Error>) {
        self.streamFactory = streamFactory
    }

    func refresh(using factory: @Sendable () async throws -> UsageSnapshot) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let value = try await factory()
            apply(value)
            errorMessage = nil
        } catch {
            errorMessage = "Could not refresh the report. \(error.localizedDescription)"
        }
    }

    private func apply(_ value: UsageSnapshot) {
        if let snapshot, snapshot.watermark.databaseID == value.watermark.databaseID,
           snapshot.watermark.revision >= value.watermark.revision { return }
        snapshot = value
    }

    /// The panel task owns observation. Reopening reconnects to the stored index.
    func observe() async {
        guard !isObserving else { return }
        isObserving = true
        errorMessage = nil
        defer { isObserving = false }
        do {
            let stream = try await streamFactory()
            for try await value in stream {
                guard !Task.isCancelled else { return }
                apply(value)
            }
            if !Task.isCancelled { errorMessage = "Report observation ended. Reopen this panel to reconnect." }
        } catch is CancellationError {
            // The panel closed; no runtime work is owned by this model.
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Could not read the index. \(error.localizedDescription)"
        }
    }
}
