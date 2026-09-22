# SM-308d — quota presentation contract

## Scope

This first SM-308d slice adds one shared quota presentation projection for CLI and
future GUI consumers. It is built from imported usage-limit observations only and
never polls a provider or derives quota from canonical token totals.

The projection keeps the latest observation for each scope/limit/window slot and
exposes:

- observed `usedPercent`;
- `remainingPercent` explicitly derived from the observed value;
- reset time and a reset discontinuity marker when the reset epoch changes;
- observation timestamp and current/stale/future freshness state;
- the original observed/partial/unknown coverage.

The decision path uses `SpecificationCore` availability specifications before
building the typed projection. Unknown values remain optional and are not converted
to zero.

## CLI behavior

`codex-monitor quota` keeps its existing JSON schema (`UsageLimitSnapshotReport`) for
automation compatibility. Human-readable output uses the shared projection and adds
`freshness=...` plus `discontinuity=reset` when applicable.

## Validation

- `UsageLimitSnapshotTests` — 8 tests passed, including derived remaining, freshness,
  reset discontinuity, and partial unknown values.
- `make check-core` — 112 tests in 17 suites, SwiftLint, CLI watch/snapshot/quota and
  performance smoke passed.
- `git diff --check` — passed.

## Remaining scope

This slice does not yet add GUI presentation, session/model quota attribution, account
profiles, model rate cards, or subscription-price estimates. Those remain separate
SM-308d/SM-308e/SM-308f work and must preserve observed versus estimated provenance.
