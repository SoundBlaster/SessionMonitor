# SM-307b — internal cache hit chart widget

Дата: 2026-09-15<br>
Ветка: `feat/sm-307b-cache-hit-widget`<br>
База: `origin/main` после merge PR #24 (`29d74fd`)<br>
`ROADMAP.md`: не изменялся по явному требованию задачи.

## Выбранное место и layout decision

Виджет добавлен в верхнюю часть sidebar существующего Session Explorer — сразу после
summary totals и перед иерархическим списком сессий. Это сохраняет Pages First/FSD
границы и делает chart частью того же query/filter context, что и список.

Layout рассчитан на sidebar шириной 240–420 pt:

- при отсутствии данных используется компактный `ContentUnavailableView`;
- список marks имеет вертикальный `ScrollView`, поэтому 250+ сессий не растягивают
  весь sidebar;
- длинные и дублирующиеся display names получают укороченные уникальные axis labels;
- legend переключается между horizontal и vertical layout через `ViewThatFits`;
- chart имеет фиксированный диапазон 0–100%, threshold rule line и компактную высоту,
  а detail остаётся в существующей правой колонке.

Search filter применяется к тому же `visibleSessions`, поэтому empty state различает
пустой выбранный period и отсутствие совпадений поиска.

## Policy states → visual states

`SessionCacheHitChartDatum` создаёт ровно один datum на каждый `SessionSummary` и
делегирует классификацию `CacheHitThresholdPolicy`. Новая accounting-логика не
добавлялась.

| Policy state | Value | Visual state | Status/accessibility |
| --- | --- | --- | --- |
| `knownBelowThreshold` | `cached input tokens / input tokens × 100` | neutral bar with red accent | `Below threshold` and threshold value |
| `knownAtThreshold` | known percent | neutral monochrome bar | `At threshold` |
| `knownAboveThreshold` | known percent | neutral monochrome bar | `Above threshold` |
| `unknown` | unavailable | neutral diamond marker | `Unknown cache coverage` |
| `partialCacheCoverage` | unavailable | neutral diamond marker | `Partial cache coverage` and unknown request count |
| `zeroInput` | unavailable | neutral diamond marker | `Zero input tokens` |
| `noCanonicalRequests` | unavailable | neutral diamond marker | `No canonical requests` |

Таким образом, красный цвет используется только для known-below-threshold; нейтральные
states не становятся визуально похожими на zero. Status дополнительно передаётся
через legend, value/status callout и accessibility value.

## Threshold, legend и accessibility semantics

Threshold отображается как dashed `RuleMark` в том же 0–100% масштабе, текстом
`Minimum threshold N%` и описанием: known values ниже линии считаются low, а
unavailable coverage остаётся neutral. Используется уже validated threshold из
`CacheHitThresholdSettings`; при изменении значения SwiftUI пересчитывает policy и
datum непосредственно, без import/rescan.

Каждый mark имеет accessibility label с display name и session ID, accessibility value
с процентом/`Unavailable` и policy status. Legend явно именует `Known`, `Below
threshold` и `Unavailable`; unavailable marks используют diamond symbol. Нажатие в
chart overlay получает y-position mark и вызывает `model.selectSession(datum.id)`,
после чего detail открывается для exact session identity.

## Изменённые файлы

- `Apps/MonitorMac/Sources/app/entrypoint/SessionMonitorApp.swift` — передача одного
  observable `CacheHitThresholdSettings` в Settings и Session Explorer window.
- `Apps/MonitorMac/Sources/pages/settings/ui/MonitorSettingsPage.swift` — использование
  переданного settings object; persistence/validation не изменены.
- `Apps/MonitorMac/Sources/pages/session-explorer/ui/SessionExplorerPage.swift` —
  размещение widget и передача текущих sessions, provenance, query и selection.
- `Apps/MonitorMac/Sources/pages/session-explorer/model/SessionCacheHitChartDatum.swift` —
  policy-backed datum projection, labels и status mapping.
- `Apps/MonitorMac/Sources/pages/session-explorer/ui/SessionCacheHitChart.swift` —
  Swift Charts block, threshold line, legend, empty/large-list layout и selection.
- `Apps/MonitorMac/Tests/SessionCacheHitChartTests.swift` — targeted datum/widget
  behavior tests.
- `reports/SM-307b-cache-hit-widget.md` — этот отчёт.

Не изменялись canonical accounting, CLI, menu bar, WidgetKit, Settings persistence и
`CacheHitThresholdPolicy` из SM-307a.

## Verification evidence

Пройдено:

- targeted `SessionCacheHitChartTests`: 5/5;
- combined targeted GUI tests (`SessionCacheHitChartTests`, `SessionCacheHitTests`,
  `SessionExplorerTests`): 20/20;
- `make build-macos` — `BUILD SUCCEEDED`;
- XcodeBuildMCP `RunProject` — app launch completed on the available Xcode project tab;
- XcodeBuildMCP `BuildProject` — successful on the existing open project tab;
- `make lint` — 0 violations;
- `make lint-architecture` — 0 errors, 0 warnings;
- `make test-architecture` — exit 0; expected negative boundary fixture was exercised;
- `git diff --check` — clean.

Targeted tests cover known below/at/above, all neutral unavailable states, validated
threshold re-evaluation without reimport, empty data, 250 sessions, long/duplicate
names, identity mapping, existing live snapshot updates, period/timezone query changes,
selection preservation and Session Explorer relationship/navigation behavior.

## Visual checks

The implementation includes system `primary`/`secondary` colors, no hard-coded window
width, truncation for axis labels, `ViewThatFits` legend fallback, vertical scrolling,
and an empty state for narrow/wide data conditions. The app was launched through the
Xcode runner, but native accessibility/screenshot inspection could not be completed in
this environment: CUA returned timeout/`AXError.cannotComplete` for the hosted app,
while the clean worktree Xcode tab retained stale “Missing package product” diagnostics
despite the CLI `make build-macos` succeeding. Therefore dark/light screenshots,
interactive click verification, and pixel-level narrow/wide visual acceptance remain
follow-up evidence rather than claimed passes.

The hosted test result also reports an existing SwiftUI warning about publishing state
inside view updates; it is outside this widget change and was not used to weaken lint or
test gates.

## Ограничения и follow-up

1. Re-run `RunAllTests` and native visual inspection in a healthy Xcode session with
   resolved package products; the attempted hosted `RunAllTests` did not terminate
   within the available 300-second window.
2. Capture and review dark/light screenshots at narrow and wide window sizes, including
   long names and a large session list.
3. If the existing SwiftUI state-publication warning is addressed later, keep it as a
   separate defect/follow-up; no accounting or widget behavior depends on it.
