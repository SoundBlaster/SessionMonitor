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
| Xcode 26.0 compatibility build | `macos-26` с выбранным Xcode 26.0.1; собирает `MonitorMac` для проверки compile-time API availability fallback |
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
предполагает выполненный `make build-cli`. Snapshot harness дополнительно проверяет external
commits, отсутствие idle emissions, concurrent migration, single-owner watch и SIGKILL recovery.
Performance smoke проверяет benchmark harness на synthetic corpus: copy isolation, native
metrics, audit и append/full parity. Реальный архив не используется в CI и не публикуется
в artifacts; методика — [docs/performance](docs/performance/README.md).
GUI tests включают SQLite writer в отдельном `/usr/bin/python3` process; Python не входит в app runtime.

## Первоначальная настройка: `make init`

После clone и после каждого `git pull` выполните одну команду: `rtk proxy make init`
(`scripts/init.sh`, повторный запуск безопасен). На macOS она по порядку:

1. устанавливает pinned SwiftLint, XcodeGen и fsd-ios в `.build/ci-tools/bin`; повторно не скачивает,
   пока все три на месте и `scripts/ci/install-tools.sh` не менялся (отпечаток установки хранится в
   `.build/ci-tools/installed-pins`), а при смене версий или digest ставит заново;
2. ставит Git hooks (`make install-hooks`);
3. разрешает Swift packages (`make resolve`);
4. пересоздаёт `Apps/MonitorMac/MonitorMac.xcodeproj` (`make generate`);
5. показывает версии toolchain (`make doctor`).

На Linux выполняются только применимые шаги (hooks и `make resolve SWIFT=swift`); pinned tools и
приложение требуют macOS. Шаг, который упал, не прерывает остальные: в конце `make init` называет
упавшие шаги и завершается с ненулевым кодом. Makefile сам использует pinned tools из
`.build/ci-tools/bin`, если они есть; явные `SWIFTLINT=`, `XCODEGEN=`, `FSD=` по-прежнему имеют
приоритет. Поведение routine проверяет `make test-init` (временный репозиторий с заглушками,
без загрузок); тест входит в job `Workflow lint`.

## Локальные Git hooks

После clone установите hooks командой `rtk proxy make install-hooks`; после обновления репозитория,
в котором появились новые hooks, выполните её ещё раз. Hooks синхронизируют локальный генерируемый
`.xcodeproj` с исходниками. Проект остаётся игнорируемым и не попадает в commit.

| Hook | Когда срабатывает | Что делает |
| --- | --- | --- |
| `pre-commit` | перед commit | `make generate`, если среди staged changes есть файл в `Apps/MonitorMac/Sources/`, `Apps/MonitorMac/project.yml` или `Apps/MonitorMac/Package.resolved`; без XcodeGen останавливает commit с подсказкой |
| `post-merge` | после `git merge` и `git pull` | `make generate`, если эти файлы изменились между прежним и новым HEAD |
| `post-checkout` | после смены ветки | то же для разницы между ветками; checkout отдельных файлов не учитывается |
| `post-rewrite` | после `git rebase` и `git pull --rebase` | то же для разницы между прежним и новым HEAD |

Hooks работают только на macOS: на других системах (Linux, где XcodeGen и приложения нет) они ничего не делают,
и коммиты файлов приложения не блокируются. Это закрывает случай, когда после pull в target не хватает новых файлов и Xcode показывает вторичные
ошибки (SM-710). Hooks после получения изменений никогда не ломают операцию Git: без XcodeGen они
печатают подсказку запустить `make generate`. Общая логика находится в
`scripts/git-hooks/generate-project.sh`; он использует установленный XcodeGen (сначала
`.build/ci-tools/bin/xcodegen`, затем `PATH`). Поведение hooks проверяет `make test-hooks`
(временный репозиторий и фальшивый XcodeGen, без Xcode); тест входит в job `Workflow lint`.

Установщик копирует каждый hook и общий `sessionmonitor-generate-project.sh` в текущую Git hooks
directory, не меняя `core.hooksPath`. Это копии, а не ссылки в рабочее дерево: так hooks работают и на
ветках, где этих файлов ещё нет (при переходе на старую ветку рабочее дерево уже без них). После изменения
самих hooks повторите `rtk proxy make install-hooks` (или `make init`): копия обновляется, ссылки от
прежней версии заменяются копиями. Чужой hook с тем же именем не перезаписывается (остальные
устанавливаются, код выхода ненулевой). Ссылка прежней версии, пока её не заменили, продолжает работать через помощника из рабочего дерева.
Если помощника нет нигде, hooks сообщают об этом и не ломают операцию Git. Если `core.hooksPath` задан глобально без repository-local override
или разрешается за пределы репозитория, установка остановится, чтобы не добавить
SessionMonitor hooks в общую hooks directory.

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
