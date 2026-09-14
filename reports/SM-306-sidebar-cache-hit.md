# SM-306 — cache hit percentage in Session Explorer sidebar

Дата: 2026-09-14
Ветка: `feat/sm-306-sidebar-cache-hit`

## Результат

Sidebar показывает `Cache hit` для каждой сессии из `SessionSummary.totals` текущего
`UsageSnapshot`. Detail использует тот же presentation projection и выбранную session
identity. Значения обновляются при `SessionExplorerModel.apply(snapshot:)`, то есть вместе
с query snapshot без отдельного import/rescan.

## Формула и состояния coverage

Для известной coverage используется только агрегат текущей сессии:

```text
cached input tokens / input tokens * 100
```

Процент доступен, когда есть подтверждённые canonical requests, нет unknown cache
requests и `inputTokens > 0`. Поэтому реальные `0.0%`, `50.0%` и `100.0%` сохраняются.

В остальных состояниях sidebar и detail показывают `—`, а tooltip/accessibility value
объясняют причину:

- no canonical requests;
- partial cache coverage с количеством requests с unknown cache usage;
- zero input tokens;
- неконсистентные totals как защитное состояние.

Проценты отдельных requests не усредняются. Relationship state (`Unknown`, `Orphan`,
`Conflict`, `Cycle` и остальные) по-прежнему поступает из `SessionTreeNode.state`.

## Изменённые файлы

- `Apps/MonitorMac/Sources/pages/session-explorer/model/SessionCacheHitPresentation.swift`
  — reusable GUI projection и coverage explanations на базе `HasCompleteCacheCoverageSpec`.
- `Apps/MonitorMac/Sources/pages/session-explorer/ui/SessionExplorerPage.swift`
  — sidebar row с cache hit, compact numeric layout, wrapping длинных названий и
  accessibility/help text.
- `Apps/MonitorMac/Sources/pages/session-explorer/ui/SessionDetailView.swift`
  — тот же projection/reason text в detail.
- `Apps/MonitorMac/Tests/SessionCacheHitTests.swift`
  — targeted SM-306 tests.
- `Apps/MonitorMac/Tests/SessionExplorerTests.swift`
  — существующий shared stub сделан доступным для targeted test file.

`ROADMAP.md`, canonical accounting, CLI, menu bar и WidgetKit не изменялись.

## Проверки

- Xcode `RunSomeTests`, scheme `MonitorMac`: **5/5 passed** — 0/50/100%,
  partial/unknown/zero-input, period/timezone change, snapshot update without import,
  sidebar/detail totals.
- Xcode `RunProject`: build and launch successful; no build errors.
- Xcode `RunAllTests`, scheme `MonitorMac`: **50/50 passed**, no skipped or failed tests.
- `rtk proxy make lint`: **passed**, 0 violations in 71 Swift files.
- `rtk proxy make test-architecture`: **passed**; the negative FSD boundary fixture was
  rejected as expected.
- `rtk proxy git diff --check`: **passed**.
- `rtk proxy make lint-architecture`: **baseline failure outside SM-306** —
  `Apps/MonitorMac/Sources/features/report-scope/ui/ReportScopeControls.swift` is
  reported as `features` referencing higher-layer `State`; this file is unchanged by
  SM-306.

## Visual verification and limitations

На актуальном Xcode-built приложении проверен dark appearance и узкий sidebar около
243 px: cache hit виден в строках, проценты не обрезаются, `Root`/`Orphan`/`Unknown`
relationship labels остаются читаемыми, detail показывает тот же процент.
Длинных display names и partial/zero-input записей в импортированном live archive для
ручной проверки не оказалось; wrapping и `—`/explanations покрыты кодом и targeted tests.
Отдельный light screenshot на этом host получить не удалось: macOS appearance override
не был принят запущенным SwiftUI окном. Цвета используют adaptive SwiftUI API
(`.background`, `.secondary`, `.quaternary`, `.bar`), без hard-coded light/dark fills.
