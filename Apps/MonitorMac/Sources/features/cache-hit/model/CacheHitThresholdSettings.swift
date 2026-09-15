import Foundation
import MonitorPolicies
import Observation

@MainActor
@Observable
final class CacheHitThresholdSettings {
    static let storageKey = "cacheHit.minimumThresholdPercent"

    private(set) var thresholdPercent: Double
    var input: String
    private(set) var validationMessage: String?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let restored = defaults.object(forKey: Self.storageKey)
            .flatMap(Self.validStoredPercent)
        let value = restored ?? CacheHitThreshold.default.percent
        thresholdPercent = value
        input = Self.input(for: value)
        validationMessage = nil
    }

    var threshold: CacheHitThreshold {
        // The stored value and every committed value are validated before assignment.
        do { return try CacheHitThreshold(percent: thresholdPercent) } catch { return .default }
    }

    @discardableResult
    func commitInput() -> Bool {
        guard let value = Self.parse(input), let validated = try? CacheHitThreshold(percent: value)
        else {
            validationMessage = "Enter a number from 0 to 100."
            return false
        }
        thresholdPercent = validated.percent
        input = Self.input(for: validated.percent)
        validationMessage = nil
        defaults.set(validated.percent, forKey: Self.storageKey)
        return true
    }

    private static func parse(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = Double(trimmed), parsed.isFinite else { return nil }
        return parsed
    }

    private static func validStoredPercent(_ value: Any) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let percent = number.doubleValue
        guard percent.isFinite, CacheHitThresholdSpec().isSatisfiedBy(percent) else { return nil }
        return percent
    }

    private static func input(for value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
