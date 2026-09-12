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

## Сборка и quality gates

Настройка toolchain, dependencies и локальной подписи описана в [README](README.md).
Build entry points находятся в [Makefile](Makefile); Xcode project генерируется
из [project.yml](Apps/MonitorMac/project.yml). Оба SwiftPM lock-файла входят в изменения
при обновлении dependencies; локальный `Local.xcconfig` в Git не добавляется.

| Изменение | Проверка |
| --- | --- |
| Core, decoder, store, CLI, policies | `make check-core`; fixtures для изменённой семантики |
| GUI/menu bar | `make lint lint-architecture`; app build и затронутые tests, visual verification изменённого UI |
| Общая интеграция, package graph, signing | `make check` или эквивалентный проверенный scope через Xcode MCP + CLI |
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
