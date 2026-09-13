# SM-309 — fix request timeline axis and navigation

## Причина бага

В исходном `RequestTimelineView` ширина графика вычислялась как `max(480, points.count * 28)`, а горизонтальная прокрутка включалась после порога количества точек. Это связывало геометрию оси с количеством запросов, но не с расстоянием между их абсолютными `Date`-значениями. Поэтому sparse session с большим gap получала неудобный масштаб и не имела явного перехода к последнему кластеру.

## Модель domain/navigation

- `dataBounds` — точные минимальная и максимальная даты фактических событий; `dataDomain` добавляет детерминированный padding (8%, минимум 30 секунд, максимум 5 минут).
- `queryDomain` строится из исходного `UsageQuery` и сохраняет его абсолютные границы. Для неограниченного All Time используется наблюдаемый span, а не искусственный бесконечный диапазон.
- По умолчанию выбран `Fit to data`: он показывает весь фактический span без растягивания до широкого query.
- `Last events` — детерминированное trailing-окно 15 минут, заканчивающееся последним событием; это навигация к последнему кластеру без эвристического поиска кластеров.
- `Full query` возвращает выбранный bounded query range; для unbounded query явно показывает наблюдаемый span.
- Ширина графика вычисляется по длительности текущего видимого `Date`-диапазона, не по `points.count`. `ScrollView(.horizontal)` получает индикаторы только когда preferred width больше измеренного viewport.
- Evidence list сохраняет все точки и отображает секунды. Timezone применяется только к `Date.FormatStyle` подписей и строк, поэтому абсолютное положение событий не меняется.
- Picker, текущее описание диапазона и chart hint доступны в accessibility tree.

## Изменённые файлы

Основные изменения SM-309:

- `Apps/MonitorMac/Sources/features/request-timeline/model/RequestTimelineModel.swift`
- `Apps/MonitorMac/Sources/features/request-timeline/ui/RequestTimelineView.swift`
- `Apps/MonitorMac/Tests/RequestTimelineAxisTests.swift`
- `reports/SM-309-timeline-axis-fix.md`

Поддержка отображения уже существующей timeline evidence и сохранение выбранной сессии/query:

- `Apps/MonitorMac/Sources/app/entrypoint/SharedReportRuntime.swift`
- `Apps/MonitorMac/Sources/pages/session-explorer/model/SessionExplorerModel.swift`
- `Apps/MonitorMac/Sources/pages/session-explorer/ui/SessionDetailView.swift`
- `Apps/MonitorMac/Sources/pages/session-explorer/ui/SessionExplorerPage.swift`
- `Apps/MonitorMac/Tests/SessionExplorerTests.swift`
- `Apps/MonitorMac/Tests/SharedReportRuntimeTests.swift`
- `Sources/MonitorCore/Models.swift`
- `Sources/MonitorCore/RequestTimeline.swift`
- `Sources/CodexSource/RolloutDecoder.swift`
- `Sources/MonitorStore/RequestTimelineStore.swift`
- `Sources/MonitorStore/UsageStore.swift`
- `Sources/MonitorRuntime/SessionMonitor.swift`
- `Tests/SessionMonitorTests/RequestTimelineTests.swift`

Эта plumbing-часть читает presentation evidence по точному `sessionID + UsageQuery`; canonical accounting и Store query semantics не изменяются.

## Targeted tests и проверки

- `rtk proxy swift test --filter RequestTimelineTests` — 5/5 passed.
- Targeted Xcode test:
  `RequestTimelineAxisTests` — 6/6 passed;
  `SessionExplorerTests/testSelectedSessionTimelineUsesTheSameQueryAndSelection` — 1/1 passed;
  result bundle: `.build/sm309-targeted-4.xcresult`.
- SwiftLint для затронутых Swift-файлов: 0 violations, 0 serious.
- `rtk proxy fsd-ios lint --config .fsd-ios.yml --strict --architecture` — 0 errors, 0 warnings.
- `rtk proxy git diff --check` — passed.
- Полный `make check` не запускался по scope задачи.

Покрыты: два разнесённых кластера, data span меньше query span, события в начале и конце диапазона, dense timeline, empty state, переключение `Fit to data` / `Last events` / `Full query`, timezone presentation, сохранение selection/query и отсутствие изменения accounting totals.

## Визуальная проверка

На реальной локальной базе выбран session `01a06e61-3787-7852-b66b-5a8465d86716`: 36 requests, два видимых кластера — примерно `00:44–00:46` и `11:34–11:35` Europe/Moscow. В dark appearance через accessibility tree и screenshot проверены:

- Fit to data показывает оба кластера без большой пустой query-области;
- Last events переводит видимую область к позднему кластеру и сообщает trailing window;
- Full query возвращает полный абсолютный диапазон;
- смена UTC ↔ Europe/Moscow меняет подписи, но не события и не selection;
- chart сообщает `Scroll Left` / `Scroll Right`, когда preferred width превышает viewport;
- диапазон, режимы и объяснение текущего состояния присутствуют в accessibility tree.

Широкий viewport проверен. Узкое окно не удалось надёжно изменить через доступный native UI automation surface: попытка resize не изменила геометрию окна, поэтому отдельное визуальное утверждение для минимальной ширины не делается. Light appearance также не удалось подтвердить: запуск с override appearance оставался dark; системные настройки после проверки восстановлены в dark и timezone приложения — в UTC.

## Ограничения и follow-ups

- `Last events` использует фиксированное 15-минутное окно; кластеризация и anomaly heuristics намеренно не добавлялись.
- Swift Charts в targeted run выдал предупреждения о fixed mark dimension и UnitPoint anchor; они не влияют на результат тестов и не относятся к accounting.
- Для старых баз без импортированной evidence timeline остаётся пустой до повторного импорта источника; данные не синтезируются молча.
- Отдельная проверка физического narrow-window layout и light appearance требует доступного способа изменить размер/appearance окна и может быть follow-up к visual QA.

