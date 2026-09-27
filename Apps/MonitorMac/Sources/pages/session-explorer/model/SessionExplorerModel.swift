import Foundation
import MonitorCore
import MonitorRuntime
import Observation

protocol SessionExplorerRuntime: RequestTimelineSource, Sendable {
    func importDirectory(_ directory: URL) async throws -> ImportSummary
    func snapshot(query: UsageQuery) async throws -> UsageSnapshot
    func snapshots(query: UsageQuery) async -> AsyncThrowingStream<UsageSnapshot, Error>
    func cacheHitRateWidget(
        period: CacheHitRateWidgetPeriod, referenceDate: Date, timeZone: TimeZone,
        accountScope: UsageAccountScope
    ) async throws -> CacheHitRateWidgetReport
    func widgetSharedSnapshot(generatedAt: Date, timeZone: TimeZone) async throws -> WidgetSharedSnapshot
    func quotaPresentation(query: UsageQuery, generatedAt: Date) async throws -> QuotaPresentationReport
    func accountProfiles() async throws -> [AccountProfile]
}

extension SessionExplorerRuntime {
    func widgetSharedSnapshot(generatedAt: Date, timeZone: TimeZone) async throws -> WidgetSharedSnapshot {
        throw WidgetSharedSnapshotBuildError.unsupportedRuntime
    }
}

extension MonitorRuntime.SessionMonitor: SessionExplorerRuntime {}

struct SessionTimelineLoadID: Hashable {
    let sessionID: String
    let query: UsageQuery
}

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
    private(set) var cacheHitRateWidgetReport: CacheHitRateWidgetReport?
    private(set) var quotaPresentationReport: QuotaPresentationReport?
    private(set) var filter = ""
    var navigation = SessionNavigationState()

    @ObservationIgnored let contextProvider: SessionReportContextProvider
    let timelineModel = RequestTimelineModel()
    @ObservationIgnored private let runtimeFactory: @Sendable () async throws -> any SessionExplorerRuntime
    @ObservationIgnored private let importedDirectorySettings: ImportedDirectorySettings
    @ObservationIgnored private var runtime: (any SessionExplorerRuntime)?
    @ObservationIgnored private var loadedQuery: UsageQuery?

    init(
        runtimeFactory: @escaping @Sendable () async throws -> any SessionExplorerRuntime,
        importedDirectorySettings: ImportedDirectorySettings = ImportedDirectorySettings()
    ) {
        let empty = UsageReport(totals: UsageTotals(), sessions: [], diagnostics: [:])
        report = empty
        query = defaultUsageQuery()
        self.importedDirectorySettings = importedDirectorySettings
        importedDirectory = importedDirectorySettings.directory
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

    func loadCacheHitRateWidget(
        period: CacheHitRateWidgetPeriod, referenceDate: Date = Date(), timeZone: TimeZone
    ) async {
        let requestedAccountScope = query.accountScope
        do {
            let runtime = try await resolvedRuntime()
            let report = try await runtime.cacheHitRateWidget(
                period: period, referenceDate: referenceDate, timeZone: timeZone,
                accountScope: requestedAccountScope
            )
            guard !Task.isCancelled, query.accountScope == requestedAccountScope else { return }
            cacheHitRateWidgetReport = report
        } catch {
            guard !Task.isCancelled, query.accountScope == requestedAccountScope else { return }
            errorMessage = "Could not load the cache hit widget. \(error.localizedDescription)"
        }
    }

    func loadQuotaPresentation(generatedAt: Date = Date()) async {
        let requestedQuery = query
        do {
            let runtime = try await resolvedRuntime()
            let report = try await runtime.quotaPresentation(
                query: requestedQuery, generatedAt: generatedAt
            )
            guard !Task.isCancelled, query == requestedQuery else { return }
            quotaPresentationReport = report
        } catch {
            guard !Task.isCancelled, query == requestedQuery else { return }
            quotaPresentationReport = nil
        }
    }

    /// Returns the delay until the current quota projection crosses its freshness boundary.
    /// Once the boundary has passed, the database watermark or the next explicit refresh
    /// is responsible for loading newer observations.
    func quotaFreshnessRefreshDelay(now: Date = Date()) -> TimeInterval? {
        guard let report = quotaPresentationReport,
              let latest = report.coverage.latestObservedAt else { return nil }
        let boundary = latest.addingTimeInterval(report.freshnessThresholdSeconds)
        let delay = boundary.timeIntervalSince(now)
        return delay > 0 ? delay : nil
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

    /// Imports the last selected folder before loading the report; falls back to a read-only refresh.
    func update() async {
        guard let importedDirectory else {
            await refresh()
            return
        }
        await importDirectory(importedDirectory)
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
            importedDirectory = directory
            importedDirectorySettings.save(directory)
            let requestedQuery = query
            let snapshot = try await runtime.snapshot(query: requestedQuery)
            importSummary = summary
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
        cacheHitRateWidgetReport = nil
        quotaPresentationReport = nil
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
