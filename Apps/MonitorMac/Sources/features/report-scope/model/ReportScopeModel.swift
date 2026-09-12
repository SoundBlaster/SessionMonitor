import Foundation
import MonitorCore
import Observation

@MainActor
@Observable
final class ReportScopeModel {
    typealias PeriodPreset = UsagePeriodPreset

    struct ObservationID: Hashable, Sendable {
        let preset: PeriodPreset
        let timeZoneIdentifier: String
        let since: Date?
        let until: Date?
    }

    private enum StorageKey {
        static let preset = "reportScope.periodPreset"
        static let timeZone = "reportScope.timeZoneIdentifier"
    }

    private(set) var preset: PeriodPreset
    private(set) var timeZoneIdentifier: String
    private(set) var query: UsageQuery

    let timeZoneIdentifiers: [String]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let sleepUntil: @MainActor (Date) async throws -> Void
    @ObservationIgnored private var boundaryRefreshTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        currentTimeZone: TimeZone = .current,
        now: @escaping @MainActor () -> Date = Date.init,
        sleepUntil: @escaping @MainActor (Date) async throws -> Void = { boundary in
            let delay = boundary.timeIntervalSinceNow
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        }
    ) {
        self.defaults = defaults
        self.now = now
        self.sleepUntil = sleepUntil
        let identifiers = ["UTC", currentTimeZone.identifier]
        timeZoneIdentifiers = identifiers.reduce(into: []) { result, identifier in
            if !result.contains(identifier) { result.append(identifier) }
        }

        let restoredPreset = defaults.string(forKey: StorageKey.preset)
            .flatMap(PeriodPreset.init(rawValue:)) ?? .all
        let storedTimeZone = defaults.string(forKey: StorageKey.timeZone)
        let restoredTimeZone = identifiers.contains(storedTimeZone ?? "") ? storedTimeZone ?? "UTC" : "UTC"
        preset = restoredPreset
        timeZoneIdentifier = restoredTimeZone
        query = Self.makeQuery(preset: restoredPreset, timeZoneIdentifier: restoredTimeZone, now: now())
        scheduleBoundaryRefresh()
    }

    var observationID: ObservationID {
        ObservationID(
            preset: preset,
            timeZoneIdentifier: timeZoneIdentifier,
            since: query.since,
            until: query.until
        )
    }

    var title: String { preset.title }

    var compactLabel: String { "\(preset.title) · \(timeZoneIdentifier)" }

    func selectPreset(_ value: PeriodPreset) {
        guard value != preset else { return }
        preset = value
        defaults.set(value.rawValue, forKey: StorageKey.preset)
        resolveQuery()
    }

    func selectTimeZone(_ identifier: String) {
        guard timeZoneIdentifiers.contains(identifier), identifier != timeZoneIdentifier else { return }
        timeZoneIdentifier = identifier
        defaults.set(identifier, forKey: StorageKey.timeZone)
        resolveQuery()
    }

    /// Re-resolves calendar-relative presets after activation or a local day boundary.
    func refreshRelativePeriod() {
        guard preset != .all else { return }
        resolveQuery()
    }

    private func resolveQuery() {
        let resolved = Self.makeQuery(preset: preset, timeZoneIdentifier: timeZoneIdentifier, now: now())
        if resolved != query { query = resolved }
        scheduleBoundaryRefresh()
    }

    private func scheduleBoundaryRefresh() {
        boundaryRefreshTask?.cancel()
        boundaryRefreshTask = nil
        guard preset != .all, let boundary = query.until else { return }
        let sleepUntil = sleepUntil
        boundaryRefreshTask = Task { [weak self] in
            do {
                try await sleepUntil(boundary)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.query.until == boundary else { return }
            self.refreshRelativePeriod()
        }
    }

    private static func makeQuery(
        preset: PeriodPreset,
        timeZoneIdentifier: String,
        now: Date
    ) -> UsageQuery {
        do {
            return try preset.resolve(referenceDate: now, timeZoneIdentifier: timeZoneIdentifier)
        } catch {
            preconditionFailure("ReportScopeModel produced an invalid query: \(error)")
        }
    }

    deinit { boundaryRefreshTask?.cancel() }
}

extension UsagePeriodPreset {
    var title: String {
        switch self {
        case .all: "All Time"
        case .today: "Today"
        case .lastSevenDays: "Last 7 Days"
        case .lastThirtyDays: "Last 30 Days"
        }
    }
}
