import Foundation
import MonitorCore
import Observation

@MainActor
@Observable
final class ReportScopeModel {
    typealias PeriodPreset = UsagePeriodPreset

    enum AccountSelection: Hashable, Identifiable {
        case allAccounts
        case profile(String)
        case unknownOrMixed

        var id: String {
            switch self {
            case .allAccounts: "all"
            case let .profile(id): "profile:\(id)"
            case .unknownOrMixed: "unknown"
            }
        }

        var usageScope: UsageAccountScope {
            switch self {
            case .allAccounts: .allAccounts
            case let .profile(id): UsageAccountScope(profileID: id)
            case .unknownOrMixed: .unknownOrMixed
            }
        }
    }

    struct ProfileOption: Identifiable, Equatable {
        let id: String
        let label: String
        let isSelectable: Bool
        let sourceCount: Int
        let assignedSourceCount: Int
        let mixedSourceCount: Int

        var hasMixedSources: Bool { mixedSourceCount > 0 }
    }

    struct ObservationID: Hashable, Sendable {
        let preset: PeriodPreset
        let timeZoneIdentifier: String
        let since: Date?
        let until: Date?
        let accountScope: UsageAccountScope
    }

    private enum StorageKey {
        static let preset = "reportScope.periodPreset"
        static let timeZone = "reportScope.timeZoneIdentifier"
        static let account = "reportScope.accountSelection"
    }

    private(set) var preset: PeriodPreset
    private(set) var timeZoneIdentifier: String
    private(set) var query: UsageQuery
    private(set) var accountSelection: AccountSelection
    private(set) var profiles: [ProfileOption] = []
    private(set) var profileCatalogError: String?

    let timeZoneIdentifiers: [String]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let sleepUntil: @MainActor (Date) async throws -> Void
    @ObservationIgnored private let profileProvider: (@Sendable () async throws -> [AccountProfile])?
    @ObservationIgnored private var boundaryRefreshTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        currentTimeZone: TimeZone = .current,
        now: @escaping @MainActor () -> Date = Date.init,
        profileProvider: (@Sendable () async throws -> [AccountProfile])? = nil,
        sleepUntil: @escaping @MainActor (Date) async throws -> Void = { boundary in
            let delay = boundary.timeIntervalSinceNow
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        }
    ) {
        self.defaults = defaults
        self.now = now
        self.sleepUntil = sleepUntil
        self.profileProvider = profileProvider
        let identifiers = ["UTC", currentTimeZone.identifier]
        timeZoneIdentifiers = identifiers.reduce(into: []) { result, identifier in
            if !result.contains(identifier) { result.append(identifier) }
        }

        let restoredPreset = defaults.string(forKey: StorageKey.preset)
            .flatMap(PeriodPreset.init(rawValue:)) ?? .all
        let storedTimeZone = defaults.string(forKey: StorageKey.timeZone)
        let restoredTimeZone = identifiers.contains(storedTimeZone ?? "") ? storedTimeZone ?? "UTC" : "UTC"
        let restoredAccountSelection = Self.restoreAccountSelection(defaults.string(forKey: StorageKey.account))
        accountSelection = restoredAccountSelection
        preset = restoredPreset
        timeZoneIdentifier = restoredTimeZone
        query = Self.makeQuery(preset: restoredPreset, timeZoneIdentifier: restoredTimeZone,
                               accountSelection: restoredAccountSelection, now: now())
        scheduleBoundaryRefresh()
    }

    var observationID: ObservationID {
        ObservationID(
            preset: preset,
            timeZoneIdentifier: timeZoneIdentifier,
            since: query.since,
            until: query.until,
            accountScope: query.accountScope
        )
    }

    var title: String { preset.title }

    var accountLabel: String {
        switch accountSelection {
        case .allAccounts: return "All accounts"
        case .unknownOrMixed: return "Unknown/Mixed"
        case let .profile(id):
            guard let profile = profiles.first(where: { $0.id == id }) else { return id }
            guard profile.hasMixedSources else { return profile.label }
            let coverage = profile.isSelectable ? "Partial" : "Mixed"
            return "\(profile.label) · \(coverage)"
        }
    }

    var compactLabel: String { "\(preset.title) · \(accountLabel)" }

    var selectedProfileIsUnavailable: Bool {
        guard case let .profile(id) = accountSelection else { return false }
        return profiles.first(where: { $0.id == id })?.isSelectable == false
    }

    var selectedProfileHasMixedSources: Bool {
        guard case let .profile(id) = accountSelection else { return false }
        return profiles.first(where: { $0.id == id })?.hasMixedSources == true
    }

    var selectedProfileMixedSourceCount: Int {
        guard case let .profile(id) = accountSelection else { return 0 }
        return profiles.first(where: { $0.id == id })?.mixedSourceCount ?? 0
    }

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

    func selectAccount(_ value: AccountSelection) {
        guard value != accountSelection else { return }
        if case let .profile(id) = value,
           profiles.first(where: { $0.id == id })?.isSelectable != true { return }
        accountSelection = value
        defaults.set(value.id, forKey: StorageKey.account)
        resolveQuery()
    }

    func refreshProfiles() async {
        guard let profileProvider else { return }
        do {
            let entries = try await profileProvider()
            let grouped = Dictionary(grouping: entries, by: \.id)
            profiles = grouped.map { id, roots in
                let label = roots.map(\.label).sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                }.first ?? id
                let assignedCount = roots.filter { $0.mappingState == .assigned }.count
                let mixedCount = roots.filter { $0.mappingState == .mixed }.count
                return ProfileOption(id: id, label: label,
                              isSelectable: roots.contains { $0.mappingState == .assigned },
                              sourceCount: roots.count,
                              assignedSourceCount: assignedCount,
                              mixedSourceCount: mixedCount)
            }.sorted {
                let comparison = $0.label.localizedCaseInsensitiveCompare($1.label)
                return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
            }
            profileCatalogError = nil
            if case let .profile(id) = accountSelection, !grouped.keys.contains(id) {
                selectAccount(.allAccounts)
            }
        } catch {
            profileCatalogError = error.localizedDescription
        }
    }

    /// Re-resolves calendar-relative presets after activation or a local day boundary.
    func refreshRelativePeriod() {
        guard preset != .all else { return }
        resolveQuery()
    }

    private func resolveQuery() {
        let resolved = Self.makeQuery(preset: preset, timeZoneIdentifier: timeZoneIdentifier,
                                      accountSelection: accountSelection, now: now())
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
        accountSelection: AccountSelection,
        now: Date
    ) -> UsageQuery {
        do {
            let periodQuery = try preset.resolve(referenceDate: now, timeZoneIdentifier: timeZoneIdentifier)
            return try UsageQuery(since: periodQuery.since, until: periodQuery.until,
                                  timeZoneIdentifier: timeZoneIdentifier,
                                  accountScope: accountSelection.usageScope)
        } catch {
            preconditionFailure("ReportScopeModel produced an invalid query: \(error)")
        }
    }

    private static func restoreAccountSelection(_ value: String?) -> AccountSelection {
        guard let value else { return .allAccounts }
        if value == "all" { return .allAccounts }
        if value == "unknown" { return .unknownOrMixed }
        if value.hasPrefix("profile:"), value.count > "profile:".count {
            return .profile(String(value.dropFirst("profile:".count)))
        }
        return .allAccounts
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
