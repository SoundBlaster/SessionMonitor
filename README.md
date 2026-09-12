# SessionMonitor

Нативный macOS-проект для анализа расхода ресурсов Codex. Первая рабочая версия:
Swift CLI, общее ядро и SwiftUI Session Explorer с SQLite storage.

## Что работает

- Потоковое чтение локальных JSONL через Foundation/Codable без сохранения prompts и tool outputs.
- Проверка ownership с учётом fork replay, глобальный dedup по response ID и диагностика конфликтов.
- Persistent checkpoints: неизменённые файлы пропускаются без чтения тела, append продолжает decoder после restart.
- GRDB/SQLite: records, diagnostics и checkpoint фиксируются одной транзакцией; WAL и один importer на БД.
- CLI `import` и `report`: text/JSON, период `[since, until)`, общие и посессионные суммы.
- CLI `watch`: native FSEvents, bounded debounce, retry/reconciliation и pause/resume/stop.
- Versioned `snapshot` / `snapshot --follow`: общие query metadata и live updates в GUI от external commits.
- Input/cache/output и optional cache-write/reasoning/total counters. Unknown не превращается в ноль.
- SpecificationCore для coverage policy; SpecificationKit `@ObservedSatisfies` в GUI.
- Native split navigation, фильтр по session ID/model, inspector и независимое состояние окон.
- MenuBarExtra: read-only сводка tokens, cache coverage, периода и времени обновления индекса.
- SwiftLint, FSD architecture lint, Makefile, XcodeGen и подписанная development app.

## Сборка и запуск

При работе из Codex с открытым Xcode основной интерфейс — подключённый MCP
`xcode-tools` через XcodeMCPWrapper broker. Проверены 43 доступных tools и успешные
`XcodeListWindows`, `XcodeListSchemes`, `GetTestList`. Выбирать workspace tab и scheme
перед `BuildProject`, `RunProject`, `RunAllTests` и debugger operations.
`SessionMonitor-Package` — Swift package с 54 core tests; GUI и 15 GUI/model/render tests
находятся в `Apps/MonitorMac/MonitorMac.xcodeproj`, схема `MonitorMac`.
XcodeBuildMCP CLI остаётся дополнительным build path; это отдельный инструмент.

Проверено: Xcode 27 beta (`27A5209h`), Swift 6.4, macOS arm64; deployment target macOS 15.
Инструменты: SwiftLint 0.63.3, XcodeGen 2.46.0, fsd-ios 0.4.0, XcodeBuildMCP 2.7.0.
Runtime dependencies разрешаются через SwiftPM; локальная compatibility dependency описана ниже.

```sh
make check-core           # Swift CLI build, SwiftLint, 54 core tests и CLI process smoke
make test-cli             # CLI signals/backpressure smoke после build-cli; Python 3 standard library
make build-mcp            # GUI build через XcodeBuildMCP CLI
make test-macos           # xcodebuild + 15 GUI/model/render tests
make lint-architecture    # FSD strict architecture gate
make check                # Полный последовательный набор локальных проверок
make ci                   # Те же native gates, locked packages и ad-hoc signing
make lint-ci              # Проверка GitHub workflow (нужен actionlint)
```

`make generate` создаёт `Apps/MonitorMac/MonitorMac.xcodeproj` из versioned `project.yml`.
Оба SwiftPM graphs закреплены в root `Package.resolved` и `Apps/MonitorMac/Package.resolved`.
Локальная подпись настраивается в игнорируемом `Apps/MonitorMac/Local.xcconfig`:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
CODE_SIGN_IDENTITY = Apple Development
```

На текущем Mac Team получена из существующего valid certificate. На новом checkout
создаётся конфигурация для ad-hoc development build. Makefile использует
`-skipMacroValidation` для известных pinned macros SpecificationCore/Kit, как
XcodeBuildMCP; глобальные Xcode trust settings не меняются. После ручного разрешения
macros в Xcode можно передать `XCODEBUILD_FLAGS=`.

```sh
swift run codex-monitor import ~/.codex/sessions
swift run codex-monitor import ~/.codex/sessions --rescan  # Принудительно пересобрать снимки
swift run codex-monitor watch ~/.codex/sessions
swift run codex-monitor report --since 2026-09-05T05:27:20Z --until 2026-09-12T05:27:20Z
swift run codex-monitor report --since 2026-09-11T21:00:00Z --until 2026-09-12T21:00:00Z --time-zone Europe/Moscow
swift run codex-monitor report --json
swift run codex-monitor snapshot --follow --time-zone Europe/Moscow
open .build/xcode/Build/Products/Debug/SessionMonitor.app
```

CLI и GUI по умолчанию используют одну БД:
`~/Library/Application Support/SessionMonitor/usage.sqlite`.
CLI поддерживает `--database PATH`; переменная `SESSIONMONITOR_DATABASE` позволяет
обоим интерфейсам использовать отдельную БД для проверки. Архивные rollouts можно
импортировать отдельным запуском из `~/.codex/archived_sessions`.
Directory import рекурсивно выбирает `*.jsonl` и несжатые числовые архивы
`*.jsonl.1`, `*.jsonl.2` и т. п. Hidden files/directories, `*.jsonl.bak` и
сжатые `*.jsonl.gz` не выбираются; декомпрессия не реализована.

Повторный `import` использует checkpoint по каждому source path. JSON summary содержит
`ioMetrics`: фактически прочитанные bytes и количество skipped/resumed/rescanned files.
`records` и `diagnostics` описывают только этот запуск; общие суммы и diagnostics
хранящегося набора возвращает `report`. При unchanged import `records` равен 0.

При росте файла с той же identity importer считает его append-only и читает только
хвост от последнего обработанного newline, в том числе после перезапуска. Partial
строка перечитывается целиком вместе с новыми bytes; raw tail не сохраняется в SQLite.
Неизменённый файл читает 0 bytes. Замена, уменьшение и изменение metadata без роста
вызывают полный rescan. Checkpoint v1 при первом обновлении пересобирается в v2.

Перезапись старых строк одновременно с ростом файла автоматически не обнаруживается.
После ручного редактирования или восстановления логов используйте `import DIRECTORY --rescan`.
В SQLite сохраняется только нормализованное состояние decoder, без raw prompts и tool outputs.

## Watch

`watch DIRECTORY` регистрирует FSEvents до первого import. События объединяются в
окно 250 ms (`--debounce-milliseconds 1...60000`); новые события не продлевают его
бесконечно. Каждое обновление сверяет всё дерево через incremental importer.
Dropped/coalesced events также вызывают reconciliation, без принудительного чтения
тел неизменённых файлов. События во время импорта сохраняют запрос на следующий проход.

Команда выводит JSON status lines с `phase`, `completedImports`, `lastImport` и
ошибкой при recovery. `SIGUSR1` ставит watch на паузу и дожидается текущего import;
после статуса `paused` новый import не начинается. `SIGUSR2` возобновляет работу
с обязательной сверкой дерева. `Ctrl-C`/`SIGINT` и `SIGTERM` отменяют importer,
дожидаются cleanup и закрывают stream. При stdout backpressure завершение ждёт
вывода не более 250 ms после остановки watcher; последние status lines могут быть отброшены.

Root должен существовать при запуске. Наблюдение за его parent позволяет заметить
rename/delete/recreate; недоступность root или меняющийся во время
чтения файл дают явный `recovering` и повтор с backoff 1 → 2 → … → 30 s.
БД должна оставаться доступной при перемещении sources. Её файлы, WAL/SHM, import/setup locks
исключены из discovery и обычных событий, даже если БД названа `usage.jsonl`.
Hidden entries и неподдерживаемые файлы не вызывают обычный refresh.

Swift API: `try await monitor.watch(directory)` возвращает `SessionWatch` с
`updates` (один consumer, latest status), `status`, `pause()`, `resume()` и `stop()`.
Владелец обязан вызвать `await stop()` либо ожидать `waitUntilStopped()` в задаче,
чья отмена остановит watcher. Watch удерживает DB lock всё время, включая pause/recovery;
второй watch или одноразовый import получает `importerBusy`. Читатели продолжают работать.
Lock освобождается после завершения importer, а при аварии/SIGKILL — операционной системой.
Symlink к БД не создаёт отдельного владельца; lock files не удаляются при release.

## Observable snapshots

`codex-monitor snapshot` выводит один JSON object, `snapshot --follow` — initial snapshot
и последующие изменения как JSON lines. Команда только читает index и не запускает importer.
Доступны `--since`, `--until`, `--time-zone` и `--database`; период остаётся абсолютным
`[since, until)`, timestamps требуют явный ISO 8601 offset, а IANA timezone сохраняется
как presentation metadata. По умолчанию используется UTC. `report` и `snapshot` разделяют
parser и validation этих параметров. `report --json` сохраняет прежний bare `UsageReport` для совместимости,
а canonical export с `query`, coverage и watermark выдаёт `snapshot`.

Контракт schema version 1 содержит `query`, `report`, `coverage` и `watermark`.
Coverage различает empty/partial/complete cache fields у canonical requests; это не
оценка полноты всего архива. Diagnostics относятся ко всем импортированным sources.
Watermark содержит database UUID, монотонный commit revision и optional committed-at.
Он обновляется атомарно с каждым изменённым source snapshot/checkpoint, включая diagnostics;
unchanged imports его не продвигают. У мигрированной БД revision начинается с 0 и дата неизвестна,
даже если прежние records уже есть. Source timestamps не используются как commit time.

GUI предлагает All Time, Today, Last 7 Days и Last 30 Days в UTC или текущей local
timezone. Calendar periods выравниваются по полуночи выбранной зоны, включая DST,
и сохраняются между запусками. Один app-owned scope применяется к окнам и menu bar;
поиск в sidebar только сужает видимый список и не меняет accounting totals.

GUI и Swift API `monitor.snapshots(query:)` используют тот же контракт: SQLite/GRDB
раз в секунду читает только marker, а полный отчёт вычисляет при изменении. Все поля
snapshot читаются в одной транзакции. Это также видит commits других CLI/GUI процессов:
обычный GRDB ValueObservation сам по себе external writes не наблюдает. Stream хранит
последнее значение, может объединять промежуточные commits и прекращает работу при отмене
consumer task. Окна GUI владеют своими tasks; фильтр и selection сохраняются при обновлениях.

Watermark относится к committed index, а не к завершению полного directory scan или
свежести raw logs. Прямые SQL writes без marker не входят в поддерживаемый write API.
Замена файла самой БД требует закрыть и вновь открыть runtime; открытая SQLite connection
продолжает обращаться к своему файлу. Ошибка observation оставляет предыдущий GUI report
видимым и сообщается пользователю; повторное открытие окна создаёт новый stream.

## Menu bar

Значок SessionMonitor открывает компактную панель: выбранный в приложении
период/timezone, input/output tokens, известный cached input, cache coverage и время
последнего commit в индексе (локальное время). Unknown cache остаётся unknown;
cached input не прибавляется к input повторно. Время индекса не доказывает свежесть logs.

Окна и панель используют один upstream stream на одинаковый `UsageQuery`. Открытие панели
не запускает importer, rescan или дополнительный polling stream, пока окно уже наблюдает
тот же query. Разные queries изолированы; при отсутствии подписчиков их stream отменяется.
Повторное открытие читает текущую БД. Навигация и sidebar search каждого окна независимы,
а accounting scope общий для приложения.
После ошибки сохраняется последний snapshot с предупреждением; повторное открытие
панели повторяет подписку. Ошибки не подменяются нулевыми totals.

**Watch Folder…** выбирает папку и явно запускает её import/watch. Панель показывает
состояние этого watcher и предлагает Pause/Resume и Stop Watch. Внешний CLI-watch
из GUI не управляется; занятый importer lock отображается как ошибка запуска.
Pause сохраняет ownership индекса, поэтому ручной импорт в это время может вернуть
ошибку занятого importer. **Refresh** только перечитывает snapshot, без import/rescan.

**Open Window** открывает Session Explorer. **Settings…** позволяет скрыть или вернуть
значок; эта настройка сохраняется. Закрытие окна и скрытие значка не останавливают
watch. **Quit SessionMonitor**, включая стандартный Quit приложения, ожидает остановку
watch и освобождение runtime. После повторного запуска watch нужно включить явно.
Bundle IDs: `ru.egormerkushev.SessionMonitor` и `ru.egormerkushev.SessionMonitor.Tests`.
Видимое product name и заголовок окна — `SessionMonitor`; `Session Explorer` — название
функциональной области, а `MonitorMac` используется только для Xcode project/target/scheme.

## Performance baseline

[SM-105: результаты на реальном архиве](docs/performance/2026-09-12-append.md):
155 files / 1,286,230,037 bytes, median fresh import 6.13 s, unchanged 0.02 s / 0 bytes.
Append 752 bytes читает ровно 752 bytes, median 0.02 s; применяется append-only контракт выше.
Audit parity: 6,340 requests и все шесть token totals. [Команда и методика](docs/performance/README.md).
`make benchmark` использует отдельные копии/БД; в CI запускается только synthetic smoke.

## Проверка результата

SM-104: 52 core tests проверяют versioned snapshot, atomic watermark/report, coverage,
rollback и importer ownership; process harness — external writes, concurrent migrations,
idle suppression, symlink и SIGKILL recovery. 8 app/model tests включают GUI observation
записи отдельного процесса. Исправлена повторная линковка static packages в hosted tests
(SM-705), которая вызывала crash GRDB. Evidence: `.build/sm104-ci-review.log`.


SM-103: полный `make ci` прошёл — 44 core tests, 6 app/model tests, builds,
SwiftLint/FSD positive+negative, locked dependencies и CLI process smoke.
Native tests покрывают append, pause/resume, root recreation, physical paths после
удаления и исключение собственных DB writes. Process smoke проверяет сигналы,
accounting после resume и заполненный stdout pipe. Evidence — `.build/sm103-ci.log`.

SM-102: `make check-core` прошёл с 33 tests и нулём SwiftLint violations. Восемь новых
lifecycle tests проверяют rename, rotation с разным порядком paths, copytruncate,
numeric archive discovery, redelivery/conflicts, ownership reset и retention.
Повторный CLI import прежних 155 файлов снова прочитал 0 bytes.
Локальное evidence — `.build/sm102-verification.json`; app baseline приведён ниже.

SM-101: прошли 25 core tests, SwiftLint и 6 GUI/model tests; CLI и app собраны.
Fixtures проверяют append/restart, UTF-8 и oversized tails, ownership, конфликты,
смену файла во время чтения, atomic rollback и отклонение устаревшего checkpoint.
После миграции копии прежней БД повторный импорт 155 файлов прочитал 0 байт;
все недельные totals ниже снова совпали. Локальное evidence — `.build/sm101-verification.json`.

Baseline первой версии: 12 core tests и 6 GUI/model tests; SwiftLint и FSD lint — без нарушений.
Negative FSD fixture отклоняет зависимость `shared → pages`. Signed app проходит
`codesign --verify --deep --strict`, identity — Apple Development. Окно проверено:
выбор сессии, фильтр и inspector обновляют данные и coverage.

На 155 реальных rollout files результаты периода 5–12 сентября совпали с Python audit:

| Метрика | Swift и reference audit |
| --- | ---: |
| Requests | 6 340 |
| Input | 775 583 024 |
| Cached input | 747 037 312 |
| Output | 3 120 896 |
| Reasoning, уже входящий в output | 920 751 |
| Total | 778 703 920 |

Локальные evidence files находятся в `.build/verification.json`, `.build/audit-report.json`,
`.build/core-tests.log`, `.build/final-core-check.log`, `.build/gui-tests.log` и
`.build/quality/*.xcresult`. Персональные данные и build artifacts исключены из Git.
GUI пока показывает все импортированные записи без фильтра периода; поэтому её общие
суммы могут быть больше приведённых недельных сумм CLI.

## Ограничения первой версии

Canonical `token_usage_record` учитываются только при подтверждённом native turn и
стабильных IDs. Legacy `token_count` не добавляются: часто это mirrors; legacy-only
сессии эта версия полностью не покрывает. Diagnostics относятся ко всем импортированным
источникам, даже когда суммы CLI ограничены периодом. Unknown record types видны в
диагностике, в том числе ещё не интерпретируемые metadata variants.

Обновление запускается через `import` или CLI `watch`; GUI watch controls ещё не подключены. Незавершённая последняя
строка учитывается после её завершения newline. БД хранит последний наблюдённый snapshot
каждого source path: отсутствие path при следующем import его не удаляет, а замена
файла по тому же path пересобирает этот snapshot. Это не история всех поколений файла.
При rotation/copytruncate прежние записи сохраняются, если архив тоже импортирован.
Rename/copy создаёт ещё один source snapshot; canonical response IDs не удваивают
суммы, а duplicate/conflict diagnostics отражают все наблюдённые копии. Diagnostics
старого path, включая partial tail, остаются его последним наблюдённым состоянием.
При ошибке в середине импорта уже завершённые файлы сохраняются;
текущий файл меняется атомарно.
Если файл изменился прямо во время чтения, import сообщает ошибку и сохраняет прежний
checkpoint; следующий запуск повторяет попытку. Truncation, replacement, изменение
metadata без роста и неподдерживаемый checkpoint вызывают полный rescan этого источника.

Приоритеты, следующие задачи и отметки выполнения ведутся в [ROADMAP.md](ROADMAP.md).
Правила работы по плану обязательны и описаны в [CONTRIBUTING.md](CONTRIBUTING.md)
и [AGENTS.md](AGENTS.md). Python используется для reference audit и process test harness, не как app runtime.

Все новые изменения проходят через отдельную ветку и PR в `main` с обязательным
GitHub check `CI`. Workflow, runner, fixed tooling и воспроизведение описаны в
[CONTRIBUTING.md](CONTRIBUTING.md#github-actions).

## Dogfooding и compatibility

В `SpecificationCore 1.0.0` найдена неоднозначность overload в `FirstMatchSpec.Builder`
на Swift 6.4. [Локальная dependency](Dependencies/README.md) содержит исходный release
и минимальный patch с отдельным regression test. Это временная интеграционная копия;
исходные пользовательские repositories не изменены. После upstream fix следует вернуть
remote dependency. SpecificationKit 4.0.0 использует ту же локальную Core dependency.
NavigationSplitViewKit остаётся референсом поведения; FSD применяется по Pages First.

[Third-party notices](THIRD_PARTY_NOTICES.md) перечисляют зависимости и licenses.

## Проектные материалы

- [Roadmap и текущий прогресс](ROADMAP.md).
- [Правила разработки](CONTRIBUTING.md) и [инструкции агентам](AGENTS.md).
- [Архитектура и границы MVP](monitor-design.md).
- [План dogfooding](dogfooding-plan.md).
- [Reuse policy и build workflow](quality-and-reuse.md).
- [Python reference audit](audit_codex.py).

`plot_audit.py` и `report.md` — локальные персональные материалы, исключённые из Git.

Материалы перенесены в `~/Development/GitHub/SessionMonitor` 12 сентября 2026.
GitHub repository: [SoundBlaster/SessionMonitor](https://github.com/SoundBlaster/SessionMonitor),
ветка `main`, [MIT License](LICENSE). Текущий статус доставки — в [ROADMAP.md](ROADMAP.md).
Исследовательские snapshots находятся в `ResearchReferences`, чтобы не конфликтовать
со Swift `Sources` на файловой системе macOS без учёта регистра.
