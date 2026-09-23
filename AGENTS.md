# SessionMonitor: инструкции агентам

## Обязательный workflow

Основной план и единственный список статусов — [ROADMAP.md](ROADMAP.md).
Пользователь требует выполнять работу по нему и отмечать завершённое в файле.

1. Перед реализацией прочитать текущую точку ROADMAP, нужный пункт, его зависимости
   и [CONTRIBUTING.md](CONTRIBUTING.md); проверить Git status и фактическое состояние кода.
2. Следовать указанному приоритету. При команде «продолжай» без нового scope брать
   следующую доступную задачу из ROADMAP. Если пользователь меняет приоритет или
   добавляет требование, сначала отразить это в плане, затем выполнять работу.
3. Перед изменениями обозначить ID задачи, поставить `Статус: в работе` и обновить
   текущую точку. Не заводить параллельный backlog или отдельный файл статусов.
4. Выполнять задачу до её критерия готовности; запускать проверки, соответствующие
   изменению. `[x]` ставить только после реализации и успешной необходимой проверки.
5. В том же наборе изменений обновить ROADMAP: дата, краткий результат, evidence,
   оставшиеся ограничения. Для частичного результата сохранить `[ ]` и описать остаток;
   для блокировки указать причину и условие продолжения. Синхронизировать текущую точку.
6. Перед финальным ответом проверить согласованность кода, ROADMAP и пользовательских
   docs. В ответе назвать затронутые IDs, результат, проверки и следующий пункт.

Сохранять IDs завершённых задач. Новый defect/follow-up получает отдельный ID.
Архитектурные объяснения находятся в [monitor-design.md](monitor-design.md),
решения по библиотекам — в [dogfooding-plan.md](dogfooding-plan.md).
Эти документы ссылаются на ROADMAP за актуальным статусом.

## Обязательные PR и GitHub CI

Все новые задачи, включая документацию, workflow и обновление ROADMAP, выполняются
в отдельной ветке и доставляются только через PR в `main`. Прямой push в `main`
запрещён. Перед началом создать ветку от актуальной `origin/main`; указать ID задачи
в PR и использовать [.github/PULL_REQUEST_TEMPLATE.md](.github/PULL_REQUEST_TEMPLATE.md).

Для этого проекта запрещено создавать и использовать Git worktree, включая
Codex-managed worktree и worktree для делегированных задач. Работать в основном
checkout репозитория, создавая обычные ветки в нём. Перед переключением веток
проверять и сохранять пользовательские изменения. Делегированные задачи выполнять
последовательно в этом checkout либо ограничивать чтением/аудитом; не запускать
параллельные изменения одних и тех же файлов.

Перед merge должны пройти обязательный GitHub check `CI` на текущей ревизии PR,
необходимые локальные проверки и разрешение review threads. Branch должен быть
актуален относительно `main`. Не применять `--admin`, force push в `main`,
`[skip ci]`, временное отключение ruleset или обход checks для доставки изменений.
Если CI упал — исправить причину в той же ветке и дождаться нового результата.
Явные указания пользователя о review/merge остаются приоритетными.

Для длительных сборок, тестов, benchmark и CI применять skill `no-wait` и
событийное ожидание вместо частого polling. После создания PR никогда активно не
ждать завершения и не опрашивать CI: сообщить текущий статус и ссылку, оставить
проверки выполняться на GitHub и продолжать только независимую работу. Перед merge
проверить актуальный CI status в рамках запроса на review/merge, не ожидая его
выполнения в цикле после создания PR.

GitHub enforcement описан в [.github/main-ruleset.json](.github/main-ruleset.json),
проверки — в [.github/workflows/ci.yml](.github/workflows/ci.yml).
Не считать наличие этих файлов доказательством включённой защиты: изменения
ruleset проверять через GitHub API. Статус реализации в ROADMAP дополнять ссылкой
и стадией PR; merge подтверждать отдельно, не выдавать открытый PR за доставленный `main`.

## Технические границы

- Swift/SPM shared core для CLI/GUI/TUI; SwiftUI macOS app. Общие accounting rules
  и query contracts не дублировать между интерфейсами.
- SpecificationCore — domain policies, SpecificationKit — reactive GUI features,
  FSD — Pages First. NavigationSplitViewKit используется как reference behavior.
- Apple SDK/standard library и проверенные OSS — первый выбор для стандартной
  инфраструктуры. Собственный код сосредоточен на Codex semantics и интеграции.
- Сохранять ownership/dedup, unknown values, provenance и atomic storage.
  Не суммировать mirrored counters и не объявлять высокий cache hit доказательством экономии.
- Локальные raw logs, audit outputs, signing overrides и build artifacts остаются
  вне Git. Изменения dependency snapshot сопровождать provenance и regression evidence.
- Canonical Xcode project definition — `Apps/MonitorMac/project.yml`;
  `make generate` создаёт `.xcodeproj`. Сохранять оба Package.resolved.

## Инструменты и проверки

Основной интерфейс работы с открытым Xcode — MCP `xcode-tools`.
Сначала определить текущий workspace tab, scheme и destination через discovery.
`SessionMonitor-Package` — core/package, `MonitorMac` — app/GUI; не смешивать test results.
Использовать BuildProject, RunProject, RunSomeTests/RunAllTests и debugger tools по задаче.
XcodeBuildMCP CLI — отдельный дополнительный путь; `swift`, `xcodebuild` и Makefile сохраняются.

Core changes: `make check-core`. GUI changes: SwiftLint/FSD и подходящие app build/tests.
Общие integration changes: `make check` либо соответствующие MCP/CLI checks с тем же scope.
GitHub native gate запускает `make ci`: тот же `check` с locked dependencies,
ad-hoc signing и проверкой lock files. `make lint-ci` проверяет Actions через actionlint.
Documentation-only: проверить ссылки, IDs, статусы и формат; повторная сборка без
изменений кода локально не требуется; обязательный GitHub CI выполняется для каждого PR.
Не повторять уже зелёные локальные проверки без новой причины.

Shell commands в этом workspace выполнять с префиксом `rtk`; для raw command — `rtk proxy`.
Учитывать [локальные правила RTK](/Users/egor/.codex/RTK.md) на машине пользователя.
Сохранять пользовательские uncommitted changes. Commit, push, PR и release выполняются
в пределах действующих указаний пользователя, а не автоматически из-за записи в плане.

## Делегирование

Этот файл сам по себе не требует subagents. При разрешённом делегировании применять
Parallel Subagent Orchestrator: ограниченная задача, явное владение файлами,
event-aware waits. Основной агент отвечает за интеграцию и обновление ROADMAP.
При завершении этапа оставлять в текущей точке достаточно контекста для продолжения.
