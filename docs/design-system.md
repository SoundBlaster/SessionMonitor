# App Design System (SM-729)

Reusable SwiftUI visual components live in `Apps/MonitorMac/Sources/shared/ui`.
Their values live in `shared/lib/DesignTokens.swift`. They import only SwiftUI, accept content slots or
already formatted `Text`, and have no dependency on MonitorCore, a feature model or a chart policy.
This is an app-local Design System; it is not a separate Swift package or WidgetKit dependency.

| Component | Contract |
| --- | --- |
| `DesignCard` | Shared padding/radius; subdued, floating material with border/shadow, or caller-tinted surface. Adds no selection or accessibility grouping. |
| `DesignBadge` | Passive capsule with caller-provided text/tint. Status semantics remain with the feature. |
| `DesignMetric` | Caption/value with compact, standard, prominent or summary emphasis; monospaced digits and combined accessibility. Summary uses callout labels and title2 values. The caller supplies formatting, unknown values and optional exact accessibility values. |
| `DesignMetricStrip` | One subdued surface with equal-width metric columns and vertical separators. Fits all metrics, pairs or a single column according to their natural text widths. Items provide stable IDs and formatted `Text`; each exposes its label/value separately to accessibility. |
| `DesignSummaryHeading` | Large title with a nearby, baseline-aligned accessory. Stacks the accessory and wraps the title when their natural widths do not fit. Both are caller-owned content slots. |
| `DesignInfoButton` | Labeled native info button with local presentation state and a dismissible popover. Caller supplies localized label, content and optional accessibility identifier. No domain decisions. |
| `DesignCardHeader` | Title and accessory content slots; stacks the accessory when the horizontal layout cannot fit. |
| `DesignEvidenceDisclosure` | Standard disclosure with shared evidence spacing/type styles. Requires a binding so the caller retains expansion state. |
| `DesignTokens` | Spacing, surfaces, separator width, page/help insets and metric grid minima. Domain thresholds, chart geometry and palette meanings remain outside these tokens. |

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

## Compact session summary (SM-732)

`SessionSummaryView` composes the summary heading, metric strip and info button. It retains
`SessionCacheHitPresentation` and the reactive `DisplayedCacheCoverageSpec`/SpecificationKit gate in the page.
Known zero cache remains 0%; partial coverage, zero input and no requests remain unavailable with an explicit
reason. UUID stays selectable. The summary resets its local presentation identity when the session changes.
Canonical usage, legacy exclusion, the cache formula and detailed availability explanations live only in
the info popover. There are no explanatory lines below the metric strip. Unavailable cache hit keeps a short
inline state (Partial data, Zero input, No requests or Unavailable); accessibility retains the full reason.
The detail toolbar owns icon-only Export before Inspector, retains its help/accessibility label and preserves
the existing selected-session/account checks.

The old 960 pt content cap is removed: summary and charts use the available detail width. No chart scale,
gesture or accounting behavior changes. On narrow widths the header and metrics grow vertically rather
than clipping or shrinking the values. `SessionSummaryLayoutTests` provides deterministic native fixtures
for light/dark, long model/identifier and large values with a large-type environment, plus no-request,
zero-input, partial and known-zero states. Local evidence is under `measurements/sm-732-native-final` on the
external build volume. These are native visual fixtures, not a full VoiceOver or UI automation test suite.
Xcode-tools build-for-testing and 26 targeted GUI tests passed. Computer Use confirmed the real summary,
separate metric/UUID accessibility nodes, selection changes, cache help and Escape dismissal, Export before
Inspector, a valid export opening the save panel (cancelled without writing), and the existing ambiguous-account
export guard. The app was launched through Xcode-tools with a single window; the original scope was restored.

The subsequent help-only refinement passed a fresh Xcode-tools build-for-testing, 7 targeted summary/cache
tests, SwiftLint/FSD and the negative architecture gate. Seven updated native fixtures are under
`measurements/sm-732-help-only` (xcresult `Test-MonitorMac-2026.10.21_09-52-01-+0300`).
Computer Use confirmed that the inline notes are absent and the native info popover still contains
canonical/legacy limitations, the formula and availability explanation; Escape dismisses it.
