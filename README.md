# SessionMonitor

Нативный macOS-проект для анализа расхода ресурсов Codex. Первая рабочая версия:
Swift CLI, общее ядро и SwiftUI Session Explorer с SQLite storage.

## Что работает

- Потоковое чтение локальных JSONL через Foundation/Codable без сохранения prompts и tool outputs.
- Проверка ownership с учётом fork replay, глобальный dedup по response ID и диагностика конфликтов.
- GRDB/SQLite: атомарная замена снимка каждого файла, WAL, один importer на БД между процессами.
- CLI `import` и `report`: text/JSON, период `[since, until)`, общие и посессионные суммы.
- Input/cache/output и optional cache-write/reasoning/total counters. Unknown не превращается в ноль.
- SpecificationCore для coverage policy; SpecificationKit `@ObservedSatisfies` в GUI.
- Native split navigation, фильтр по session ID/model, inspector и независимое состояние окон.
- SwiftLint, FSD architecture lint, Makefile, XcodeGen и подписанная development app.

## Сборка и запуск

При работе из Codex с открытым Xcode основной интерфейс — подключённый MCP
`xcode-tools` через XcodeMCPWrapper broker. Проверены 43 доступных tools и успешные
`XcodeListWindows`, `XcodeListSchemes`, `GetTestList`. Выбирать workspace tab и scheme
перед `BuildProject`, `RunProject`, `RunAllTests` и debugger operations.
`SessionMonitor-Package` — Swift package с 12 core tests; GUI и 6 GUI/model tests
находятся в `Apps/MonitorMac/MonitorMac.xcodeproj`, схема `MonitorMac`.
XcodeBuildMCP CLI остаётся дополнительным build path; это отдельный инструмент.

Проверено: Xcode 27 beta (`27A5209h`), Swift 6.4, macOS arm64; deployment target macOS 15.
Инструменты: SwiftLint 0.63.3, XcodeGen 2.46.0, fsd-ios 0.4.0, XcodeBuildMCP 2.7.0.
Runtime dependencies разрешаются через SwiftPM; локальная compatibility dependency описана ниже.

```sh
make check-core           # Swift CLI build, SwiftLint, 12 core tests
make build-mcp            # GUI build через XcodeBuildMCP CLI
make test-macos           # xcodebuild + 6 GUI/model tests
make lint-architecture    # FSD strict architecture gate
make check                # Полный последовательный набор локальных проверок
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
swift run codex-monitor report --since 2026-09-05T05:27:20Z --until 2026-09-12T05:27:20Z
swift run codex-monitor report --json
open .build/xcode/Build/Products/Debug/SessionMonitor.app
```

CLI и GUI по умолчанию используют одну БД:
`~/Library/Application Support/SessionMonitor/usage.sqlite`.
CLI поддерживает `--database PATH`; переменная `SESSIONMONITOR_DATABASE` позволяет
обоим интерфейсам использовать отдельную БД для проверки. Архивные rollouts можно
импортировать отдельным запуском из `~/.codex/archived_sessions`.

## Проверка результата

12 core tests и 6 GUI/model tests прошли; SwiftLint и FSD lint — без нарушений.
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

Импорт запускается явно и перечитывает выбранные файлы целиком. Незавершённая последняя
строка откладывается до следующего импорта. Снимки ранее импортированных, затем удалённых
файлов остаются в БД; это хранилище наблюдённых данных, не зеркало папки. При ошибке в
середине импорта уже завершённые файлы сохраняются; текущий файл меняется атомарно.

Приоритеты, следующие задачи и отметки выполнения ведутся в [ROADMAP.md](ROADMAP.md).
Правила работы по плану обязательны и описаны в [CONTRIBUTING.md](CONTRIBUTING.md)
и [AGENTS.md](AGENTS.md). Python используется только для reference audit, не как app runtime.

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
