import Combine
import Foundation
import MonitorCore
import MonitorPolicies
import SpecificationKit
import Synchronization

struct SessionReportSnapshot: Equatable, Sendable {
    let report: UsageReport
    let selectedSessionID: String?

    var displayedTotals: UsageTotals {
        report.sessions.first { $0.id == selectedSessionID }?.totals ?? report.totals
    }
}

/// A concrete immutable snapshot bridges the window to SpecificationKit. Synchronous
/// reads honor ContextProviding's nonisolated contract; UI writes publish only after
/// replacing the snapshot. Neither the provider nor a specification crosses actors.
final class SessionReportContextProvider: ContextProviding, ContextUpdatesProviding {
    private let snapshot: Mutex<SessionReportSnapshot>
    private let updates = PassthroughSubject<Void, Never>()
    private let streams = ContextStreams()

    init(snapshot: SessionReportSnapshot) {
        self.snapshot = Mutex(snapshot)
    }

    func currentContext() -> SessionReportSnapshot {
        snapshot.withLock { $0 }
    }

    var contextUpdates: AnyPublisher<Void, Never> {
        updates.eraseToAnyPublisher()
    }

    var contextStream: AsyncStream<Void> {
        let streams = streams
        let id = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        streams.continuations.withLock { $0[id] = continuation }
        continuation.onTermination = { _ in
            streams.continuations.withLock { $0[id] = nil }
        }
        return stream
    }

    @MainActor
    func replace(with newSnapshot: SessionReportSnapshot) {
        let changed = snapshot.withLock { current in
            guard current != newSnapshot else { return false }
            current = newSnapshot
            return true
        }
        guard changed else { return }
        updates.send(())
        let continuations = streams.continuations.withLock { Array($0.values) }
        continuations.forEach { $0.yield(()) }
    }

    deinit {
        let continuations = streams.continuations.withLock { Array($0.values) }
        continuations.forEach { $0.finish() }
    }

    private final class ContextStreams: Sendable {
        let continuations = Mutex<[UUID: AsyncStream<Void>.Continuation]>([:])
    }
}

/// The GUI adapts its selection snapshot, while the shared policy remains canonical.
struct DisplayedCacheCoverageSpec: Specification {
    func isSatisfiedBy(_ candidate: SessionReportSnapshot) -> Bool {
        HasCompleteCacheCoverageSpec().isSatisfiedBy(candidate.displayedTotals)
    }
}
