import Foundation
import MonitorCore
import MonitorRuntime
import Observation

protocol SessionExplorerRuntime: Sendable {
    func importDirectory(_ directory: URL) async throws -> ImportSummary
    func snapshot(query: UsageQuery) async throws -> UsageSnapshot
    func snapshots(query: UsageQuery) async -> AsyncThrowingStream<UsageSnapshot, Error>
}

extension MonitorRuntime.SessionMonitor: SessionExplorerRuntime {}

@MainActor
@Observable
final class SessionExplorerModel {
    enum Activity: Equatable {
        case idle
        case loading
        case importing
    }

    private(set) var snapshot: UsageSnapshot?
    private(set) var report: UsageReport
    private(set) var activity: Activity = .idle
    private(set) var errorMessage: String?
    private(set) var importSummary: ImportSummary?
    private(set) var importedDirectory: URL?
    private(set) var lastUpdated: Date?
    private(set) var filter = ""
    var navigation = SessionNavigationState()

    @ObservationIgnored let contextProvider: SessionReportContextProvider
    @ObservationIgnored private let runtimeFactory: @Sendable () async throws -> any SessionExplorerRuntime
    @ObservationIgnored private var runtime: (any SessionExplorerRuntime)?
    @ObservationIgnored private var didLoad = false

    init(runtimeFactory: @escaping @Sendable () async throws -> any SessionExplorerRuntime) {
        let empty = UsageReport(totals: UsageTotals(), sessions: [], diagnostics: [:])
        report = empty
        contextProvider = SessionReportContextProvider(
            snapshot: SessionReportSnapshot(report: empty, selectedSessionID: nil)
        )
        self.runtimeFactory = runtimeFactory
    }

    var visibleSessions: [SessionSummary] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return report.sessions.filter { session in
            query.isEmpty || session.id.localizedCaseInsensitiveContains(query)
                || session.model.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedSession: SessionSummary? {
        visibleSessions.first { $0.id == navigation.selectedSessionID }
    }

    var isBusy: Bool { activity != .idle }

    func setFilter(_ value: String) {
        filter = value
        navigation.reconcile(with: visibleSessions)
        publishSnapshot()
    }

    func selectSession(_ id: String?) {
        navigation.select(id, among: visibleSessions)
        publishSnapshot()
    }

    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        await refresh()
    }

    /// Owned by the window task; closing the window cancels the underlying observation.
    func observe() async {
        do {
            let runtime = try await resolvedRuntime()
            let stream = await runtime.snapshots(query: try UsageQuery())
            for try await snapshot in stream {
                guard !Task.isCancelled else { return }
                apply(snapshot)
            }
        } catch is CancellationError {
            // Window lifetime ended.
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Could not observe the report. \(error.localizedDescription)"
        }
    }

    func refresh() async {
        guard !isBusy else { return }
        activity = .loading
        errorMessage = nil
        defer { activity = .idle }
        do {
            let runtime = try await resolvedRuntime()
            let snapshot = try await runtime.snapshot(query: UsageQuery())
            apply(snapshot)
        } catch {
            errorMessage = "Could not load the report. \(error.localizedDescription)"
        }
    }

    func importDirectory(_ directory: URL) async {
        guard !isBusy else { return }
        activity = .importing
        errorMessage = nil
        importSummary = nil
        let scopedAccess = directory.startAccessingSecurityScopedResource()
        defer {
            if scopedAccess { directory.stopAccessingSecurityScopedResource() }
            activity = .idle
        }
        do {
            let runtime = try await resolvedRuntime()
            let summary = try await runtime.importDirectory(directory)
            let snapshot = try await runtime.snapshot(query: UsageQuery())
            importSummary = summary
            importedDirectory = directory
            apply(snapshot)
        } catch {
            errorMessage = "Could not import \(directory.lastPathComponent). \(error.localizedDescription)"
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func resolvedRuntime() async throws -> any SessionExplorerRuntime {
        if let runtime { return runtime }
        let runtime = try await runtimeFactory()
        self.runtime = runtime
        return runtime
    }

    private func apply(_ newSnapshot: UsageSnapshot) {
        if let snapshot, snapshot.watermark.databaseID == newSnapshot.watermark.databaseID,
           snapshot.watermark.revision >= newSnapshot.watermark.revision { return }
        snapshot = newSnapshot
        report = newSnapshot.report
        navigation.reconcile(with: visibleSessions)
        lastUpdated = newSnapshot.watermark.committedAt
        publishSnapshot()
    }

    private func publishSnapshot() {
        contextProvider.replace(with: SessionReportSnapshot(
            report: report,
            selectedSessionID: navigation.selectedSessionID
        ))
    }
}
