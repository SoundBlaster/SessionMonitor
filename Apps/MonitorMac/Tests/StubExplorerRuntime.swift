import Foundation
import MonitorCore
import MonitorRuntime

@testable import SessionMonitor

actor StubExplorerRuntime: SessionExplorerRuntime {
    private struct Observer {
        let query: UsageQuery
        let continuation: AsyncThrowingStream<UsageSnapshot, Error>.Continuation
    }

    private var storedReport: UsageReport
    private var importFailure = false
    private var reportFailure = false
    private var reportAfterNextImport: UsageReport?
    private var importedDirectoryValues: [URL] = []
    private var revision: Int64 = 0
    private var observers: [UUID: Observer] = [:]
    private var delayedQuotaQuery: UsageQuery?
    private var delayedQuotaContinuation: CheckedContinuation<QuotaPresentationReport, Never>?
    private var delayedQuotaStarted = false
    private var delayedQuotaStartContinuation: CheckedContinuation<Void, Never>?
    var observerCount: Int { observers.count }
    var importedDirectories: [URL] { importedDirectoryValues }

    init(report: UsageReport) {
        storedReport = report
    }

    func replaceReport(_ report: UsageReport) {
        storedReport = report
        revision += 1
        for observer in observers.values {
            if let value = try? snapshot(query: observer.query) {
                observer.continuation.yield(value)
            }
        }
    }
    func replaceReportWithoutAdvancingWatermark(_ report: UsageReport) { storedReport = report }
    func yield(_ report: UsageReport, query: UsageQuery, revision: Int64) {
        let value = UsageSnapshot(
            query: query,
            watermark: QueryWatermark(databaseID: "fixture", revision: revision, committedAt: Date()),
            report: report
        )
        for observer in observers.values { observer.continuation.yield(value) }
    }
    func failImports() { importFailure = true }
    func failReports(_ value: Bool) { reportFailure = value }
    func replaceReportAfterNextImport(_ report: UsageReport) { reportAfterNextImport = report }
    func delayQuota(for query: UsageQuery) { delayedQuotaQuery = query }
    func waitForDelayedQuotaRequest() async {
        if delayedQuotaStarted { return }
        await withCheckedContinuation { delayedQuotaStartContinuation = $0 }
    }
    func releaseDelayedQuota() {
        guard let continuation = delayedQuotaContinuation, let query = delayedQuotaQuery else { return }
        delayedQuotaContinuation = nil
        continuation.resume(returning: quotaReport(query: query, generatedAt: Date(timeIntervalSince1970: 1)))
    }

    func importDirectory(_ directory: URL) throws -> ImportSummary {
        if importFailure { throw StubFailure.importFailed }
        importedDirectoryValues.append(directory)
        if let reportAfterNextImport {
            storedReport = reportAfterNextImport
            self.reportAfterNextImport = nil
            revision += 1
        }
        return ImportSummary(files: 1, records: 1, diagnostics: [:])
    }

    func snapshot(query: UsageQuery) throws -> UsageSnapshot {
        if reportFailure { throw StubFailure.reportFailed }
        return UsageSnapshot(query: query,
                             watermark: QueryWatermark(databaseID: "fixture", revision: revision, committedAt: Date()),
                             report: storedReport)
    }

    func timeline(sessionID: String, query: UsageQuery) throws -> RequestTimeline {
        RequestTimeline(sessionID: sessionID, query: query, points: [])
    }

    func cacheHitRateWidget(
        period: CacheHitRateWidgetPeriod, referenceDate: Date, timeZone: TimeZone,
        accountScope: UsageAccountScope
    ) -> CacheHitRateWidgetReport {
        CacheHitRateWidgetBuilder.build(
            observations: [], period: period, referenceDate: referenceDate, timeZone: timeZone
        )
    }

    func quotaPresentation(query: UsageQuery, generatedAt: Date) async throws -> QuotaPresentationReport {
        if query == delayedQuotaQuery {
            delayedQuotaStarted = true
            delayedQuotaStartContinuation?.resume()
            delayedQuotaStartContinuation = nil
            return await withCheckedContinuation { delayedQuotaContinuation = $0 }
        }
        return quotaReport(query: query, generatedAt: generatedAt)
    }

    private func quotaReport(query: UsageQuery, generatedAt: Date) -> QuotaPresentationReport {
        QuotaPresentationReport(
            query: query, generatedAt: generatedAt, freshnessThresholdSeconds: 900,
            coverage: UsageLimitTelemetryCoverage(snapshots: []), windows: []
        )
    }

    func accountProfiles() async throws -> [AccountProfile] { [] }

    func snapshots(query: UsageQuery) -> AsyncThrowingStream<UsageSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let identifier = UUID()
            do {
                continuation.yield(try snapshot(query: query))
                observers[identifier] = Observer(query: query, continuation: continuation)
                continuation.onTermination = { [weak self] _ in
                    Task { await self?.removeObserver(identifier) }
                }
            } catch { continuation.finish(throwing: error) }
        }
    }

    private func removeObserver(_ identifier: UUID) { observers[identifier] = nil }

    private enum StubFailure: LocalizedError {
        case importFailed
        case reportFailed

        var errorDescription: String? {
            switch self {
            case .importFailed: "Fixture import failure"
            case .reportFailed: "Fixture report failure"
            }
        }
    }
}
