# SM-404 — SessionMonitor app icon

Дата: 2026-09-25

## Результат

- Создан редактируемый макет с иконой и организованными слоями в [Figma](https://www.figma.com/design/wuFWDUy7V5V8WdyXXcDwmE/SessionMonitor-App-Icon).
- По пользовательскому прототипу собран нативный `Apps/MonitorMac/SessionMonitor.icon` в Apple Icon Composer.
- Иконка использует монохромный график: тёмную основу, четыре вертикальных диапазона, средние маркеры, редкую сетку и два выброса. В Composer отключены эффекты Liquid Glass на рисунке, чтобы сохранить исходную геометрию; маска и системное оформление остаются нативными.
- `project.yml` объявляет `.icon` как единый file reference и связывает ресурс с app target. Xcode показывает `SessionMonitor.icon` как Icon Composer Icon, а в General → App Icons поле App Icon равно `SessionMonitor`.

## Проверки

- XcodeGen: `make generate` — успешно.
- SwiftLint: 0 нарушений в 130 файлах.
- FSD architecture lint: 0 ошибок, 0 предупреждений.
- `git diff --check` — успешно.
- Icon Composer previews: Default, Dark и Mono визуально проверены.
- Xcode MCP `BuildProject` — блокируется до компиляции ошибкой package trust: `Macro “SpecificationCoreMacros” ... was changed since a previous approval and must be enabled before it can be used`. Изменение icon resource не дошло до компиляции; требуется восстановить разрешение macro в Xcode и повторить сборку.

## Ограничение

В `SessionMonitor.icon` текущий artwork импортирован единым векторным SVG foreground layer. Исходные элементы отдельно организованы и редактируются в Figma.
