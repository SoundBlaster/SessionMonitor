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

    init(
        defaults: UserDefaults = .standard,
        currentTimeZone: TimeZone = .current,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.now = now
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
        query = Self.makeQuery(preset: preset, timeZoneIdentifier: timeZoneIdentifier, now: now())
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
