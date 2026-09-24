# Dogfooding библиотек в Codex Monitor

Дата: 12 сентября 2026. Статус: архитектурное решение и план adoption;
первая интеграция и сборка выполнены. Статусы задач — в [ROADMAP.md](ROADMAP.md),
поддерживаемые возможности — в [README](README.md). Приложение использует SpecificationCore и
SpecificationKit как библиотеки, FSD как архитектуру/tooling, а NavigationSplitViewKit
как референс рабочей навигации по уточнению пользователя. Проверяются полезность
контрактов и стоимость интеграции.

## Роли и сценарии

| Проект | Роль в приложении | Первый проверяемый сценарий |
| --- | --- | --- |
| SpecificationCore | Общие diagnostic policies, исполняемые CLI и runtime | По snapshot выдать объяснимое finding; отличить отсутствие доказательств от отсутствия проблемы |
| SpecificationKit | Реактивные decisions и predicates GUI features | Кнопка сравнения и состояние recommendation panel обновляются при изменении выбранных сессий/coverage |
| NavigationSplitViewKit | Референс поведения нативной navigation, без обязательной package dependency | Проект → сессия → request/evidence; корректная selection при фильтре и обновлении данных |
| FSD | GUI architecture, генерация slices и architecture lint | Экран анализа, выделяемое действие ExportReport, проверка направления зависимостей |
| NestedA11yIDs | Иерархические стабильные accessibility identifiers для SwiftUI UI automation | Session Explorer: semantic IDs для навигации, viewport controls и выбранной сессии без изменения VoiceOver labels/traits |

Общие диагностические правила вычисляются в MonitorPolicies на SpecificationCore.
GUI использует их результаты и те же predicates через SpecificationKit; CLI и
GUI не поддерживают разные копии правила «можно сравнить эти две выборки».
UI-specific presentation decisions находятся в соответствующем GUI slice.

## NestedA11yIDs: устойчивые UI selectors

SessionMonitor использует NestedA11yIDs как UI-test selector contract: `.a11yRoot(...)`
задаёт границу screen/component, а `.nestedAccessibilityIdentifier(...)` строит
понятные dot-separated IDs для небольшого набора интерактивных и важных диагностических
элементов. Не размечать каждый leaf view и не выводить IDs из отображаемого текста.

Identifiers не заменяют VoiceOver labels, values, traits или hints. В release 1.0.0
модификатор также применяет `.accessibilityElement(children: .contain)`, поэтому миграция
должна учитывать существующие `.combine`/`.contain`, Charts и Button labels. Проверять
не только query-имена в UI tests, но и фактический accessibility tree; не принимать
неожиданное изменение группировки ради автоматической генерации IDs.

## SpecificationCore: правила с явными результатами

Проверенные API: `Specification.isSatisfiedBy`, композиция predicates,
`DecisionSpec.decide`, `FirstMatchSpec`, `decideWithMetadata`, `ContextProviding`
и static/generic providers. Для продукта вводим типизированный immutable snapshot
с coverage, model/harness, границами turns, статусом baseline и evidence pointers.
Сам snapshot — тип приложения, protocol не требует использовать словарь EvaluationContext.

Первые domain specs приложения:

- `HasSufficientCoverageSpec`: достаточно ли наблюдений для конкретного вывода.
- `ComparableCohortsSpec`: согласованы ли параметры двух сравниваемых групп.
- `UnchangedPollingEvidenceSpec`: подтверждено ли отсутствие изменений, а не
  только совпадение arguments инструмента.
- `CacheRegressionDecision`: confirmed signal, candidate или insufficient evidence
  с причинами и ссылками на исходные записи.

Это предложенные типы приложения, не существующие symbols библиотеки. `DecisionSpec`
позволяет вернуть typed result; `nil` не интерпретируется автоматически как
«всё хорошо». Неизвестные метрики сохраняются как неизвестные. `FirstMatchSpec`
уместен для выбора одного приоритетного действия. Все независимые findings
собираются отдельно, чтобы первый match не скрывал остальные проблемы.
Метаданные индекса matched rule сами по себе не являются объяснением: evidence,
rule ID и обоснование входят в domain result приложения.

Parser, dedup, file IO и транзакции остаются обычными алгоритмами с проверяемыми
инвариантами. Specification Pattern используется там, где есть самостоятельное
условие или решение, которое полезно именовать, комбинировать и тестировать.

CLI dogfooding считается состоявшимся, когда `report`/`doctor` действительно
исполняют эти specs и показывают их результаты, а fixtures покрывают positive,
negative и unknown cases. Простого `import SpecificationCore` недостаточно.

## SpecificationKit: живое состояние GUI

Проверенные `@ObservedSatisfies` и `@ObservedDecides` принимают explicit provider
и спецификацию. Для автоматических обновлений provider должен давать update
signals через `ContextUpdatesProviding`. SpecificationKit уже зависит от
SpecificationCore и реэкспортирует его типы.

Приложение связывает новые query snapshots с provider конкретного окна/feature.
UI наблюдает компактные domain values, а не читает БД или rollouts из body.
Первый пример: после изменения выбора сессий `ComparableCohortsSpec` управляет
доступностью Compare, а отдельный presentation decision объясняет disabled state
или показывает готовое сравнение. Аналогично работает recommendation panel.

Проверить смену selected session, обновление data watermark, переход unknown →
known, закрытие окна и независимость двух окон. Swift concurrency/observation
границы проверяются сборкой и interaction tests. Specs с closure-based type
erasure не объявляются Sendable без проверки; между executors предпочтительно
передавать immutable snapshots/results и выполнять evaluation у владельца spec.

## NavigationSplitViewKit: референс рабочей навигации

В проверенном main `NavigationModel` хранит `CustomColorCategory?` и `CustomColor?`;
`bootstrap` и `syncSelection` работают с `category.colors`. `CategoryView` также
принимает цветовые модели. Пользователь подтвердил использование этого проекта
как примера, поэтому обобщение публичного API и upstream changes не входят в
план приложения. Прямая SPM dependency на NavigationSplitViewKit не требуется.

Переносим проверяемые идеи: централизованный selection state, согласование
category/item, column visibility, inspector и восстановление допустимого выбора.
Приложение реализует собственный `SessionNavigationState` со стабильными ProjectID,
SessionID и при необходимости RequestID. Это предлагаемые app types. Реальные
переходы реализуются SwiftUI NavigationSplitView и композицией экранов по FSD.
App-wide routes и lifecycle окон находятся в app, state конкретного explorer —
в соответствующем page. Наблюдаемая модель принадлежит своему окну.

При изменении фильтра сохранить допустимую selection; при исчезновении элемента
очистить её или выбрать первый согласно явно заданной политике. Начальный выбор
задаётся после получения данных. Поведение macOS при resize и visibility колонок
проверяется самостоятельно: iOS size-class ветки demo не доказывают его на Mac.

Acceptance: Session Explorer воспроизводит нужные navigation behaviors,
фильтрация/удаление selection и inspector работают предсказуемо, два окна не
разделяют mutable state. В документации сохраняется ссылка на референс и
происхождение адаптированного кода. Это применение reference implementation,
а не заявление об интеграционном тестировании library API.

## FSD: GUI и направление зависимостей

Применяем контракт `app → pages → widgets → features → entities → shared`.
Начинаем с pages и извлекаем slices при реальной необходимости — это прямо
соответствует правилу Pages First в repository пользователя.

Начальная карта GUI:

```text
Apps/MonitorMac/Sources/
  app/                    # entrypoint, DI, window lifecycle и routes
  pages/session-explorer/ # первая страница: список, детали, evidence
  pages/overview/         # следующая страница: недельный обзор
  widgets/                # общие композиции по мере появления второго consumer
  features/export-report/ # самостоятельное действие с бизнес-результатом
  features/compare-runs/  # выбор/сравнение, когда доходим до этой возможности
  entities/session/      # GUI model/UI для canonical SessionID и snapshots
  entities/finding/      # представление finding и evidence
  shared/                 # общие UI primitives и технические utilities
```

Карта показывает целевую раскладку; все папки не генерируются заранее. Domain DTO
и policies из общего SPM package остаются каноническими. GUI entity slices
предоставляют их projections и entity-specific UI. DI связывается на верхнем
уровне; shared не становится складом domain logic. Sibling slices не импортируют
друг друга; orchestration размещается выше. SpecificationKit входит только в
те GUI slices, где нужны реактивные specification decisions.

В CLI/core сначала применяем small public APIs и однонаправленный SPM graph.
Import/report/compare можно выделять как use cases, но pages/widgets там не
появляются без своего смысла. FSD rules не требуют переноса SwiftData из demo:
в этом приложении storage остаётся GRDB.

Repository FSD предоставляет tooling, включая `fsd-ios lint` и SwiftPM command
plugin `fsd-generate`; `FSDToolingSupport` — вспомогательный marker target.
Эти компоненты не добавляются как runtime dependencies GUI. Root источников
настраивается через `.fsd-ios.yml`, поэтому для macOS проверяем правила на
`Apps/MonitorMac/Sources`, сохраняя собственный app target и build/test commands.
Architecture lint использует эвристику Swift symbol references; compiler-level
границы между SPM modules дополняют его. `harmonize` остаётся advisor.

## Первый вертикальный сценарий

1. Собрать минимальный dependency graph на выбранном toolchain: SpecificationCore
   для CLI/policies и SpecificationKit для macOS feature. Оба manifests подключают
   macro targets и SwiftSyntax от 510.0.0; стоимость clean build и совместимость
   с Swift 6.4 beta требуют проверки. Наличие UI-independent Core не означает
   отсутствия build-time dependencies.
2. Импортировать зафиксированный fixture, получить typed finding в CLI и проверить
   его reason/evidence и unknown case. Числовые результаты сверить с audit oracle.
3. Создать FSD page Session Explorer с собственной navigation state по референсу,
   показать то же finding, связать обновления snapshot с SpecificationKit provider.
4. Проверить смену selection, появление новых данных и экспорт отчёта; запустить
   FSD lint на реальном macOS source root. Отдельный negative fixture подтверждает,
   что архитектурная проверка обнаруживает запрещённую зависимость.

Успех — работающий пользовательский маршрут, небольшие явные adapters, одинаковые
domain decisions в CLI/GUI и воспроизводимые tests. Обнаруженные ограничения API
фиксируются с минимальным reproducer; расширения библиотек выполняются тогда,
когда их требует следующий согласованный сценарий. Локальные checkouts библиотек
в рамках этого исследования не менялись.

## Проверенные источники

Проверка выполнена по manifests и выбранным исходникам main, закреплённым commit
IDs. Снимки и metadata находятся в [ResearchReferences/dogfooding](ResearchReferences/dogfooding).
Это API inspection, не подтверждение успешной совместной сборки.

| Repository | Проверенный commit | Наблюдаемые version candidates |
| --- | --- | --- |
| SpecificationCore | `3e9af798feff7401962a40166cf3d6f41cbab867` | tag `1.0.0` |
| SpecificationKit | `d81e7f8a3586c9b4279044f984ae7830c6dd0b49` | tag `4.0.1`; manifest требует Core от `1.0.0` |
| NavigationSplitView | `94813a4e7fd44d0da836b42048429699bedc874f` | используется как reference source |
| FSD | `21731b9dd7d5008b832af5caca6d19f7a36fe54f` | tag `v0.4.0`; developer tooling |
| NestedA11yIDs | `ad123fbc8dda58f20de1e6fbd21120bcfbaabf85` | tag `1.0.0`; MIT; macOS 12+ |

Для первой сборки закреплялись SpecificationKit 4.0.0 и локальная копия
SpecificationCore 1.0.0 с [compatibility patch](Dependencies/README.md).
После выхода upstream-исправления текущая dependency переведена на SpecificationCore
1.1.0, закреплённый exact в `Package.swift`; resolved revision сохраняется в
`Package.resolved`. Текущий GUI pin — SpecificationKit 4.0.1 с upstream fix из
[PR #80](https://github.com/SoundBlaster/SpecificationKit/pull/80); его интеграция
проверена в SessionMonitor PR #48 через package resolution, native build, SwiftLint
и FSD lint. FSD 0.4.0 используется как установленный CLI. Таблица выше сохраняет
provenance исходного API inspection, а текущий resolved pin указан отдельно.

- [SpecificationCore: DecisionSpec](https://github.com/SoundBlaster/SpecificationCore/blob/3e9af798feff7401962a40166cf3d6f41cbab867/Sources/SpecificationCore/Core/DecisionSpec.swift)
  и [FirstMatchSpec](https://github.com/SoundBlaster/SpecificationCore/blob/3e9af798feff7401962a40166cf3d6f41cbab867/Sources/SpecificationCore/Specs/FirstMatchSpec.swift).
- [SpecificationKit: ObservedSatisfies](https://github.com/SoundBlaster/SpecificationKit/blob/4.0.1/Sources/SpecificationKit/Wrappers/ObservedSatisfies.swift)
  и [ObservedDecides](https://github.com/SoundBlaster/SpecificationKit/blob/4.0.1/Sources/SpecificationKit/Wrappers/ObservedDecides.swift).
- [NavigationSplitViewKit: NavigationModel](https://github.com/SoundBlaster/NavigationSplitView/blob/94813a4e7fd44d0da836b42048429699bedc874f/Sources/NavigationSplitViewKit/Models/NavigationModel.swift).
- [FSD: Architecture](https://github.com/SoundBlaster/FSD/blob/21731b9dd7d5008b832af5caca6d19f7a36fe54f/ARCHITECTURE.md),
  [configuration](https://github.com/SoundBlaster/FSD/blob/21731b9dd7d5008b832af5caca6d19f7a36fe54f/docs/configuration.md)
  и [external adoption](https://github.com/SoundBlaster/FSD/blob/21731b9dd7d5008b832af5caca6d19f7a36fe54f/docs/adoption/external-project.md).

У всех четырёх repositories указана MIT license; при использовании/адаптации
исходников сохраняются соответствующие notices. Транзитивные dependencies
проверяются по фактически разрешённому SPM graph.
