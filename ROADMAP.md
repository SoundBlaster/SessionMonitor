# SessionMonitor Roadmap

Обновлено: 2026-09-12. Это основной файл приоритетов, задач и статусов проекта.
Архитектура и ограничения — в [monitor-design.md](monitor-design.md), правила
работы — в [CONTRIBUTING.md](CONTRIBUTING.md), инструкции агентам — в [AGENTS.md](AGENTS.md).

## Текущая точка

Первая версия CLI + GUI реализована и проверена. SM-101 добавляет persistent checkpoints:
неизменённые файлы читают 0 bytes, append сохраняет состояние decoder между запусками.
Для проверки изменённого файла пока перечитывается старый prefix; watch, menu bar,
WidgetKit, TUI и адаптация ещё не реализованы.
GitHub repository подключён; `main` отслеживает `origin/main`.
Первый commit с реализацией создан (SM-702).
SM-704 доставлена через [PR #1](https://github.com/SoundBlaster/SessionMonitor/pull/1), merge `de7e328`;
GitHub CI и ruleset для `main` включены.
**Текущая доставка: SM-101 реализована и проверена локально; [PR #2](https://github.com/SoundBlaster/SessionMonitor/pull/2) открыт, ожидает CI/review.**
**Следующая задача: SM-102 — восстановление импорта при изменениях файлов.**
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
  Ограничение: изменённый prefix проверяется полным SHA256 read (оптимизация — SM-105).
  Стадия доставки: [PR #2](https://github.com/SoundBlaster/SessionMonitor/pull/2) открыт,
  ожидает обязательный CI/review; ещё не в `main`.
- [ ] **SM-102** — Восстанавливать импорт при rotation, truncation и замене файла.
  Зависит от SM-101. Готово, когда смена identity/содержимого вызывает нужный rescan,
  а переименование или повторная доставка canonical records не удваивают суммы.
- [ ] **SM-103** — Добавить FSEvents watch с debounce, recovery и cancellation.
  Зависит от SM-102. Готово, когда append обновляет БД, dropped/coalesced events
  восстанавливаются через reconciliation, pause/resume имеет явную семантику.
- [ ] **SM-104** — Общий observable query snapshot и координация CLI/GUI между процессами.
  Зависит от SM-103. Snapshot содержит schema version, период/timezone, coverage и watermark.
  Готово, когда GUI видит external writes, два клиента не создают двух importers,
  а завершение процесса освобождает lock; это подтверждено process tests.
- [ ] **SM-105** — Зафиксировать performance baseline на реальном архиве.
  Измерить first/incremental import, bytes read, peak memory, размер БД и idle CPU.
  Готово, когда повторное обновление читает только изменения, а audit parity сохраняется.

## 2. Menu bar

- [ ] **SM-201** — Добавить MenuBarExtra со статусом watch и краткой сводкой.
  Зависит от SM-104. Показать период, расход, cache coverage и свежесть общего snapshot;
  открытие панели не запускает новый importer или полный rescan.
- [ ] **SM-202** — Действия и lifecycle menu bar.
  Зависит от SM-201. Open window, refresh, pause/resume, settings, quit;
  закрытие окна сохраняет watch, удаление значка не закрывает открытое окно,
  а Quit корректно завершает runtime. Проверить визуально и тестами состояний.

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

## Evidence и границы

Baseline первой версии: 12 core + 6 GUI/model tests, SwiftLint/FSD, signed native build,
visual smoke и точная parity семи usage totals. Локальные logs/xcresult и audit
исключены из Git; при их отсутствии использовать reproducible tests и не выдавать
старый результат за свежий запуск. Количество тестов относится к этому baseline.

Полный marketplace профилей, remote sync, универсальный multi-provider monitor и
автономный optimizer не входят в текущий MVP. Новые требования сначала добавляются
сюда с приоритетом, зависимостями и проверяемым критерием готовности.
