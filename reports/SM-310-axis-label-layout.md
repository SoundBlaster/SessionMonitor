# SM-310 — Request timeline Y-axis label layout

## Причина clipping

`RequestTimelineView` задавал chart фиксированную высоту `250pt`, но не резервировал
вертикальный padding для plot dimension. При больших token values верхняя Y-axis mark
(например, `300,000`) размещалась вплотную к верхней границе chart и glyph частично
выходил за card bounds.

## Выбранное исправление

Добавлен штатный Swift Charts scale inset:

```swift
.chartYScale(range: .plotDimension(padding: RequestTimelineChartLayout.yAxisTopInset))
```

Inset составляет `16pt`; высота chart, data marks, Y-domain, X-domain, absolute
timestamps, accounting и горизонтальный `ScrollView` не менялись. Accessibility label
вынесен в единый layout contract и сохранён без сокращения.

## Targeted tests

`RequestTimelineAxisTests`: 11 tests passed, включая:

- безопасный верхний inset;
- large token values;
- zero/small values;
- Fit to data, Last events и Full query;
- empty timeline;
- полный accessibility label;
- существующие проверки absolute span, navigation и timezone.

Команда:

```text
xcodebuild ... -only-testing:MonitorMacTests/RequestTimelineAxisTests test
```

## Визуальные проверки

- Реальный Session Explorer с reported high-token session `01a06e61-3787-7852-b66b-5a8465d86716`.
- Dark appearance: верхняя подпись `300,000` полностью видима внутри chart/card.
- Accessibility tree сохранил `requestTimeline.chart`, полное описание
  `Cached and uncached input over time`, range controls и horizontal scroll actions.
- Launch override для light appearance был выполнен, но приложение осталось в dark
  appearance; отдельный light screenshot не получен.

## Оставшиеся ограничения

- Light-specific screenshot verification требует переключения appearance через UI/System
  Settings; код использует системные цвета и не содержит appearance-specific ветвления.
- Существующие runtime warnings SwiftUI/Charts (`Publishing changes from within view
  updates`, fixed mark dimension и custom UnitPoint) не относятся к SM-310 и не изменялись.
