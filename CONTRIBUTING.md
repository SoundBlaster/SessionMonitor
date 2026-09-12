# Работа над SessionMonitor

## План и статусы

[ROADMAP.md](ROADMAP.md) — обязательный план разработки и основной источник статуса.
Это правило действует для людей и coding agents; дополнительные инструкции агентам
находятся в [AGENTS.md](AGENTS.md).

1. Прочитать текущую точку и выбрать следующую доступную задачу по приоритету и зависимостям.
   Явный приоритет пользователя отражается в ROADMAP до начала работы.
2. Указать ID задачи и `Статус: в работе`, обновить активную/следующую задачу.
   Новое требование добавить с новым ID, ожидаемым результатом и проверкой готовности.
3. Реализовать ограниченный результат, сохраняя существующие решения и чужие изменения.
   Детали архитектуры уточнять в соответствующем design document, с отсылкой к ID.
4. Проверить критерий готовности и подходящие quality gates. Код, который только
   написан или компилируется без необходимой проверки поведения, не считается завершённой задачей.
5. В том же наборе изменений отметить `[x]`, дату, результат и evidence.
   Частичный результат оставить `[ ]`, записав остаток; blocker — с причиной и условием снятия.
6. Обновить текущую точку и следующий пункт; синхронизировать README/architecture docs,
   когда меняются возможности, команды или ограничения. Не вести дублирующий checklist.
7. В итоговом сообщении или описании изменения указать IDs, проверки и существенные ограничения.

Завершённые IDs сохраняются. Регрессия или дополнительная работа получает отдельный
пункт с отсылкой к исходному. Проверки предыдущих запусков обозначаются как baseline;
не следует представлять их как вновь выполненные. Git/PR/publication workflow определяется
текущими указаниями владельца проекта; чекбокс в плане не заменяет эти указания.

## Только через pull requests

Начиная с SM-704, каждая задача, включая docs/CI/ROADMAP, выполняется в отдельной
ветке от актуальной `origin/main`, например `feat/sm-101-incremental-checkpoints`.
Коммиты отправляются в эту ветку, затем открывается PR в `main` по
[шаблону](.github/PULL_REQUEST_TEMPLATE.md). Прямые push в `main` запрещены.

Merge выполняется через PR после успешного обязательного check `CI` на текущей
ревизии, актуализации относительно `main` и разрешения review threads.
Не обходить проверки через admin bypass, force push, `[skip ci]` или выключение защиты.
При падении CI исправлять причину в ветке PR. Указания владельца о review/merge
соблюдаются независимо от зелёного CI.

ROADMAP хранит результат задачи, evidence и ссылку/стадию PR. Реализация с зелёными
проверками в открытом PR ещё не означает, что она находится в `main`.
Изменения статуса также проходят через PR.

[Ruleset](.github/main-ruleset.json) задаёт PR requirement, обязательный `CI`,
запрет удаления/force push и отсутствие bypass actors, включая admin bypass.
Число обязательных внешних approvals — 0: владелец может merge свой PR после CI;
запрошенные review threads всё равно должны быть разрешены. Требование дополнительных
reviewers можно добавить отдельно. Фактические настройки проверяются через GitHub API.

## GitHub Actions

[Quality workflow](.github/workflows/ci.yml) выполняется на каждом PR в `main`,
на push после merge и при ручном запуске. Фильтров по имени ветки/путям нет.
Новая ревизия отменяет устаревший run; итоговый `CI` успешен только при успехе
обоих jobs, включая отсутствие skipped/cancelled обязательных gates.

| Job | Runner и проверки |
| --- | --- |
| Workflow lint | `ubuntu-24.04`, actionlint и ShellCheck для CI scripts |
| Native checks | `xcode-27`, `make ci`: CLI/app builds, SwiftLint, FSD positive/negative, core/app tests и CLI process smoke |
| CI | Итоговый required check для всех обязательных jobs |

Native runner использует Xcode 27/Swift 6.4, соответствующий текущему development
baseline. Образ пока preview: beta revision может меняться, фактическая версия
выводится в log, cache key включает Xcode build и оба lock files. См.
[официальное описание runner](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md).
Другие toolchains не считаются проверенными этим gate.

[Installer](scripts/ci/install-tools.sh) закрепляет SwiftLint 0.63.3, XcodeGen 2.46.0,
fsd-ios 0.4.0, actionlint 1.7.12 и SHA256 официальных release archives.
GitHub Actions закреплены по commit SHA. Permissions — `contents: read`;
PR code не получает credentials для push или Apple Developer secrets.
Dependencies загружаются из lock files; CI не переписывает pins.
Ad-hoc signing не обращается к Developer account и не меняет локальный `Local.xcconfig`.
Distribution signing/notarization проверяются отдельно на этапе SM-703.

Локальное воспроизведение на macOS arm64:

```sh
rtk proxy bash scripts/ci/install-tools.sh native
rtk proxy bash scripts/ci/install-tools.sh workflow
rtk proxy make lint-ci ACTIONLINT=.build/ci-tools/bin/actionlint
rtk proxy make ci SWIFTLINT="$PWD/.build/ci-tools/bin/swiftlint" XCODEGEN="$PWD/.build/ci-tools/bin/xcodegen" FSD="$PWD/.build/ci-tools/bin/fsd-ios"
```

ShellCheck выполняется Linux job; при наличии локального `shellcheck` также запустить
`rtk proxy shellcheck scripts/ci/*.sh`. Installer пишет только в `.build/ci-tools`.
Log и `.xcresult` сохраняются artifact `native-results-*` на 7 дней, в том числе при failure.
Персональный audit не запускается в CI; используются versioned synthetic fixtures.

## Сборка и quality gates

Настройка toolchain, dependencies и локальной подписи описана в [README](README.md).
Build entry points находятся в [Makefile](Makefile); Xcode project генерируется
из [project.yml](Apps/MonitorMac/project.yml). Оба SwiftPM lock-файла входят в изменения
при обновлении dependencies; локальный `Local.xcconfig` в Git не добавляется.

| Изменение | Проверка |
| --- | --- |
| Core, decoder, store, CLI, policies | `make check-core`; fixtures и CLI process smoke для изменённой семантики |
| GUI/menu bar | `make lint lint-architecture`; app build и затронутые tests, visual verification изменённого UI |
| Общая интеграция, package graph, signing | `make check` или эквивалентный проверенный scope через Xcode MCP + CLI |
| CI/workflow | `make lint-ci`, ShellCheck, `make ci` и реальный GitHub Actions run |
| WidgetKit/TUI на следующих этапах | Дополнить gates для новых targets/runtime и отразить их в ROADMAP/Makefile |
| Только документация | Проверить локальные ссылки, уникальность IDs, статусы, Markdown и отсутствие противоречий |

Для работы в открытом Xcode предпочтителен подключённый MCP `xcode-tools`.
Сначала проверить окно, активную scheme и destination. Для core используется
`SessionMonitor-Package`, для GUI — проект `MonitorMac.xcodeproj` и scheme `MonitorMac`.
BuildProject/RunSomeTests/RunAllTests выбираются по scope; `GetTestList` помогает
не приписывать тесты другого target или workspace текущему изменению.
XcodeBuildMCP CLI и нативные `swift`/`xcodebuild` остаются доступными путями.

Сохранять короткий итог проверки и ссылку на подходящий log/xcresult или test source.
Локальные evidence могут находиться в игнорируемой `.build`; такой путь помечается
как локальный и может отсутствовать в чистом clone. В repository должны оставаться
достаточные инструкции и fixtures для воспроизведения. Не повторять полный набор
проверок после изменения только документации или ради запуска другого wrapper.

На рабочей машине пользователя shell commands запускаются через `rtk`
(`rtk proxy` для прямого вызова); пути и локальные overrides берутся из окружения.

`make check-core` и `make ci` также выполняют `make test-cli`: Python 3 standard-library
harness запускает собранный Swift CLI на synthetic sources и проверяет pause/resume,
SIGINT/SIGTERM, accounting и cleanup при полном stdout pipe. Отдельный `make test-cli`
предполагает выполненный `make build-cli`. Python не входит в app runtime.

## Реализация и reuse

Использовать Apple SDK/Swift standard library и поддерживаемые OSS для parsers,
storage, search, sorting и validation. Основание собственного решения — конкретная
предметная семантика или проверенный пробел готовых средств.

Общий domain/query layer обслуживает CLI, GUI, menu bar, widgets и TUI.
SpecificationCore содержит policies, SpecificationKit связывает GUI с reactive state,
FSD применяется по Pages First. Системные widgets означают WidgetKit extension.
Подробные границы — [архитектура](monitor-design.md) и [dogfooding](dogfooding-plan.md).

Сохранять accounting invariants: canonical ownership, dedup, unknown/observed-zero,
atomic writes и объяснимый coverage. Локальные prompts/tool outputs и signing material
не добавляются в Git. Dependency changes должны сохранять pins, licenses и provenance;
[SpecificationCore compatibility copy](Dependencies/README.md) остаётся временным решением.
