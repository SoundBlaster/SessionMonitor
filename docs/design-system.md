# App Design System (SM-729)

Reusable SwiftUI visual components live in `Apps/MonitorMac/Sources/shared/ui`.
Their values live in `shared/lib/DesignTokens.swift`. They import only SwiftUI, accept content slots or
already formatted `Text`, and have no dependency on MonitorCore, a feature model or a chart policy.
This is an app-local Design System; it is not a separate Swift package or WidgetKit dependency.

| Component | Contract |
| --- | --- |
| `DesignCard` | Shared padding/radius; subdued, floating material with border/shadow, or caller-tinted surface. Adds no selection or accessibility grouping. |
| `DesignBadge` | Passive capsule with caller-provided text/tint. Status semantics remain with the feature. |
| `DesignMetric` | Caption/value with compact, standard or prominent emphasis; monospaced digits and combined accessibility. The caller supplies formatting, unknown values and optional exact accessibility values. |
| `DesignCardHeader` | Title and accessory content slots; stacks the accessory when the horizontal layout cannot fit. |
| `DesignEvidenceDisclosure` | Standard disclosure with shared evidence spacing/type styles. Requires a binding so the caller retains expansion state. |
| `DesignTokens` | Spacing, surfaces, badge opacity and metric grid minima. Domain thresholds, chart geometry and palette meanings remain outside these tokens. |

```swift
DesignCard {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
        DesignCardHeader {
            Label("Signal", systemImage: "chart.line.uptrend.xyaxis")
        } accessory: {
            DesignBadge(title: Text("Observed"))
        }
        DesignMetric(title: Text("Current value"), value: Text("95.0k"), emphasis: .prominent)
        DesignEvidenceDisclosure(title: Text("Source evidence"), isExpanded: $isExpanded) {
            Text(explanation)
        }
    }
}
```

Use `Text` to preserve localized keys/resources at the call site. Do not move token formatting, unknown
semantics or domain labels into shared UI. `ContextInsightSignalCard`, the zone card and the passive
snapshot remain feature compositions. The signal card still owns its `@State`; the snapshot still hides
its duplicate accessibility tree, and the always-mounted chart snapshot owns keyboard/VoiceOver access.
Hover observation stays in the same leaf views; policy/projection work does not move into shared UI.

## Verification

Compared with PR #116 commit `0cdec9d`, the existing six native NSHostingView fixture captures are
pixel-identical after extraction (equal dimensions, zero changed RGB pixels): light/dark chart+summary,
light/dark multiple-signal cards with expanded evidence, narrow summary with a large-type environment,
and narrow monochrome preview. The 15 targeted presentation/interaction tests pass through Xcode-tools.
Build-for-testing, SwiftLint (249 files), FSD lint/negative regression and diff checks pass.
No new live assistive-technology or Release performance measurement is claimed.

Local captures and the comparison report are under the checkout's external measurements directory,
`measurements/sm-729/native-attachments` and `visual-comparison.json`; these artifacts are not committed.
The deterministic fixtures remain in `ContextInsightPresentationTests.swift` for reproduction.
