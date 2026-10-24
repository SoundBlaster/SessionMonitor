import MonitorCore
import SpecificationKit
import SwiftUI

/// The selected session owns cache semantics; shared components only lay out formatted values.
struct SessionSummaryView: View {
    let session: SessionSummary
    let sessionTitle: String?
    @ObservedSatisfies<SessionReportSnapshot> private var hasCompleteCacheCoverage: Bool

    init(session: SessionSummary, provider: SessionReportContextProvider, sessionTitle: String? = nil) {
        self.session = session
        self.sessionTitle = sessionTitle
        _hasCompleteCacheCoverage = ObservedSatisfies(provider: provider, using: DisplayedCacheCoverageSpec())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
            SessionSummaryHeader(
                model: session.model, sessionTitle: sessionTitle, sessionID: session.id, cacheHit: cacheHit,
                cacheValue: hasCompleteCacheCoverage ? cacheHit.value : "—"
            )
            DesignMetricStrip(items: [
                .init(id: "sessionDetail.requests", title: Text("Requests"),
                      value: Text(session.totals.requests, format: .number)),
                .init(id: "sessionDetail.inputTokens", title: Text("Input tokens"),
                      value: Text(session.totals.inputTokens, format: .number)),
                .init(id: "sessionDetail.outputTokens", title: Text("Output tokens"),
                      value: Text(session.totals.outputTokens, format: .number)),
                .init(id: "sessionDetail.cachedInputTokens", title: Text("Known cached input"),
                      value: Text(session.totals.cachedInputTokens, format: .number))
            ])
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sessionDetail.summary")
    }

    private var cacheHit: SessionCacheHitPresentation {
        SessionCacheHitPresentation(totals: session.totals)
    }
}

private struct SessionSummaryHeader: View {
    let model: String
    let sessionTitle: String?
    let sessionID: String
    let cacheHit: SessionCacheHitPresentation
    let cacheValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.inline) {
            DesignSummaryHeading {
                Text(sessionTitle ?? (model.isEmpty ? "Unknown model" : model))
                    .lineLimit(2)
                    .help(sessionTitle ?? model)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(sessionTitle == nil ? "sessionDetail.model" : "sessionDetail.title")
            } accessory: {
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.item) {
                    Text(cacheValue)
                        .font(.title.bold()).monospacedDigit()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Cache hit")
                        .accessibilityValue(cacheHit.accessibilityValue)
                        .accessibilityIdentifier("sessionDetail.cacheHit")
                    cacheLabel.font(.callout).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    DesignInfoButton(title: Text("About cache hit")) {
                        SessionCacheHitHelp(cacheHit: cacheHit)
                    }
                    .accessibilityIdentifier("sessionDetail.cacheHelp")
                }
            }
            if sessionTitle != nil {
                Text(model.isEmpty ? "Unknown model" : model)
                    .font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("sessionDetail.model")
            }
            Text(sessionID)
                .font(.callout.monospaced()).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Session ID")
                .accessibilityValue(sessionID)
                .accessibilityIdentifier("sessionDetail.sessionID")
        }
    }

    private var cacheLabel: Text {
        switch cacheHit.state {
        case .known: Text("Cache hit")
        case .unavailable(reason: .noCanonicalRequests): Text("Cache hit · No requests")
        case .unavailable(reason: .partialCoverage): Text("Cache hit · Partial data")
        case .unavailable(reason: .zeroInput): Text("Cache hit · Zero input")
        case .unavailable(reason: .invalidTotals): Text("Cache hit · Unavailable")
        }
    }
}

private struct SessionCacheHitHelp: View {
    let cacheHit: SessionCacheHitPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
            Text("Cache hit").font(.headline)
            Text(cacheHit.explanation)
            Text("""
                 Cached input tokens ÷ input tokens. A percentage is shown only when \
                 every request has cache data and input is greater than zero.
                 """)
                .foregroundStyle(.secondary)
            Text("Canonical usage only. Legacy token_count records are excluded from these totals.")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
}
