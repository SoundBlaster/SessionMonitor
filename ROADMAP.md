# SessionMonitor Roadmap

Обновлено: 2026-09-12. Это основной файл приоритетов, задач и статусов проекта.
Архитектура и ограничения — в [monitor-design.md](monitor-design.md), правила
работы — в [CONTRIBUTING.md](CONTRIBUTING.md), инструкции агентам — в [AGENTS.md](AGENTS.md).

## Текущая точка

Первая версия CLI + GUI реализована и проверена. SM-101 добавляет persistent checkpoints:
неизменённые файлы читают 0 bytes, append сохраняет состояние decoder между запусками.
SM-105 переводит рост той же identity на append-only чтение хвоста. SM-103 добавляет
CLI/native watch; SM-201 добавляет read-only menu bar, SM-202 — app-owned watch controls
и lifecycle. WidgetKit, TUI и адаптация ещё не реализованы.
GitHub repository подключён; `main` отслеживает `origin/main`.
Первый commit с реализацией создан (SM-702).
SM-704 доставлена через [PR #1](https://github.com/SoundBlaster/SessionMonitor/pull/1), merge `de7e328`;
GitHub CI и ruleset для `main` включены.
SM-101 доставлена через [PR #2](https://github.com/SoundBlaster/SessionMonitor/pull/2), merge `bbddb26`.
SM-102 доставлена через [PR #3](https://github.com/SoundBlaster/SessionMonitor/pull/3), merge `f366308`.
SM-103 доставлена через [PR #4](https://github.com/SoundBlaster/SessionMonitor/pull/4), merge `14d7be5`.
SM-104 (включая SM-705) доставлена через [PR #5](https://github.com/SoundBlaster/SessionMonitor/pull/5).
**SM-105 доставлена через [PR #7](https://github.com/SoundBlaster/SessionMonitor/pull/7), merge `af7faa2`.**
**SM-201 доставлена через [PR #8](https://github.com/SoundBlaster/SessionMonitor/pull/8), merge `44929b4`.**
**SM-203 доставлена через [PR #12](https://github.com/SoundBlaster/SessionMonitor/pull/12),
merge `f6eb88a`: единое видимое product name `SessionMonitor`.**
**SM-202 завершена локально и проходит delivery через [PR #10](https://github.com/SoundBlaster/SessionMonitor/pull/10)
(2026-09-12). Следующая feature-задача: SM-301.**
По запросу пользователя 2026-09-12 добавлены SM-306/SM-307: cache hit в sidebar и
внутри приложения — график сессий с настраиваемым порогом. SM-308 планирует
дополнительную статистику и детектирование аномального расхода. Реализация запланирована.
Новые изменения выполняются только в отдельных ветках через PR; direct push в `main` запрещён.

Основной порядок: этапы 1 → 2 → 3 → 4 → 5 → 6. Этап 7 содержит сопровождение
и доставку, которые можно выполнять по необходимости. Изменение приоритетов
пользователем отражается здесь до начала зависимой работы.

## Как отмечать прогресс

- `[ ]` — запланировано. Для начатого пункта добавить `Статус: в работе` и обновить текущую точку.
- `[ ]` с `Статус: заблокировано` — указать конкретную причину и условие продолжения.
- `[x]` — критерий выполнен и проверен; рядом указать дату, результат и evidence.
- Частичная реализация остаётся `[ ]`; выполненную часть и остаток записать под пунктом.
- Перед завершением рабочей сессии обновить текущую точку и затронутые задачи.
- Сохранять IDs и историю завершённых задач. Новые требования и найденные дефекты
  добавлять отдельными пунктами, не прятать их в формулировку уже выполненного.
- Не отмечать весь этап завершённым, пока в нём остаются обязательные пункты.

## 0. Выполненная основа

Отметки ниже основаны на реализации и проверках от 2026-09-12, а не на одном плане.

- [x] **SM-001** — Создать локальный repository и перенести материалы в SessionMonitor.
  Готово 2026-09-12: `main`, материалы сохранены; commit и remote относятся к SM-702.
- [x] **SM-002** — Общее Swift/SPM-ядро и CLI `import` / `report` с text/JSON и периодом `[since, until)`.
  Готово 2026-09-12: [Package.swift](Package.swift), [CLI](Sources/MonitorCLI/MonitorCommand.swift).
- [x] **SM-003** — Canonical accounting: ownership/fork replay, dedup, conflicts, unknown counters, partial tail.
  Готово 2026-09-12: [decoder](Sources/CodexSource/RolloutDecoder.swift),
  [regression tests](Tests/SessionMonitorTests/AccountingTests.swift). Legacy estimates не входят в этот пункт.
- [x] **SM-004** — GRDB/SQLite, atomic source replacement, WAL и importer lock.
  Готово 2026-09-12: [store](Sources/MonitorStore/UsageStore.swift),
  [runtime](Sources/MonitorRuntime/SessionMonitor.swift). Межпроцессные stress tests остаются в SM-104.
- [x] **SM-005** — Первый SwiftUI Session Explorer: selection, фильтр, inspector, отдельное состояние окон.
  Готово 2026-09-12: [GUI](Apps/MonitorMac/Sources/pages/session-explorer),
  [6 GUI/model tests](Apps/MonitorMac/Tests/SessionExplorerTests.swift); выполнен visual smoke на реальных данных.
- [x] **SM-006** — SpecificationCore/Kit для coverage policy и FSD Pages First для GUI.
  Готово 2026-09-12: [policy](Sources/MonitorPolicies/CacheCoverage.swift),
  [reactive provider](Apps/MonitorMac/Sources/pages/session-explorer/model/SessionReportContextProvider.swift).
- [x] **SM-007** — Обойти подтверждённую Swift 6.4 overload ambiguity в SpecificationCore 1.0.0.
  Готово 2026-09-12: [локальный patch и provenance](Dependencies/README.md),
  [builder regression test](Tests/SessionMonitorTests/SpecificationIntegrationTests.swift). Upstream delivery — SM-701.
- [x] **SM-008** — SwiftLint, Makefile, XcodeGen, FSD lint, native build/tests и Apple Development signing.
  Готово 2026-09-12: [Makefile](Makefile), [project.yml](Apps/MonitorMac/project.yml).
  12 core tests и 6 GUI/model tests passed; positive/negative FSD gates и подпись проверены.
- [x] **SM-009** — Сверить Swift accounting с недельным Python audit.
  Готово 2026-09-12: 155 реальных rollout files, 6 340 requests; все семь usage totals совпали.
  [Локальное evidence](.build/verification.json), [сводка](README.md#проверка-результата).
- [x] **SM-010** — Проверить подключённый Xcode MCP и разделить package/app workflow.
  Готово 2026-09-12: 43 tools, успешные discovery calls; [workflow](quality-and-reuse.md).
  `SessionMonitor-Package` и `MonitorMac` имеют разные test plans.
- [x] **SM-011** — Выделить roadmap и закрепить обязательное ведение статусов.
  Готово 2026-09-12: этот файл, [AGENTS.md](AGENTS.md), [CONTRIBUTING.md](CONTRIBUTING.md);
  проверены IDs, локальные ссылки и согласованность документов.

## 1. Incremental import и watch

- [x] **SM-101** — Хранить offsets и необходимое состояние decoder вместе с импортированными событиями.
  Готово 2026-09-12: versioned checkpoints, atomic records/diagnostics/progress commit,
  restart и partial-tail recovery, stale-writer rejection, `--rescan`, CLI I/O metrics.
  Проверено: `make check-core` — 25 tests/SwiftLint; app build и 6 app/model tests;
  [fixtures](Tests/SessionMonitorTests/IncrementalImportTests.swift) покрывают rollback,
  append, UTF-8/oversized tails, ownership и изменившийся snapshot.
  На копии прежней БД: миграция 155 sources, повторный import — 155 skipped/0 bytes,
  точная parity недельного audit. [Локальное evidence](.build/sm101-verification.json).
  Первоначально prefix проверялся полным SHA256 read; SM-105 меняет контракт на append-only.
  Стадия доставки: [PR #2](https://github.com/SoundBlaster/SessionMonitor/pull/2) merged
  2026-09-12, commit `bbddb26`, после [зелёного CI](https://github.com/SoundBlaster/SessionMonitor/actions/runs/34691036600)
  на `9bc822c` (25 core + 6 app/model tests, все quality gates).
- [x] **SM-102** — Восстанавливать импорт при rotation, truncation и замене файла.
  Готово 2026-09-12: directory scan включает `*.jsonl.[0-9]+` через native Swift Regex;
  закреплён recovery/retention contract для последних snapshots наблюдённых paths.
  [Восемь lifecycle tests](Tests/SessionMonitorTests/SourceRecoveryTests.swift) проверяют
  rename/restart/append, rotation в обоих порядках paths, copytruncate, discovery,
  redelivery/conflicts, сброс ownership и partial-tail/removed-source history.
  `make check-core` — 33 tests и ноль SwiftLint violations; CLI help и повторный import
  155 sources — 0 bytes. [Локальное evidence](.build/sm102-verification.json).
  Ограничения: compressed archives не выбираются; missing paths сохраняют свои последние
  diagnostics. Старое поколение заменённого path сохраняется, если archive тоже импортирован.
  Доставка: [PR #3](https://github.com/SoundBlaster/SessionMonitor/pull/3).
  PR merged 2026-09-12, commit `f366308`, после [зелёного CI](https://github.com/SoundBlaster/SessionMonitor/actions/runs/34691595544).
- [x] **SM-103** — Добавить FSEvents watch с debounce, recovery и cancellation.
  Готово 2026-09-12: native parent-directory stream, physical-path filtering,
  bounded debounce, sticky reconciliation и retry 1–30 s; [SessionWatch](Sources/MonitorRuntime/SessionWatch.swift).
  Pause дожидается active import, resume всегда сверяет дерево, stop/cancellation
  отменяет importer и закрывает stream. CLI `watch` поддерживает SIGUSR1/SIGUSR2/SIGINT/SIGTERM,
  JSON status lines и завершение при backpressure stdout.
  Проверено: полный `make ci` — 44 core и 6 app/model tests, builds, SwiftLint/FSD,
  locked dependencies, [CLI process smoke](scripts/tests/watch-cli-smoke.py).
  [Native tests](Tests/SessionMonitorTests/NativeWatchTests.swift) покрывают реальные FSEvents,
  root rename/recreate, pause/resume и собственные DB writes; deterministic tests — dropped flags,
  in-flight events, retries, cancellation и stale callbacks. Локальное evidence: `.build/sm103-ci.log`.
  Ограничения: первоначальный root должен существовать; БД должна оставаться доступной;
  multi-process watch ownership и GUI query observation — SM-104. Prefix read policy SM-101 сохранена.
  Доставка: [PR #4](https://github.com/SoundBlaster/SessionMonitor/pull/4).
  PR merged 2026-09-12, commit `14d7be5`, после зелёного required CI на `4f81184`.
- [x] **SM-104** — Общий observable query snapshot и координация CLI/GUI между процессами.
  Готово 2026-09-12: [UsageSnapshot](Sources/MonitorCore/UsageSnapshot.swift) schema v1,
  absolute period/timezone, cache coverage и durable UUID/revision/commit-time watermark.
  Atomic GRDB snapshot, revision check раз в секунду, bounded/cancellable stream;
  CLI `snapshot --follow` и GUI observation читают external commits без нового importer.
  Watch удерживает canonical DB lease до cleanup, в том числе на pause/recovery;
  setup/migration сериализованы отдельно, symlink не обходит ownership, SIGKILL освобождает flock.
  Проверено: `make ci` — 52 core + 8 app/model tests, builds, SwiftLint/FSD и оба process harness.
  [Process tests](scripts/tests/snapshot-cli-smoke.py) покрывают external writes, idle suppression,
  concurrent first-open migrations, busy owner, alias и process death; GUI также читает commit
  отдельного SQLite process. [Atomic tests](Tests/SessionMonitorTests/QuerySnapshotTests.swift)
  сверяют totals с watermark при concurrent writes. Evidence: `.build/sm104-ci-review.log`.
  Ограничения: один native marker poll/second на consumer; промежуточные commits могут объединяться;
  marker описывает index commit, не полноту scan. Замена файла БД требует reopen runtime.
  Доставка: [PR #5](https://github.com/SoundBlaster/SessionMonitor/pull/5).
  PR merged 2026-09-12, commit `79b4259`, после зелёного required CI на `281bd58`.
- [x] **SM-105** — Зафиксировать performance baseline на реальном архиве.
  Выполнено и проверено локально (2026-09-12). По решению пользователя рост той же identity считается append-only;
  rewrite-plus-growth требует явного `--rescan`. [Baseline и методика](docs/performance/2026-09-12.md)
  доставлены через [PR #6](https://github.com/SoundBlaster/SessionMonitor/pull/6):
  release, 155 files / 1,271,886,559 bytes, три повторения.
  Median fresh / unchanged / append: 12.47 / 0.09 / 0.36 s; unchanged — 0 bytes.
  Peak RSS max: 270.92 / 12.56 / 356.23 MiB; DB/WAL/SHM — 4,894,720 bytes.
  Watch idle CPU ниже разрешения 0.01 s за 30 s; один observer — около 0.033% одного core.
  Повторный Python audit: 6,340 requests, все token totals совпали; append/full report parity подтверждена.
  Добавлены `make benchmark`, isolated copy, native time/ps metrics и synthetic CI smoke.
  Исходный baseline: append 752 bytes читал 357,981,808 bytes для проверки prefix.
  Новая реализация: checkpoint v2, resume при росте; same-size change/shrink/replacement дают rescan.
  Rewrite-plus-growth вне автоматического recovery: `--rescan` восстанавливает snapshot.
  [Повторный baseline](docs/performance/2026-09-12-append.md): 155 files / 1,286,230,037 bytes.
  Три append запуска читают ровно 752 bytes, median 0.02 s; unchanged — 0 bytes / 0.02 s.
  Fresh median 6.13 s; audit 6,340 requests и полный rebuild совпадают.
  Новый `make check-core`: 54 core tests, SwiftLint и три process harnesses passed.
  Доставка оптимизации: [PR #7](https://github.com/SoundBlaster/SessionMonitor/pull/7).
  Стадия при записи 2026-09-12 14:12 UTC: открыт, required CI/review; merge проверяется в GitHub.
  Исторический `make ci` для PR #6: 52 core + 8 app/model tests и три process harnesses passed.
  PR #6 merged 2026-09-12, commit `2b48beb`; эти цифры относятся к прежней реализации.
  Измерить first/incremental import, bytes read, peak memory, размер БД и idle CPU.
  Готово, когда append-only обновление читает только хвост (включая прежнюю partial line),
  а audit parity сохраняется. Scope уточнён пользователем 2026-09-12.

## 2. Menu bar

- [x] **SM-201** — Добавить MenuBarExtra со статусом watch и краткой сводкой.
  Выполнено и проверено локально (2026-09-12). Read-only панель на общем UsageSnapshot contract;
  GUI watch ещё не запущен, статус внешнего watcher неизвестен. Управление — SM-202.
  SharedReportRuntime разделяет default stream между окнами и панелью; навигация per-window.
  Loading/empty/error, tokens, cache coverage и время commit индекса без обещания source freshness.
  Bundle IDs по указанию пользователя: `ru.egormerkushev.SessionMonitor` / `.Tests`.
  `make lint lint-architecture test-macos`: 15 GUI/model/render tests passed, SwiftLint/FSD passed.
  Native build passed; пустая menu-панель проверена визуально, populated fixture проверен в окне.
  Native ImageRenderer: empty/partial/complete панели с большими totals проверены визуально.
  Полный actions/lifecycle visual pass — SM-202.
  Доставка: [PR #8](https://github.com/SoundBlaster/SessionMonitor/pull/8).
  Стадия при записи 2026-09-12 14:35 UTC: открыт для CI/review; merge проверяется в GitHub.
  Зависит от SM-104. Показать период, расход, cache coverage и свежесть общего snapshot;
  открытие панели не запускает новый importer или полный rescan.
- [x] **SM-202** — Действия и lifecycle menu bar.
  Реализация и verification завершены 2026-09-12.
  App-owned watch с выбором папки, pause/resume/stop; Refresh читает snapshot,
  Settings управляют значком, стандартный Quit ожидает остановку runtime, включая pending start.
  Evidence: `make generate lint lint-architecture test-macos` passed, 25 GUI tests;
  controller tests покрывают start, duplicate start, pause/resume/stop, stale status и pending shutdown,
  real-runtime test подтверждает release importer lock после shutdown paused watch.
  Render empty/partial/complete проверен. Live pass на подписанном build подтвердил menu-extra,
  Refresh без запуска importer, Open Window с единым marketing name, Settings toggle и layout,
  сохранение процесса после закрытия всех окон, повторное открытие WindowGroup и стандартный Quit
  с exit code 0. Доставка: [PR #10](https://github.com/SoundBlaster/SessionMonitor/pull/10).
  Зависит от SM-201. Open window, refresh, pause/resume, settings, quit;
  закрытие окна сохраняет watch, удаление значка не закрывает открытое окно,
  а Quit корректно завершает runtime. Проверить визуально и тестами состояний.
- [x] **SM-203** — Использовать SessionMonitor как единое видимое marketing name.
  `SessionMonitor` должно быть названием приложения, главного окна, menu bar и Settings.
  `Session Explorer` остаётся названием функциональной области в документации, а `MonitorMac` —
  внутренним именем Xcode project/target/scheme и не показывается пользователю.
  Готово, когда заголовок окна не меняется на `Session Explorer` или model name, bundle metadata
  сохраняет `SessionMonitor`, а main/empty/selected-session состояния проверены визуально.
  Выполнено локально 2026-09-12: navigation title статичен, `CFBundleDisplayName/CFBundleName`
  остаются `SessionMonitor`. `make generate lint lint-architecture test-macos` passed (15 tests);
  native empty и selected-session states проверены через accessibility tree и screenshots.
  Доставка: [PR #12](https://github.com/SoundBlaster/SessionMonitor/pull/12); стадия при записи —
  required CI passed на `ff519a8`, review/merge ещё не завершены.
- [ ] **SM-204** — Устранить AppKit reentrant `NSTableView` warnings на macOS beta.
  Обнаружено в live SM-202 pass 2026-09-12 при обновлении и открытии Session Explorer:
  AppKit сообщает, что reentrant operation в table delegate станет assert в будущей версии.
  Готово, когда причина локализована до собственного update/navigation кода или upstream SwiftUI,
  повторяемый сценарий не пишет warning, а selection, refresh и multi-window tests остаются зелёными.

## 3. Аналитический GUI и диагностика

- [ ] **SM-301** — Выбор периода/timezone и согласованные фильтры CLI/GUI.
  Готово, когда одна выборка даёт одинаковые суммы и coverage во всех интерфейсах,
  а export JSON сохраняет период, фильтры и watermark.
- [ ] **SM-302** — Названия сессий, provenance и дерево parent/subagent/fork.
  Сохранять наблюдаемые model/harness/version/effort; неизвестное явно помечать.
  Готово, когда дерево основано на source evidence и не меняет общий accounting total.
- [ ] **SM-303** — Request timeline на Swift Charts и переход к evidence.
  Зависит от SM-301/SM-302. Показать cached/uncached input, human/goal turns,
  compactions и tool/wait events; пользователь может объяснить конкретный всплеск расхода.
- [ ] **SM-304** — `sessions`, `inspect`, `doctor` и объяснимые diagnostic findings.
  Отдельно проверять repetitive polling, startup overhead и cache changes;
  учитывать нормальное ожидание, первый request turn и compaction как negative cases.
  Готово, когда finding содержит причины/evidence/confidence, а настройки читаются без изменения.
- [ ] **SM-305** — Определить и реализовать поддерживаемую legacy usage семантику.
  Fixtures должны покрыть cumulative deltas/resets, late/reversed mirrors и fork replay.
  Готово, когда estimates явно отделены от canonical records и не создают двойного учёта.
- [ ] **SM-306** — Показывать cache hit % каждой сессии в sidebar.
  Зависит от SM-104. Использовать totals сессии из текущего общего snapshot:
  `cached input tokens / input tokens × 100`, без усреднения процентов отдельных requests.
  При partial/unknown cache или нулевом input показывать «—» с объяснением coverage,
  а не 0%. Процент соответствует той же сессии и периоду, что detail view.
  Готово, когда значения обновляются вместе со snapshot, совпадают с detail/CLI,
  а длинные названия и проценты не обрезаются в узком sidebar; есть tests и visual check.
- [ ] **SM-307** — Внутренний виджет с графиком cache hit по сессиям и порогом в Settings.
  Зависит от SM-306/SM-202. Компактный Swift Charts block в Session Explorer;
  точное место выбрать и проверить в существующем layout при реализации.
  Один элемент графика соответствует одной сессии текущей выборки, значение — cache hit %.
  Основная палитра монохромная; красный акцент только для известного процента строго ниже нормы.
  Unknown/partial/zero-input обозначать нейтрально и отдельно от низкого cache hit.
  Settings: минимальный допустимый cache hit в диапазоне 0–100%, сохранение между запусками
  и немедленная переоценка графика без reimport/rescan; начальное значение определить при реализации.
  Показать порог на графике, значение и статус в подписи/tooltip; цвет не единственный сигнал.
  Выбор сессии на графике открывает её detail. Domain policy использовать совместно через
  SpecificationCore, реактивные GUI decisions — SpecificationKit; данные брать из общего snapshot.
  Это виджет внутри окна приложения, отдельный от системного WidgetKit в SM-401/SM-402.
  Готово, когда проверены значения ниже/равно/выше порога, invalid Settings, сохранение настройки,
  unknown/empty states и live updates; layout читается в light/dark mode и при большом числе сессий.
- [ ] **SM-308** — Дополнительная статистика и объяснимое детектирование аномалий расхода.
  Зависит от SM-104/SM-301/SM-302/SM-303/SM-304. Для выбранного интервала показывать model responses,
  input/cached/uncached/output tokens, cache hit и breakdown по thread, model и типу tool event;
  parent и subagents учитывать совместно и отдельно без изменения canonical total.
  Детектировать высокий абсолютный расход и темп responses/tokens, концентрацию расхода в нескольких
  threads, repetitive polling/wait density, uncached bursts и резкое ухудшение cache hit. Высокий
  cache hit сам по себе не означает низкий расход или экономию: finding должен учитывать абсолютные
  tokens, число responses и повторяемость действий. `wait`, process wait/`write_stdin`, `wait_threads`,
  `clock.sleep`, shell и goal continuations классифицировать раздельно; unknown tool/version не
  подменять нулём. Нормальное длительное event-aware ожидание должно быть negative case.
  Пороговые значения делать настраиваемыми или выводить из сопоставимого baseline/cohort, сохраняя
  evidence pointers, confidence, coverage/unknown reason и основание срабатывания; единичный дневной
  пример не становится hard-coded нормой.
  Production source для server usage snapshots — наблюдаемые usage-limit events в импортируемых
  Codex rollouts. Версионированный source adapter сохраняет в SQLite event timestamp, limit/window ID,
  duration, used percent, `resetsAt`, source/event identity и schema provenance; повторный импорт
  дедуплицирует snapshot. Приложение не создаёт сетевой polling лимитов. Unsupported schema даёт
  diagnostic и unknown coverage, а отсутствие такого события остаётся unknown.
  Server usage snapshots показывать как отдельный вспомогательный ряд: delta процента интерпретировать
  только внутри одного limit/window ID и `resetsAt`. При смене границы обозначать discontinuity и не
  приписывать разницу одному дню.
  Готово, когда GUI и CLI объясняют аномалию до конкретных threads/models/tool events и временного
  участка, а fixtures покрывают: большой расход при высоком cache hit, один dominant thread,
  polling storm, первый request, compaction, обычное длительное ожидание с прогрессом, uncached spike,
  partial/unknown telemetry, parent/subagent и duplicate/fork replay без двойного учёта, а также смену
  `resetsAt`. Проверить на обезличенном примере 2026-09-12: 2 328 responses, 286,6 млн input,
  277,0 млн cached, 9,53 млн uncached, 1,34 млн output, 96,67% cache hit, top-3 threads
  около 70%, model breakdown, 1 107 wait/polling, 857 shell и 10 `clock.sleep`; изменение server
  indicator 82% → 89% при смене `resetsAt` должно дать discontinuity, а не дневной расход 7 п.п.
  Integration test прогоняет обезличенный production-captured rollout через обычный import, проверяет
  provenance/dedup, сохранение после restart и одинаковый auxiliary series в CLI и GUI.

## 4. Системные macOS widgets

Пользователь подтвердил WidgetKit widgets на desktop/в Notification Center.
Подробности — [архитектура widgets](monitor-design.md#системные-widgets).

- [ ] **SM-401** — Shared snapshot и WidgetKit extension с App Group.
  Зависит от SM-104/SM-301. Публиковать небольшой Codable snapshot атомарно;
  extension читает его без raw logs/второго importer. Проверить entitlements и подпись.
- [ ] **SM-402** — Widgets «Расход» и «Cache», small/medium layouts.
  Зависит от SM-401; мини-графики — от SM-303. Today/7d, coverage, updated-at,
  empty/unknown/stale states и переход к тому же отчёту через deep link.
  Готово, когда метрики совпадают с GUI, layouts проверены на macOS,
  а timeline/reload соблюдают системный update budget без обещания секундной свежести.

## 5. Адаптация и связь с orchestration

- [ ] **SM-501** — Baselines и сравнение сопоставимых model/harness/config cohorts.
  Зависит от SM-302/SM-304. Учитывать effort, размер контекста, границы turns и качество результата;
  текущий config snapshot не выдавать за исторический. Готово, когда сравнение воспроизводимо.
- [ ] **SM-502** — Release monitoring и совместимость source adapters.
  Проверять публичные release metadata, помечать неизвестные форматы/версии и проверять fixtures.
  Готово, когда релиз даёт основание для проверки, а не недоказанный вывод о причине cache miss.
- [ ] **SM-503** — Проверяемые рекомендации через SpecificationCore и GUI features через SpecificationKit.
  Зависит от SM-501/SM-502. Изменять один фактор при сравнении; показывать confidence,
  rework/quality и расход на результат. Не переводить token totals в subscription quota percent.
- [ ] **SM-504** — Компактный отчёт для Parallel Subagent Orchestrator.
  Зависит от SM-304/SM-501. Отражать суммарные parent+child costs, startup и ожидания;
  чтение отчёта для решения не должно запускать постоянный LLM polling или повторять весь audit.
- [ ] **SM-505** — Управляемый config apply после проверенных рекомендаций.
  Зависит от SM-503. Concrete diff, backup, сохранение TOML comments, validation всех
  затронутых клиентов и воспроизводимый rollback; применение — в пределах запроса пользователя.

## 6. TUI

- [ ] **SM-601** — Ограниченный spike готовой Swift TUI библиотеки.
  Проверить таблицы, клавиатуру, Cyrillic/Unicode, resize, repaint и terminal cleanup.
  Готово, когда принято решение с evidence о пригодности; GUI не блокируется этим выбором.
- [ ] **SM-602** — Live TUI на общем query/watch API.
  Зависит от SM-104/SM-601. Текущие сессии, расход, coverage и findings;
  одинаковые данные с CLI/GUI и корректное восстановление терминала при выходе/ошибке.

## 7. Сопровождение и доставка

- [ ] **SM-701** — Передать SpecificationCore fix upstream и вернуть remote SwiftPM dependency.
  Готово после доступного исправленного upstream revision/release и повторной integration verification;
  до этого локальный patch остаётся с provenance и regression test.
- [x] **SM-702** — Первый scoped commit и подключение выбранного Git remote.
  Готово 2026-09-12: [commit 9473271](https://github.com/SoundBlaster/SessionMonitor/commit/9473271622011f2ae80027df5c74230adb11ead8)
  содержит CLI/app, tests, build tooling, dependency patch и документацию.
  `origin` — [SoundBlaster/SessionMonitor](https://github.com/SoundBlaster/SessionMonitor),
  `main` отслеживает `origin/main`; initial commit `74242a0` с [MIT License](LICENSE) сохранён.
  Проверено: состав 78 добавленных файлов, `git diff --cached --check`, исключение audit outputs,
  личных plot labels и signing overrides. Build/test evidence — baseline SM-008/SM-009.
- [ ] **SM-703** — Distribution packaging CLI/app/widget, notices, signing, notarization и обновления.
  Готово, когда выбранный способ доставки проверен на чистой установке с сохранением данных;
  Apple Development build сам по себе не подтверждает distribution readiness.
- [x] **SM-704** — Настроить GitHub CI и обязательный PR workflow до следующих feature tasks.
  Готово 2026-09-12: [PR #1](https://github.com/SoundBlaster/SessionMonitor/pull/1),
  [успешный CI run](https://github.com/SoundBlaster/SessionMonitor/actions/runs/34689690547)
  на `10f58a5`: Workflow lint/ShellCheck, CLI/app builds, SwiftLint/FSD positive+negative,
  12 core и 6 app/model tests, locked packages и ad-hoc signing. Локальный `make ci` также прошёл.
  [Ruleset 23038107](https://github.com/SoundBlaster/SessionMonitor/rules/23038107) включён
  и проверен через API: PR + required `CI` от GitHub Actions, strict checks, no bypass,
  запрет удаления/force push. Workflow и правила адаптированы из FSD и зафиксированы в AGENTS/CONTRIBUTING.
  Стадия доставки: PR #1 merged 2026-09-12, commit `de7e328`, после зелёного required CI.

- [x] **SM-705** — Устранить повторную линковку static packages в hosted app tests.
  Выявлено и исправлено 2026-09-12 при проверке SM-104: test target использует symbols
  host app вместо второй копии GRDB/runtime; [project.yml](Apps/MonitorMac/project.yml).
  До исправления реальный runtime test завершался GRDB thread precondition crash.
  После исправления `make test-macos` — 8 tests passed, включая external-process GUI observation;
  локальное evidence `.build/sm104-app.log`. Доставка совместно с SM-104: [PR #5](https://github.com/SoundBlaster/SessionMonitor/pull/5).

## Evidence и границы

Baseline первой версии: 12 core + 6 GUI/model tests, SwiftLint/FSD, signed native build,
visual smoke и точная parity семи usage totals. Локальные logs/xcresult и audit
исключены из Git; при их отсутствии использовать reproducible tests и не выдавать
старый результат за свежий запуск. Количество тестов относится к этому baseline.

Полный marketplace профилей, remote sync, универсальный multi-provider monitor и
автономный optimizer не входят в текущий MVP. Новые требования сначала добавляются
сюда с приоритетом, зависимостями и проверяемым критерием готовности.
