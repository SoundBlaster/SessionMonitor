import Foundation
import MonitorCore
import MonitorStore

extension SessionMonitor {
    public func snapshot(query: UsageQuery) throws -> UsageSnapshot {
        // No previous watermark means the store always returns the current snapshot.
        guard let snapshot = try store.snapshot(query: query) else { throw QueryObservationError.missingSnapshot }
        return snapshot
    }

    /// Reads only the revision each second while idle. GRDB observation alone misses external writes.
    /// Each consumer owns its bounded stream; cancellation releases its task and database reference.
    public func snapshots(query: UsageQuery) -> AsyncThrowingStream<UsageSnapshot, Error> {
        let store = store
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task.detached {
                do {
                    var previous: QueryWatermark?
                    while !Task.isCancelled {
                        if let snapshot = try store.snapshot(query: query, after: previous) {
                            previous = snapshot.watermark
                            continuation.yield(snapshot)
                        }
                        try await Task.sleep(for: .seconds(1))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private enum QueryObservationError: Error { case missingSnapshot }
