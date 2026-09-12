# Reuse, quality gates и native build workflow

Дата: 12 сентября 2026. Требования пользователя для Swift/macOS проекта.
Активные quality files находятся в корне проекта; starter сохраняется как исходный шаблон.
Текущие результаты первой CLI/app сборки и тестов — в [README](README.md).
План и статусы задач — в [ROADMAP.md](ROADMAP.md), обязательный workflow — в [CONTRIBUTING.md](CONTRIBUTING.md).

GitHub delivery выполняется строго через PR. Активные CI entry points:
[Quality workflow](.github/workflows/ci.yml), `make ci`, `make lint-ci` и
[main ruleset](.github/main-ruleset.json). Общие Makefile gates и PR/main triggers
адаптированы из [FSD template](https://github.com/SoundBlaster/FSD/tree/v0.4.0/templates/fsd-ios);
ветки Codex проходят те же проверки. Настройка и фактическая верификация — SM-704.

## Правило выбора реализации

Для стандартной задачи сначала использовать Apple SDK/Swift standard library,
затем подходящий поддерживаемый open-source компонент. Проверять реальное покрытие
сценария, tests, releases, совместимость toolchain, license и стоимость dependency
graph. Популярность помогает составить shortlist, но не заменяет проверку контракта.
Собственная реализация оправдана предметной семантикой или конкретным выявленным
пробелом готовых средств. Причину фиксировать кратко в решении по компоненту.

| Задача | Основа | Собственная часть приложения |
| --- | --- | --- |
| JSON | Foundation JSONDecoder/Codable | Отображение версий Codex events в domain DTO |
| JSONL | Потоковое чтение Foundation, готовый JSON decoder для каждой записи | Framing завершённых строк, offsets, partial tail и версия event schema |
| TOML config | Кандидат dduan/TOMLDecoder для чтения, после проверки fixtures | Извлечение relevant fields и version-aware interpretation |
| CLI arguments | Apple ArgumentParser | Список команд и их use cases |
| Structural validation | Codable, constraints/transactions SQLite; готовый schema validator при реальной потребности в JSON Schema | Semantic invariants, coverage, domain specs |
| Сортировка | SQL ORDER BY с устойчивым tie-breaker; Swift sorted для небольших коллекций | Пользовательские ключи сортировки |
| Поиск и фильтры | SQL/indexes; SQLite FTS5, когда нужен полнотекстовый поиск | Набор индексируемых полей и пользовательский query contract |
| Storage | GRDB + SQLite migrations/transactions | Схема предметных данных и atomic import batches |
| File watching | FSEvents + Foundation | Reconciliation, dedup и политика checkpoint |
| Даты и hashing | Foundation date/time APIs, CryptoKit | Выбор нормализуемых полей и правил сравнения |
| GUI и charts | SwiftUI/Swift Charts | Экран анализа, проекции и пользовательские действия |

Dependency для новой возможности выбирается тогда, когда она входит в следующий
сценарий. Например, отсутствие JSON Schema задачи не требует заранее подключать
универсальный validator. Поиск индексирует разрешённые нормализованные данные;
FTS5 не является причиной сохранять полные prompts в БД.

TOML decoder подтверждает чтение, но не гарантирует сохранение comments/formatting
при записи. Для будущего config apply отдельно проверить готовый editor с нужным
round-trip контрактом или доступную операцию самого Codex. Самописная TOML grammar
и замена значений регулярными выражениями не являются принятым решением.

Dogfooding SpecificationCore/Kit и FSD — явный выбор пользователя. Эти библиотеки
используются в своих roles, а не заменяют готовые JSON parsers, SQL engine или
общую инфраструктуру. [План dogfooding](dogfooding-plan.md) определяет границы.

## Подготовленные quality files

- [Makefile](quality-starter/Makefile): единый вход для локальных проверок и CI.
- [.swiftlint.yml](quality-starter/.swiftlint.yml): default rules и небольшой
  набор дополнительных проверок; сторонние/generated build directories исключены.
- [.fsd-ios.yml](quality-starter/.fsd-ios.yml): FSD root GUI и architecture rules.
- [verification.json](quality-starter/verification.json) и
  [verification.log](quality-starter/verification.log): результаты проверки starter.

Эти три configuration files переносятся в root первого app repository. Defaults
соответствуют архитектурному предложению: CLI product `codex-monitor`, Xcode
project `Apps/MonitorMac/MonitorMac.xcodeproj`, shared scheme `MonitorMac`.
При выборе реальных имён они меняются через Make variables. До появления app
project соответствующие targets завершаются явной ошибкой, а не дают ложный pass.

| Make target | Что выполняется |
| --- | --- |
| doctor | Проверяет доступные Swift, Xcode и SwiftLint versions |
| resolve | SwiftPM dependency resolution |
| build-cli / test-core | swift build / swift test |
| lint-core / lint | SwiftLint --strict для package или всего первого-party кода |
| lint-architecture | fsd-ios lint по root/config этого приложения |
| build-macos / test-macos | xcodebuild build/test для shared macOS scheme |
| check-core | Последовательно build CLI → lint package → package tests |
| check | Build CLI/app → SwiftLint → FSD lint → package/app tests |
| archive | Локальный Release archive через xcodebuild |

Makefile совместим с установленным GNU Make 3.81. Проверки не исправляют исходники
автоматически, сохраняют failure exit codes и дают новый .xcresult path для
каждого app test run. Сборка предшествует lint, чтобы анализировать компилируемый
код. Package/test source paths подаются одним способом, без повторного обхода
файлов из-за сочетания included и CLI paths.

SwiftLint фиксируется на **0.63.3**, уже установленной на Mac; CI должен использовать
ту же версию. При подключении lint к Xcode/SPM предпочтителен рекомендованный
upstream binary plugin **SimplyDanny/SwiftLintPlugins** с exact version: он
позволяет не собирать сам SwiftLint и его dependency graph из source. Одна и та же
конфигурация действует для IDE и Make; полная CLI-проверка остаётся quality gate.
Не добавлять глобальные исключения правил ради случайного прохода CI.

В `check` app scheme должен реально содержать tests. Готовность этапа подтверждает
выполнение существующих test cases, а не только exit 0 пустого test plan. Счётчики
используют отчёты Swift Testing/xcresult, без привязки к хрупкому grep stdout.

## swift, xcodebuild и XcodeBuildMCP

`swift` собирает и тестирует package. `xcodebuild` собирает и тестирует приложение,
создаёт archive и служит воспроизводимым основанием CI. XcodeBuildMCP используется
для agent workflow вокруг этих же project/scheme/destination: discovery,
build/test/run, диагностика и получение артефактов через доступные tools.
Общие build settings и параметры берутся из проекта, не дублируются в новом
самодельном build runner. Успешную сборку не нужно повторять через все три пути
только для отметки об использовании каждого инструмента.

XcodeBuildMCP 2.7.0 установлен через официальный Homebrew tap и использован через
его CLI для первой успешной macOS app build. Затем пользователь подключил Xcode MCP
`xcode-tools` через XcodeMCPWrapper broker. Подключение проверено в этой задаче:
43 tools, успешные `XcodeListWindows`, `XcodeListSchemes` и `GetTestList`.
Основной интерфейс дальнейшей работы в открытом Xcode — `xcode-tools`;
XcodeBuildMCP CLI остаётся дополнительным и не является тем же MCP server.
Перед build/test/run необходимо выбрать workspace tab, scheme и подходящий destination:
`SessionMonitor-Package` покрывает package/core, `MonitorMac` — native app и GUI tests.
XcodeGen 2.46.0 генерирует проект из YAML. Makefile работает через нативные commands
независимо от MCP connection. Broker при проверке не перезапускался; конфигурация не менялась.

## Подпись и окружение

Проверено локально: Xcode **27.0 / 27A5209h**, Apple Swift **6.4**, SwiftLint **0.63.3**,
GNU Make **3.81**. Выбран Xcode-beta. Найдена одна valid identity категории
**Apple Development**; приватные ключи не экспортировались. Наличие платной
Apple Developer account указано пользователем, membership отдельно не проверялся.

Для development app настраивается Automatic signing и существующая Team в Xcode.
Makefile использует project signing settings и допускает override DEVELOPMENT_TEAM.
При необходимости Xcode-managed provisioning есть явный переключатель
ALLOW_PROVISIONING_UPDATES=YES. Значения Team/bundle ID берутся из реального проекта.
Development build должен сохранять требуемую подпись; временное отключение signing
для отдельной compile-only проверки не считается signed app verification.

Release export, Developer ID signing, notarization и публикация являются отдельным
этапом доставки. Подготовленный archive target сам ничего не публикует. Факт
наличия Apple Development identity не доказывает готовность distribution signing.

## Источники

- [SwiftLint](https://github.com/realm/SwiftLint) и
  [binary plugins](https://github.com/SimplyDanny/SwiftLintPlugins).
- [TOMLDecoder](https://github.com/dduan/TOMLDecoder): Swift Codable decoder;
  кандидат для read path, не выбранный editor для config apply.
- [SQLite FTS5](https://www.sqlite.org/fts5.html): готовый full-text engine.
- [XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP): MCP и CLI workflows.
- [Apple: signing settings](https://developer.apple.com/documentation/xcode/build-settings-reference?changes=_1).
