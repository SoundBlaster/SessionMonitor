import Foundation
import MonitorCore

/// Shares report observations per full query across windows and the menu without owning imports.
actor SharedReportRuntime: SessionExplorerRuntime {
    private struct QueryObservation {
        let generation: UUID
        var observers: [UUID: AsyncThrowingStream<UsageSnapshot, Error>.Continuation]
        var task: Task<Void, Never>?
        var latest: UsageSnapshot?
    }

    private let runtime: any SessionExplorerRuntime
    private var observations: [UsageQuery: QueryObservation] = [:]

    init(runtime: any SessionExplorerRuntime) { self.runtime = runtime }

    func importDirectory(_ directory: URL) async throws -> ImportSummary {
        try await runtime.importDirectory(directory)
    }

    func snapshot(query: UsageQuery) async throws -> UsageSnapshot {
        try await runtime.snapshot(query: query)
    }

    func timeline(sessionID: String, query: UsageQuery) async throws -> RequestTimeline {
        try await runtime.timeline(sessionID: sessionID, query: query)
    }

    func cacheHitRateWidget(
        period: CacheHitRateWidgetPeriod, referenceDate: Date, timeZone: TimeZone,
        accountScope: UsageAccountScope
    ) async throws -> CacheHitRateWidgetReport {
        try await runtime.cacheHitRateWidget(period: period, referenceDate: referenceDate,
                                             timeZone: timeZone, accountScope: accountScope)
    }

    func quotaPresentation(query: UsageQuery, generatedAt: Date) async throws -> QuotaPresentationReport {
        try await runtime.quotaPresentation(query: query, generatedAt: generatedAt)
    }

    func accountProfiles() async throws -> [AccountProfile] {
        try await runtime.accountProfiles()
    }

    func snapshots(query: UsageQuery) async -> AsyncThrowingStream<UsageSnapshot, Error> {
        let id = UUID()
        let (stream, continuation) = AsyncThrowingStream<UsageSnapshot, Error>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let generation: UUID
        if var observation = observations[query] {
            generation = observation.generation
            observation.observers[id] = continuation
            if let latest = observation.latest { continuation.yield(latest) }
            observations[query] = observation
        } else {
            generation = UUID()
            observations[query] = QueryObservation(
                generation: generation,
                observers: [id: continuation],
                task: nil,
                latest: nil
            )
        }
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id, query: query, generation: generation) }
        }
        if observations[query]?.task == nil {
            let runtime = runtime
            let task = Task { [weak self] in
                let source = await runtime.snapshots(query: query)
                do {
                    for try await value in source {
                        guard !Task.isCancelled else { break }
                        await self?.publish(value, query: query, generation: generation)
                    }
                    await self?.finish(query: query, generation: generation, error: nil)
                } catch {
                    await self?.finish(query: query, generation: generation, error: error)
                }
            }
            observations[query]?.task = task
        }
        return stream
    }

    private func publish(_ value: UsageSnapshot, query: UsageQuery, generation: UUID) {
        guard var observation = observations[query], observation.generation == generation else { return }
        observation.latest = value
        observations[query] = observation
        for observer in observation.observers.values { observer.yield(value) }
    }

    private func finish(query: UsageQuery, generation: UUID, error: (any Error)?) {
        guard let observation = observations[query], observation.generation == generation else { return }
        observations[query] = nil
        let completed = Array(observation.observers.values)
        for observer in completed { observer.finish(throwing: error) }
    }

    private func removeObserver(_ id: UUID, query: UsageQuery, generation: UUID) {
        guard var observation = observations[query], observation.generation == generation else { return }
        observation.observers[id] = nil
        guard observation.observers.isEmpty else {
            observations[query] = observation
            return
        }
        observations[query] = nil
        observation.task?.cancel()
    }

    deinit {
        for observation in observations.values { observation.task?.cancel() }
    }
}
