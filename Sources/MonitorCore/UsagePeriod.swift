import Foundation

/// Calendar-aligned periods resolved to absolute query bounds in the selected timezone.
public enum UsagePeriodPreset: String, Codable, CaseIterable, Hashable, Sendable {
    case all
    case today
    case lastSevenDays
    case lastThirtyDays

    /// Resolves calendar presets through the next local midnight. The resulting query always
    /// contains absolute half-open bounds, so DST changes do not require later reinterpretation.
    public func resolve(referenceDate: Date, timeZoneIdentifier: String) throws -> UsageQuery {
        let query = try UsageQuery(timeZoneIdentifier: timeZoneIdentifier)
        guard self != .all else { return query }
        guard referenceDate.timeIntervalSince1970.isFinite else { throw QueryError.invalidPeriod }

        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw QueryError.invalidTimeZone
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: referenceDate)
        guard let until = calendar.date(byAdding: .day, value: 1, to: today),
              let since = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) else {
            throw QueryError.invalidPeriod
        }
        return try UsageQuery(since: since, until: until, timeZoneIdentifier: timeZoneIdentifier)
    }

    private var dayCount: Int {
        switch self {
        case .all: 0
        case .today: 1
        case .lastSevenDays: 7
        case .lastThirtyDays: 30
        }
    }
}
