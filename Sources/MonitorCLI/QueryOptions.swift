import ArgumentParser
import Foundation
import MonitorCore

struct UsageQueryOptions: ParsableArguments {
    @Option(help: "Inclusive timezone-aware ISO 8601 start timestamp.")
    var since: String?

    @Option(help: "Exclusive timezone-aware ISO 8601 end timestamp.")
    var until: String?

    @Option(help: "Timezone identifier for presentation; timestamps remain absolute.")
    var timeZone = "UTC"

    @Option(help: "Limit the query to a mapped account profile ID; omitted means all accounts.")
    var profile: String?

    @Flag(help: "Limit the query to unmapped, unknown, or mixed account sources.")
    var unknownOrMixed = false

    func query() throws -> UsageQuery {
        guard !(profile != nil && unknownOrMixed) else {
            throw ValidationError("Use either --profile or --unknown-or-mixed, not both.")
        }
        let accountScope = profile.map(UsageAccountScope.init(profileID:))
            ?? (unknownOrMixed ? .unknownOrMixed : .allAccounts)
        do {
            return try UsageQuery(
                since: parseDate(since),
                until: parseDate(until),
                timeZoneIdentifier: timeZone,
                accountScope: accountScope
            )
        } catch QueryError.invalidPeriod {
            throw ValidationError("The --since timestamp must precede --until.")
        } catch QueryError.invalidTimeZone {
            throw ValidationError("Invalid time zone identifier: \(timeZone)")
        }
    }

    private func parseDate(_ value: String?) throws -> Date? {
        guard let value else { return nil }
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
            return date
        }
        guard let date = try? Date.ISO8601FormatStyle().parse(value) else {
            throw ValidationError("Invalid ISO 8601 timestamp: \(value)")
        }
        return date
    }
}
