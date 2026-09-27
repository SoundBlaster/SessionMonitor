import Foundation
import MonitorCore
import MonitorRuntime
import XCTest

final class WidgetSharedSnapshotTests: XCTestCase {
    func testSnapshotRoundTripsThroughAtomicStoreWithoutIdentities() throws {
        let snapshot = try makeSnapshot()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSharedSnapshotStore(fileURL: directory.appending(path: "widget-snapshot.json"))

        try store.write(snapshot)

        XCTAssertEqual(try store.read(), snapshot)
        let data = try Data(contentsOf: store.fileURL)
        let payload = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(payload.contains("session_id"))
        XCTAssertFalse(payload.contains("model"))
        XCTAssertFalse(payload.contains("/usage.sqlite"))
        XCTAssertTrue(payload.contains("unknownObservationCount"))
    }

    func testSnapshotRejectsUnsupportedSchemaVersion() throws {
        let data = try JSONEncoder().encode(makeSnapshot())
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let futureSchema = json.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":99")
        let decoder = JSONDecoder()

        XCTAssertThrowsError(try decoder.decode(WidgetSharedSnapshot.self, from: Data(futureSchema.utf8))) {
            XCTAssertEqual($0 as? WidgetSharedSnapshotError, .unsupportedVersion(99))
        }
    }

    func testSnapshotRejectsDuplicatePeriodsAndInvalidMetrics() throws {
        let totals = UsageTotals(requests: 2, inputTokens: 100, cachedInputTokens: 90, outputTokens: 4)
        let today = try WidgetUsagePeriodSnapshot(period: .today, startsAt: .now.addingTimeInterval(-3_600),
                                                  endsAt: .now, totals: totals)
        let cache = try WidgetCachePeriodSnapshot(startsAt: .now.addingTimeInterval(-86_400), endsAt: .now,
                                                  hitRate: 90, comparisonDeltaPercentagePoints: nil,
                                                  availability: .available, sessionCount: 1, buckets: [])

        XCTAssertThrowsError(try WidgetSharedSnapshot(generatedAt: .now, timeZoneIdentifier: "UTC", revision: 1,
                                                       usage: [today, today], cache: cache))
        XCTAssertThrowsError(try WidgetCacheBucket(startsAt: .now.addingTimeInterval(-60), endsAt: .now,
                                                   lower: 95, upper: 90, average: 92, sampleCount: 1))
    }

    func testRuntimeBuildsIdentityFreeEmptySnapshotFromItsCanonicalStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = try SessionMonitor(databaseURL: directory.appending(path: "usage.sqlite"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))

        let snapshot = try await runtime.widgetSharedSnapshot(generatedAt: now, timeZone: timeZone)

        XCTAssertEqual(snapshot.schemaVersion, WidgetSharedSnapshot.currentSchemaVersion)
        XCTAssertEqual(snapshot.generatedAt, now)
        XCTAssertEqual(snapshot.usage.map(\.period), [.last7Days, .today])
        XCTAssertTrue(snapshot.usage.allSatisfy { $0.requests == 0 && $0.cacheCoverage == .empty })
        XCTAssertEqual(snapshot.cache.availability, .noData)
        XCTAssertNil(snapshot.cache.hitRate)
    }

    private func makeSnapshot() throws -> WidgetSharedSnapshot {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let totals = UsageTotals(requests: 12, inputTokens: 10_000, cachedInputTokens: 9_000,
                                 outputTokens: 500, unknownCacheRequests: 1)
        let today = try WidgetUsagePeriodSnapshot(period: .today, startsAt: now.addingTimeInterval(-3_600),
                                                  endsAt: now, totals: totals)
        let week = try WidgetUsagePeriodSnapshot(period: .last7Days,
                                                 startsAt: now.addingTimeInterval(-7 * 86_400), endsAt: now,
                                                 totals: totals)
        let outlier = try WidgetCacheOutlier(hitRate: 12, deviation: -2.8, severity: .strong)
        let bucket = try WidgetCacheBucket(startsAt: now.addingTimeInterval(-86_400), endsAt: now,
                                           lower: 80, upper: 98, average: 90, sampleCount: 4,
                                           outliers: [outlier])
        let cache = try WidgetCachePeriodSnapshot(startsAt: now.addingTimeInterval(-7 * 86_400), endsAt: now,
                                                  hitRate: nil, comparisonDeltaPercentagePoints: nil,
                                                  availability: .partial, sessionCount: 8,
                                                  unknownObservationCount: 2, buckets: [bucket])
        return try WidgetSharedSnapshot(generatedAt: now, timeZoneIdentifier: "Europe/Moscow", revision: 42,
                                        usage: [today, week], cache: cache)
    }
}
