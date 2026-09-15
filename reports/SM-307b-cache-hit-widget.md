# SM-307b — internal cache hit chart widget

Дата: 2026-09-15
Ветка: `fix/sm-307b-startup-freeze`
База: `origin/main` (`811f493`, после merge предыдущего SM-307b PR)
`ROADMAP.md`: не изменялся по явному требованию задачи.

## Выбранное место и layout decision

Виджет находится в верхней части sidebar Session Explorer — после summary totals и
перед иерархическим списком сессий. Он получает текущие `visibleSessions`, общий
`UsageQuery`, provenance и selection из того же `SessionExplorerModel`; accounting и
query semantics не дублируются.

Sidebar chart использует один экземпляр Swift Charts для текущей группы максимум из
8 сессий. Кнопки Previous/Next session group дают bounded paging для 250+ сессий;
основной native `List` ниже остаётся bounded scrolling surface. Chart viewport имеет
фиксированный диапазон 140–220 pt, а вместе с навигацией — максимум 248 pt.

Sidebar теперь имеет явный вертикальный контракт: `Header` фиксирован на 176 pt,
cache-hit block фиксирован на 460 pt, а `List` — единственный flexible region с
`minHeight: 0` и `maxHeight: .infinity`. Поэтому верхние блоки не зависят от числа
сессий, а `List` получает только остаток высоты parent и остаётся native bounded
scroll surface. Заголовок model и UUID в каждой строке ограничены одной строкой с
middle truncation, поэтому длинные display names не могут раздувать row height.

Sidebar, detail content и window root также получают explicit max frames;
`NavigationSplitView` дополнительно учитывает top safe area. Это ограничивает layout
в пределах content region, не меняя selection или query semantics.

## Policy states → visual states

`SessionCacheHitChartDatum` создаёт ровно один datum на каждый `SessionSummary` и
делегирует классификацию `CacheHitThresholdPolicy`.

| Policy state | Visual state | Status/accessibility |
| --- | --- | --- |
| `knownBelowThreshold` | neutral bar с красным accent | `Below threshold` и threshold value |
| `knownAtThreshold` | neutral monochrome bar | `At threshold` |
| `knownAboveThreshold` | neutral monochrome bar | `Above threshold` |
| `unknown` | neutral diamond | `Unknown cache coverage` |
| `partialCacheCoverage` | neutral diamond | `Partial cache coverage` и unknown request count |
| `zeroInput` | neutral diamond | `Zero input tokens` |
| `noCanonicalRequests` | neutral diamond | `No canonical requests` |

Красный цвет используется только для known-below-threshold. Legend, diamond symbol,
selected-session description и accessibility summary дают status-сигналы независимо
от цвета.

## Threshold, legend и accessibility semantics

Значение отображается dashed `RuleMark` в диапазоне 0–100%, текстом `Minimum threshold
N%` и описанием: known values ниже линии считаются low, unavailable coverage остаётся
neutral. В chart используется validated threshold из `CacheHitThresholdSettings`.
Изменение settings меняет policy/datum в SwiftUI сразу, без import/rescan.

Chart summary содержит количество sessions, known/below/unavailable counts и threshold;
navigation buttons остаются отдельными accessibility controls. Click overlay разрешает
нажатие по `datum.id` и вызывает `model.selectSession`, поэтому detail открывается для
точной session identity. Selection сохраняется при live snapshot update, period/query и
timezone changes по существующим model semantics.

## Startup freeze fix

Первоначальная реализация передавала все session indices в `AxisMarks` и строила chart
height как `26pt × count + 28`; при 250 sessions это давало более 6,500 pt intrinsic
layout. Более того, fresh sample показал отдельный существующий hot path: detail
`RequestTimelineView` строил Charts из 2,545 points выбранной сессии.

Исправлено:

- cache-hit chart materializes only the current page (8 marks, максимум 8 Y-axis labels);
- `axisMarkIndices` и chart viewport имеют bounded contracts, без thousand-point layout;
- navigation controls дают доступ к остальным sessions, а complete session `List`
  остаётся прокручиваемой;
- request timeline сохраняет полный `RequestTimeline` и полный evidence list, но в
  Chart использует deterministic representative projection с максимум 256 marks,
  сохраняя first/last bounds и semantic-event preference. Это presentation-only change;
  canonical accounting и loaded evidence не меняются.

## Изменённые файлы

- `Apps/MonitorMac/Sources/pages/session-explorer/ui/SessionCacheHitChart.swift` —
  one-page chart, bounded viewport, sparse axis, paging и accessible summary.
- `Apps/MonitorMac/Sources/pages/session-explorer/ui/SessionExplorerPage.swift` —
  explicit `Header → fixed Chart → flexible List` sidebar layout, bounded
  long-name rows, sidebar/detail frames и top safe-area containment.
- `Apps/MonitorMac/Sources/app/entrypoint/SessionMonitorApp.swift` —
  window content fills available bounded area.
- `Apps/MonitorMac/Sources/features/request-timeline/ui/RequestTimelineView.swift` —
  capped presentation marks for dense detail timelines; full evidence remains available.
- `Apps/MonitorMac/Tests/SessionCacheHitChartTests.swift` — policy, identity, empty,
  long/duplicate labels and 192/250/512-session viewport regression/performance contract.
- `Apps/MonitorMac/Tests/RequestTimelineAxisTests.swift` — dense 2,545-point chart cap
  and first/last bounds regression.
- `reports/SM-307b-cache-hit-widget.md` — this report.

Canonical accounting, CLI, menu bar, WidgetKit, Settings persistence and
`CacheHitThresholdPolicy` не изменялись.

## Verification evidence

Пройдено:

- `make test-macos` / full `MonitorMac` test plan: **63/63 passed**;
- targeted `SessionCacheHitChartTests` + `RequestTimelineAxisTests`: **18/18 passed**;
- `make build-macos`: **BUILD SUCCEEDED**;
- Xcode-tools `BuildProject`: **project built successfully**;
- Xcode-tools targeted layout/identity tests: **3/3 passed**;
- `make lint`: **0 violations**;
- `make lint-architecture`: **0 errors, 0 warnings**;
- `make test-architecture`: **exit 0**; expected negative boundary fixture was exercised;
- `git diff --check`: clean.

Current full test result bundle:
`.build/quality/20260915T182247-DFDF48E5-ED2D-4AE3-9A9C-72C08844EA8B.xcresult`.

Previous targeted result bundle:
`.build/quality/sm307b-freeze-targeted-final5.xcresult`.

В targeted result остаётся существующее SwiftUI runtime warning о publishing changes
inside view updates; оно не связано с новым projection/layout contract и не использовано
для ослабления lint/test gates.

Xcode-tools discovery использовал clean tab `windowtab2`, scheme `MonitorMac`, destination
`My Mac` arm64/macOS 27. На этой ревизии `BuildProject` и `RunProject` завершились
успешно; приложение запущено с PID `59893`. CLI через тот же Xcode 27 toolchain также
собрал проект успешно.

## Instruments / startup evidence

До финального dense-timeline cap: процесс `45725` достиг physical footprint 1.6G,
держал 100% CPU и не создал окно за 27 s. Sample
`.build/quality/sm307b-final-hot.sample.txt` показал 2,320/2,320 main-thread samples
в `AttributeGraph`/`Charts`, через `DynamicViewList`, `ForEachState` и `Canvas`.

После финального cap и bounded layout: процесс `48053` на актуальном Debug build после
загрузки реального локального archive достиг sleeping state: `ps` показал 0.1% CPU и
230,704 KB RSS. Sample `.build/quality/sm307b-final-layout-idle.sample.txt` за 3 s
показал 2,342 main-thread samples, из которых 2,316 были в `mach_msg`, без
Charts/AttributeGraph loop. `vmmap -summary` показал 143.5M physical footprint и
239.3M peak. Instruments trace:
`.build/quality/Attach_48053_2026-09-15_19.38.03_A94453C1.trace`, Time Profiler,
15.842 s, PID 48053, завершён по time limit.

Это startup/event-loop evidence, а не обещание конкретного first-frame FPS или memory
ceiling. В данном hosted LaunchServices probe приложение осталось без AX-visible window,
поэтому этот результат не используется как ручная visual acceptance.

## Visual checks

Пользовательский screenshot зафиксировал дефект: sidebar и detail content визуально
заходили в toolbar/titlebar area, а large chart мог раздвигать split layout. Кодовая
правка добавляет top safe-area containment и bounded frames для root/sidebar/detail,
плюс bounded chart paging.

Проверка dark/light, narrow/wide window, длинных display names, 250+ sessions,
threshold line/legend и click-to-detail через native AX/screenshot runner в этом
окружении не завершилась: Xcode runner недоступен из-за package-cache/XPC ошибок, а
LaunchServices probe не создал видимое окно. Поэтому pixel-level visual pass и ручной
click/scroll acceptance остаются явно непроверенными, без искусственного ослабления
lint или тестов.

## Ограничения и follow-up

1. Нужен повторный `RunAllTests` и native visual walkthrough в здоровой Xcode session
   с resolved package products.
2. Нужны verified screenshots в light/dark при узком и широком размере окна, включая
   250+ sessions и long names; отдельно проверить, что safe-area correction не создаёт
   лишний top gap.
3. Representative timeline chart намеренно не заменяет полный evidence list; если
   потребуется pixel-precise inspection каждого события, использовать список или
   отдельный detail interaction, не возвращая все points в один Chart.
