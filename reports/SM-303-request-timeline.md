# SM-303 — request timeline and evidence

## Статус

SM-303 реализован в отдельном feature/model слое. Timeline — presentation-only: он читает canonical usage и отдельные source-evidence события, но не участвует в accounting и не изменяет `UsageQuery` или totals. ROADMAP не изменялся, PR не создавался.

## Изменённые файлы

- `Sources/MonitorCore/RequestTimeline.swift` — типы presentation model: `RequestTimeline`, точки input и `TimelineEventKind`.
- `Sources/MonitorCore/Models.swift` — перенос разобранных source-evidence событий через `ParsedRollout`.
- `Sources/CodexSource/RolloutDecoder.swift` — извлечение только явно типизированных событий без классификации по prompt text или имени файла.
- `Sources/MonitorStore/UsageStore.swift` — миграция и read-only persistence таблицы `source_timeline_events`.
- `Sources/MonitorStore/RequestTimelineStore.swift` — запрос timeline для одной exact session и периода `[since, until)`.
- `Sources/MonitorRuntime/SessionMonitor.swift` — runtime facade для timeline query.
- `Apps/MonitorMac/Sources/features/request-timeline/model/RequestTimelineModel.swift` — отдельная feature model с проверкой session/query identity.
- `Apps/MonitorMac/Sources/features/request-timeline/ui/RequestTimelineView.swift` — Swift Charts, legend, неизвестные значения, горизонтальная прокрутка chart и вертикальная прокрутка evidence.
- `Apps/MonitorMac/Sources/pages/session-explorer/*` — загрузка timeline для текущей selection, тот же absolute query/timezone и detail placement.
- `Apps/MonitorMac/Sources/app/entrypoint/SharedReportRuntime.swift` — runtime forwarding.
- `Tests/SessionMonitorTests/RequestTimelineTests.swift` — targeted core/store tests.
- `Apps/MonitorMac/Tests/SessionExplorerTests.swift` и `Apps/MonitorMac/Tests/SharedReportRuntimeTests.swift` — selection/query propagation tests.

## Источник evidence

| Что показывается | Источник | Граница классификации |
| --- | --- | --- |
| Cached input | подтверждённая запись `token_usage_record`, поля `input_tokens` и `cached_input_tokens`, через `confirmed` | cached value берётся только из явного поля; при отсутствии показывается `Unavailable` |
| Uncached input | presentation calculation `input_tokens - cached_input_tokens` для той же подтверждённой записи | это derived display value, canonical accounting не меняется |
| Human turn | явный `response_item` с `type=message` и `role=user`, либо явные `event_msg` turn-start типы | prompt text не анализируется |
| Goal / auto-continuation turn | явные `turn_kind` / `continuation_kind`, а также явные goal/continuation event types | имя rollout-файла и текст события не используются как эвристика |
| Compaction | top-level `compacted` или явно типизированное compaction event | неполный/неизвестный payload не повышается до compaction |
| Tool | явные `function_call`, `custom_tool_call`, `custom_tool_call_output` или типизированные `tool_*` event types | tool не выводится из произвольного текста |
| Wait | явно типизированные `wait`/`waiting` event types | отсутствующее evidence не считается wait |
| Unknown | неизвестный явный event type или unsupported typed response item | сохраняется как `Unknown`, без угадывания |

Usage points и source events фильтруются одинаково по абсолютному `[since, until)` и точному `sessionID`; child sessions не присоединяются к parent. Timezone влияет только на presentation metadata/formatting.

## Targeted tests

- `rtk proxy swift test --filter RequestTimelineTests` — 5/5 passed:
  - cached/uncached input без изменения accounting;
  - human и goal/continuation turns;
  - compaction/tool/wait при explicit evidence и Unknown event;
  - half-open period filtering и отсутствие child aggregation;
  - timezone presentation, empty timeline и unavailable cache.
- `xcodebuild ... test -only-testing:MonitorMacTests/SessionExplorerTests/testSelectedSessionTimelineUsesTheSameQueryAndSelection` — 1/1 passed.
- Targeted SwiftLint для изменённых Core/Store/Source/Runtime/feature/session-explorer/test файлов — 0 violations.
- `fsd-ios lint --config .fsd-ios.yml --strict --architecture` — 0 errors, 0 warnings.
- FSD boundary harness с отрицательной fixture отверг запрещённую зависимость; ожидаемый boundary check завершился `FSD_BOUNDARY_PASS`.
- `git diff --check` — passed.

Полный `make check` намеренно не запускался по scope задачи.

## Визуальные проверки

- Dark appearance: live Debug app с реальными 57 usage points — timeline section, cached/uncached legend, chart horizontal scroll и evidence list подтверждены screenshot + accessibility tree.
- Light appearance: после временного переключения системной appearance live screenshot подтвердил читаемость карточки, контраста, chart и legend; исходный Dark appearance восстановлен.
- Большое число событий: chart остаётся горизонтально прокручиваемым, evidence list — вертикально прокручиваемым внутри ограниченной высоты.
- Narrow window: отдельный screenshot resize не завершён, поскольку доступный CUA surface не предоставляет window resize API и drag по границе не сработал. Горизонтальный chart overflow проверен на текущем live viewport; узкое окно остаётся ручным follow-up для UI QA.

## Неизвестные и неподдержанные случаи

- Старые базы, созданные до migration `timeline-evidence-v1`, не имеют исторических source event rows до повторного импорта соответствующего evidence; canonical usage при этом остаётся доступным.
- У usage record без `cached_input_tokens` cached/uncached split не выводится и отображается как `Unavailable`.
- Provider-specific события без явного поддержанного type сохраняются как `Unknown` или не materialize-ятся, если payload отсутствует.
- Timeline не является causal explanation, anomaly detector или efficiency metric; эти задачи остаются за SM-304/последующими scope.

## Оставшиеся риски

- Набор поддержанных typed event names должен расширяться только по подтверждённым source schema/evidence, иначе появится риск ложной классификации.
- Большие timelines используют горизонтальный chart и ограниченный внутренний evidence viewport; это сохраняет layout, но требует usability review на экстремальных размерах.
- В live app остаются существующие AppKit/SwiftUI layout warnings, не связанные с новой feature; targeted build/test завершается успешно.
