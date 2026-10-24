import Foundation

/// Reduced input for quota presentation, not a raw observation report or anomaly history.
/// Keeps all latest-timestamp ties and the final reset-transition witnesses per presentation series.
/// Coverage counts include the entire query, including unsupported and windowless snapshots.
/// The evidence size follows the number of series and tied observations, never a fixed row limit.
public struct QuotaPresentationEvidence: Equatable, Sendable {
    public let query: UsageQuery
    public let generatedAt: Date
    public let snapshots: [UsageLimitSnapshotObservation]
    public let coverage: UsageLimitTelemetryCoverage
    public let accountCoverages: [QuotaAccountCoverage]

    public init(report: UsageLimitSnapshotReport) {
        self.init(query: report.query, generatedAt: report.generatedAt, snapshots: report.snapshots,
                  coverage: report.coverage, accountCoverages: report.accountCoverages)
    }

    public init(
        query: UsageQuery, generatedAt: Date, snapshots: [UsageLimitSnapshotObservation],
        coverage: UsageLimitTelemetryCoverage, accountCoverages: [QuotaAccountCoverage]
    ) {
        self.query = query
        self.generatedAt = generatedAt
        self.snapshots = snapshots
        self.coverage = coverage
        self.accountCoverages = accountCoverages
    }
}
