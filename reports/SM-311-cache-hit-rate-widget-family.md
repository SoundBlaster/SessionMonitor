# SM-311 — Cache Hit Rate Widget Family

Дата: 2026-09-19  
Ветка: `feat/sm-311-cache-hit-widget-family`  
Статус: частичная реализация, PR #29 открыт.

## Результат этого этапа

Старый `SessionCacheHitChart` показывал один bar на session, его model/session labels и
selection противоречили новому privacy contract. Он удалён из sidebar и заменён на
`CacheHitRateWidget`: reusable SwiftUI composition, принимающая только
`CacheHitRateWidgetReport`. Public presentation model не содержит session ID и model.

`MonitorCore/CacheHitRateWidget.swift` строит report из минимальных read-only observations:

- weighted period rate и delta к immediately previous equal period;
- hourly buckets для 24h и daily buckets для 7d/14d/30d в выбранной timezone;
- per-bucket P10–P90 и weighted average;
- min/max fallback для менее четырёх session samples;
- robust-z outliers на median/MAD, ограниченные presentation family limit;
- `noData`, `partialCoverage` и `notApplicable` без подмены unknown нулём.

Текущий canonical record хранит `input` и optional `cached`, но не отдельное поле
`cacheable_input_tokens`; в этом source adapter `input` является cacheable denominator,
как и в существующем cache-hit contract. Если producer начнёт отдавать отдельный
denominator, его нужно добавить в `UsageRecord` и заменить mapping без изменения
presentation formulas.

`CacheHitRateWidgetAppearance` содержит semantic palette, copy/legend strings и layout
tokens. `CacheHitRateWidgetSettings` хранит 24h/7d/14d/30d в `UserDefaults`; текущий
in-app card реагирует на snapshot revision и настройку периода без reimport. Она также
пересчитывает rolling window на каждой следующей границе local hour, чтобы records
своевременно выходили из window и hourly buckets для 24h сдвигались без нового import.

После review добавлены safeguards для presentation correctness: quarter-band axis учитывает
weighted average, но продолжает исключать isolated outliers; hourly labels используют report
timezone; а average marker центрирован над range bar. Negative delta разворачивает только
иконку, сохраняя число читаемым.

После native visual follow-up X-axis получает только фактические starts buckets и edge padding,
так что первый и последний weekday не обрезаются, а automatic date ticks не подменяют дни
недели. Для medium family используются three-letter weekday labels. Weighted average может
лежать вне unweighted P10–P90, поэтому marker display-clamp'ится внутри range bar; исходное
weighted значение остаётся в report.

После visual direction correction chart plot стал responsive 16:9, а sidebar зарезервировал
для card 240pt вместо 460pt. Grid показывает только 75–100 с шагом 5, и при narrow sidebar
labels переключаются на single-character weekdays; wider families сохраняют three-letter form.

## Проверки

- `make check-core` — полный core/CLI/performance smoke passed; новые 7 core tests passed.
- `make test-macos` — полный MonitorMac test plan passed.
- `make build-macos` — passed.
- `make lint` — 0 violations.
- `make lint-architecture` — 0 errors, 0 warnings.
- `make test-architecture` — expected negative FSD fixture detected; target exited successfully.
- `git diff --check` — passed.
- Xcode MCP `BuildProject` — passed; `RunSomeTests` for `CacheHitRateWidgetTests` — 4/4 passed.
- Native dark-mode AX and screenshot: card displays `97.0%`, `Last 7 days` and delta,
  while widget subtree exposes only aggregate distribution text; no session/model identity.
- Review regressions: targeted `CacheHitRateWidgetTests` — 7/7 passed, including weighted
  average axis, timezone-aware hourly label and next-hour refresh schedule.

## Remaining delivery

The card has no enabled tap destination yet because `cache_analytics` does not exist.
SM-401 will add an App Group, atomically published Codable snapshot and WidgetKit extension;
SM-402 will map this same card/report contract to macOS small/medium/large families and then
validate desktop-widget light/dark/Dynamic Type layouts. iOS/iPadOS host targets are not in the
current macOS-only Xcode project and therefore are not claimed by this stage.
