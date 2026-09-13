import Foundation
import MonitorCore
import MonitorRuntime
import Observation

protocol SessionExplorerRuntime: RequestTimelineSource, Sendable {
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
    private(set) var provenance: [String: SessionProvenance] = [:]
    private(set) var report: UsageReport
    private(set) var query: UsageQuery
    private(set) var activity: Activity = .idle
    private(set) var errorMessage: String?
    private(set) var importSummary: ImportSummary?
    private(set) var importedDirectory: URL?
    private(set) var lastUpdated: Date?
    private(set) var filter = ""
    var navigation = SessionNavigationState()

    @ObservationIgnored let contextProvider: SessionReportContextProvider
    let timelineModel = RequestTimelineModel()
    @ObservationIgnored private let runtimeFactory: @Sendable () async throws -> any SessionExplorerRuntime
    @ObservationIgnored private var runtime: (any SessionExplorerRuntime)?
    @ObservationIgnored private var loadedQuery: UsageQuery?

    init(runtimeFactory: @escaping @Sendable () async throws -> any SessionExplorerRuntime) {
        let empty = UsageReport(totals: UsageTotals(), sessions: [], diagnostics: [:])
        report = empty
        query = defaultUsageQuery()
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
                || (provenance[session.id]?.displayName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var sessionTree: [SessionTreeNode] {
        SessionTreeBuilder.build(sessions: report.sessions, provenance: provenance)
    }

    var visibleSessionTree: [SessionTreeNode] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessionTree }
        return sessionTree.compactMap { filteredTree($0, query: query, provenance: provenance) }
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
        let previousSelection = navigation.selectedSessionID
        navigation.select(id, among: visibleSessions)
        if navigation.selectedSessionID != previousSelection { timelineModel.reset() }
        publishSnapshot()
    }

    func loadTimeline(sessionID: String) async {
        guard selectedSession?.id == sessionID else { return }
        do {
            let runtime = try await resolvedRuntime()
            await timelineModel.load(sessionID: sessionID, query: query, source: runtime)
        } catch {
            timelineModel.fail(error)
        }
    }

    func loadIfNeeded(query requestedQuery: UsageQuery? = nil) async {
        let requestedQuery = requestedQuery ?? query
        activate(requestedQuery)
        guard loadedQuery != requestedQuery else { return }
        loadedQuery = requestedQuery
        await refresh()
    }

    /// Owned by the window task; closing the window cancels the underlying observation.
    func observe(query requestedQuery: UsageQuery? = nil) async {
        let requestedQuery = requestedQuery ?? query
        activate(requestedQuery)
        do {
            let runtime = try await resolvedRuntime()
            let stream = await runtime.snapshots(query: requestedQuery)
            for try await snapshot in stream {
                guard !Task.isCancelled else { return }
                apply(snapshot, expectedQuery: requestedQuery)
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
            let requestedQuery = query
            let snapshot = try await runtime.snapshot(query: requestedQuery)
            apply(snapshot, expectedQuery: requestedQuery)
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
            let requestedQuery = query
            let snapshot = try await runtime.snapshot(query: requestedQuery)
            importSummary = summary
            importedDirectory = directory
            apply(snapshot, expectedQuery: requestedQuery)
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

    private func activate(_ requestedQuery: UsageQuery) {
        guard query != requestedQuery else { return }
        query = requestedQuery
        timelineModel.reset()
        snapshot = nil
        provenance = [:]
        report = UsageReport(totals: UsageTotals(), sessions: [], diagnostics: [:])
        navigation.reconcile(with: [])
        lastUpdated = nil
        publishSnapshot()
    }

    private func apply(_ newSnapshot: UsageSnapshot, expectedQuery: UsageQuery) {
        guard query == expectedQuery, newSnapshot.query == expectedQuery else { return }
        if let snapshot, snapshot.query == newSnapshot.query,
           snapshot.watermark.databaseID == newSnapshot.watermark.databaseID,
           snapshot.watermark.revision >= newSnapshot.watermark.revision { return }
        snapshot = newSnapshot
        provenance = newSnapshot.provenance
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

private func filteredTree(_ node: SessionTreeNode, query: String,
                          provenance: [String: SessionProvenance]) -> SessionTreeNode? {
    let matches = node.session.id.localizedCaseInsensitiveContains(query)
        || node.session.model.localizedCaseInsensitiveContains(query)
        || (provenance[node.id]?.displayName?.localizedCaseInsensitiveContains(query) ?? false)
    let children = node.children.compactMap { filteredTree($0, query: query, provenance: provenance) }
    guard matches || !children.isEmpty else { return nil }
    return SessionTreeNode(session: node.session, state: node.state, children: children)
}

private func defaultUsageQuery() -> UsageQuery {
    do {
        return try UsageQuery()
    } catch {
        preconditionFailure("The built-in UTC query must be valid: \(error)")
    }
}
