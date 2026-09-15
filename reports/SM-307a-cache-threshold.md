# SM-307a — cache hit threshold settings and policy

## Result

SM-307a adds a persisted minimum cache-hit threshold and a pure projection for
one `SessionSummary`. The Session Explorer layout, canonical accounting, CLI,
menu bar, WidgetKit, and `ROADMAP.md` are unchanged.

## Default and persistence

- Default threshold: **80%**.
- 80% is an explicit operational baseline for identifying a known low hit rate;
  it is below the approximately 96% aggregate cache-hit baseline documented by
  the project and therefore does not classify normal high-hit sessions as low.
- The GUI model stores a `Double` in `UserDefaults` under
  `cacheHit.minimumThresholdPercent`.
- The model accepts an injected `UserDefaults`, so two independently created
  instances restore the same value in tests and production uses `.standard`.
- Missing, non-numeric, non-finite, or out-of-range stored values are ignored
  and the model uses 80% without overwriting the corrupted value.

## Validation semantics

`CacheHitThresholdSpec` is the domain specification in `MonitorPolicies` and
accepts only finite values in the closed interval 0...100. `NaN`, positive or
negative infinity, negative values, and values above 100 are rejected.

Settings input trims whitespace, rejects empty/non-numeric input, and commits
only after successful domain validation. Invalid input keeps both the active
threshold and the persisted value unchanged and exposes a validation message
in Settings.

## Presentation states

`CacheHitThresholdPolicy.presentation(for:)` returns:

- `knownBelowThreshold` — complete known cache coverage and hit percentage
  strictly below the configured threshold;
- `knownAtThreshold` — complete known coverage and exact equality;
- `knownAboveThreshold` — complete known coverage and value above threshold;
- `unknown` — malformed/inconsistent cache totals;
- `partialCacheCoverage` — at least one request has unknown cache usage;
- `zeroInput` — canonical requests exist but input is zero;
- `noCanonicalRequests` — no confirmed canonical requests.

Only `knownBelowThreshold` is a low-cache-hit state. Unknown, partial, zero-input,
and no-canonical-request states never become low through fallback or coercion.
The policy reads `SessionSummary` and does not mutate it or its canonical totals.

## Changed files

- `Sources/MonitorPolicies/CacheHitThreshold.swift` — domain validation,
  validated threshold, and pure policy.
- `Apps/MonitorMac/Sources/features/cache-hit/model/CacheHitThresholdSettings.swift`
  — Settings model, persistence, parsing, and recovery.
- `Apps/MonitorMac/Sources/pages/settings/ui/MonitorSettingsPage.swift` —
  threshold input and validation message.
- `Apps/MonitorMac/Tests/CacheHitThresholdTests.swift` — policy, validation,
  persistence, recovery, invalid-input, and immutability tests.
- `reports/SM-307a-cache-threshold.md` — this report.

## Verification

- `make lint` — passed, 0 violations.
- `make lint-architecture` — passed, 0 errors and 0 warnings.
- `make test-architecture` — passed; its expected synthetic negative fixture
  reports one invalid dependency while the boundary check exits successfully.
- `make test-macos XCODEBUILD_FLAGS='-only-testing:MonitorMacTests/CacheHitThresholdTests'`
  — passed, 6/6 targeted GUI-hosted tests; native app/test build passed.
- `make test-core` — passed, 84 tests in 14 suites.
- `git diff --check` — passed.

## SM-307b interface contract and limitations

SM-307b can create `CacheHitThresholdPolicy(threshold:)` from the current
Settings model's validated `threshold` and project each snapshot session with
`presentation(for:)`. It should render red/accent treatment only for
`knownBelowThreshold`; all other cases need a neutral, explicit label or
tooltip. One chart datum must remain one `SessionSummary`; the policy must not
recompute, aggregate, or alter canonical totals. Threshold changes should
re-evaluate existing snapshot data without import/rescan. This change does not
implement the chart, graph interaction, or Session Explorer layout work.
