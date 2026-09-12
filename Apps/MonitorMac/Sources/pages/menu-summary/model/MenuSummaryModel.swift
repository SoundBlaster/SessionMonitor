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
        @Sendable (UsageQuery) async throws -> AsyncThrowingStream<UsageSnapshot, Error>
    @ObservationIgnored private var activeQuery = menuDefaultUsageQuery()
    @ObservationIgnored private var observationGeneration = UUID()

    init(streamFactory: @escaping @Sendable () async throws -> AsyncThrowingStream<UsageSnapshot, Error>) {
        self.streamFactory = { _ in try await streamFactory() }
    }

    init(queryStreamFactory: @escaping @Sendable (UsageQuery) async throws ->
         AsyncThrowingStream<UsageSnapshot, Error>) {
        streamFactory = queryStreamFactory
    }

    func refresh(query: UsageQuery? = nil, using factory: @Sendable () async throws -> UsageSnapshot) async {
        guard !isRefreshing else { return }
        let requestedQuery = query ?? activeQuery
        activate(requestedQuery)
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let value = try await factory()
            apply(value, expectedQuery: requestedQuery)
            errorMessage = nil
        } catch is CancellationError {
            // Cancellation does not invalidate the last available report.
        } catch {
            errorMessage = "Could not refresh the report. \(error.localizedDescription)"
        }
    }

    private func activate(_ query: UsageQuery) {
        guard activeQuery != query else { return }
        activeQuery = query
        snapshot = nil
        errorMessage = nil
    }

    private func apply(_ value: UsageSnapshot, expectedQuery: UsageQuery) {
        guard activeQuery == expectedQuery, value.query == expectedQuery else { return }
        if let snapshot, snapshot.query == value.query,
           snapshot.watermark.databaseID == value.watermark.databaseID,
           snapshot.watermark.revision >= value.watermark.revision { return }
        snapshot = value
    }

    /// The panel task owns observation. Reopening reconnects to the stored index.
    func observe(query: UsageQuery? = nil) async {
        let requestedQuery = query ?? activeQuery
        if isObserving, activeQuery == requestedQuery { return }
        activate(requestedQuery)
        let generation = UUID()
        observationGeneration = generation
        isObserving = true
        errorMessage = nil
        defer {
            if observationGeneration == generation { isObserving = false }
        }
        do {
            let stream = try await streamFactory(requestedQuery)
            for try await value in stream {
                guard !Task.isCancelled, observationGeneration == generation else { return }
                apply(value, expectedQuery: requestedQuery)
            }
            if !Task.isCancelled, observationGeneration == generation {
                errorMessage = "Report observation ended. Reopen this panel to reconnect."
            }
        } catch is CancellationError {
            // The panel closed; no runtime work is owned by this model.
        } catch {
            guard !Task.isCancelled, observationGeneration == generation else { return }
            errorMessage = "Could not read the index. \(error.localizedDescription)"
        }
    }
}

private func menuDefaultUsageQuery() -> UsageQuery {
    do {
        return try UsageQuery()
    } catch {
        preconditionFailure("The built-in UTC query must be valid: \(error)")
    }
}
