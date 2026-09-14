# SM-305 — legacy usage

## Выбранная семантика

Canonical остаётся единственным источником `UsageReport`: валидный
`token_usage_record` с подтверждёнными `session_id/thread_id`, native turn,
timestamp и `response_id`. Его dedup, conflict handling, fork replay и
ownership не изменены.

Legacy `event_msg/token_count` не имеет response/turn identity. `info.total_token_usage`
трактуется как cumulative snapshot, а `last_token_usage` — как mirror последнего
шага и не используется для суммирования. Первый валидный snapshot задаёт baseline
и даёт только partial coverage; следующая монотонная snapshot даёт delta.
Равная snapshot не создаёт запись. Явная all-zero snapshot начинает новый epoch
и считается reset; следующий рост даёт delta этого epoch. Ненулевое уменьшение
неразличимо от late/reversed mirror, поэтому остаётся unknown и baseline не меняет.

Дельты сохраняются как `LegacyUsageEstimate` в отдельной таблице и API
`legacyEstimates`. Они не входят в canonical SQL view, `UsageReport`, session
totals или snapshot accounting. Поэтому mirrors из другого source не выдаются
за canonical usage и автоматически не складываются. Fork replay также не может
создать canonical legacy record: у legacy нет доказуемой fork/response identity.

## Canonical, estimate и unknown

- `source_records` / `confirmed` — canonical records; только они считаются в
  `report()`.
- `source_legacy_estimates` — отдельные положительные cumulative deltas;
  optional component counters сохраняют partial coverage.
- `legacyPartialCoverage` — первый baseline snapshot; `legacyUnknownSnapshots` —
  отсутствующие/невалидные counters; `legacyReversedOrUncertain` — ненулевые
  decrease; ни один из них не считается usage.
- `legacySnapshotsNotCounted` сохранён для backward-compatible diagnostics на
  старом `info: null`/неполном legacy input.

## Fixtures и проверки

Inline fixtures в `Tests/SessionMonitorTests/AccountingTests.swift` покрывают:

- cumulative `100 → 130` (delta 30), равный mirror, reversed `50`;
- zero reset и новый epoch `0 → 20` (delta 20);
- missing/partial info;
- canonical record рядом с legacy estimate: canonical report остаётся ровно
  одним request / 100 input tokens;
- checkpoint continuation: baseline переживает restart и append import.

Пройдено:

- `swift test --filter legacyCumulativeDeltasResetsAndMirrorsRemainSeparate`
- `swift test --filter AccountingTests` (после исправления — targeted suite)
- `make lint-architecture`
- `make check-core` — повторяется после lint-only исправления; включает build,
  SwiftLint, core tests и CLI smoke harness.

Полный `make check` не запускался: GUI/menu bar не затронуты.

## Backward compatibility и ограничения

Migration `legacy-estimates-v1` additive: старые SQLite базы сохраняют все
canonical rows/checkpoints и получают пустую legacy table при открытии.
Старые checkpoints без legacy baseline безопасно продолжают импорт с partial
coverage. Нет сетевого polling, prompt/file-name эвристик или GUI изменений.

Ненулевой reset нельзя доказать без epoch marker и намеренно не поддержан.
Cross-source mirror reconciliation, legacy fork attribution и точное
пересечение legacy estimates с canonical response records требуют стабильной
identity в upstream формате; это follow-up, а не скрытая эвристика.

## Изменённые файлы

- `Sources/MonitorCore/Models.swift`
- `Sources/CodexSource/RolloutDecoder.swift`
- `Sources/MonitorStore/UsageStore.swift`
- `Sources/MonitorRuntime/SessionMonitor.swift`
- `Tests/SessionMonitorTests/AccountingTests.swift`
- `reports/SM-305-legacy-usage.md`
