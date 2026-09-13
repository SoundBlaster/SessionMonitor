# SM-302a — Existing database provenance backfill

## Изменённые файлы

- `Sources/CodexSource/RolloutDecoder.swift`
- `Sources/MonitorStore/UsageStore.swift`
- `Sources/MonitorRuntime/SessionMonitor.swift`
- `Tests/SessionMonitorTests/ExistingDatabaseBackfillTests.swift`
- `reports/SM-302a-existing-db-backfill.md`

## Механизм backfill

При штатном импорте source с canonical records и отсутствующей provenance runtime запускает отдельный metadata-only pass. Decoder перечитывает rollout-файл, но не декодирует usage records, формирует новый checkpoint schema v3 и возвращает metadata. Store атомарно записывает provenance и checkpoint; `source_records`, diagnostics и accounting не изменяются.

Checkpoint schema v2 декодируется обратно совместимо и повышается до v3 только вместе с успешным backfill. После этого обычный incremental path видит unchanged source и не перечитывает его повторно. Повторный запуск не находит missing provenance и читает 0 bytes.

Если rollout-файл отсутствует, directory scan его не возвращает: сохранённые canonical records остаются доступны, provenance остаётся отсутствующей, snapshot не падает.

## Targeted tests и результаты

Запущено:

```text
swift test --filter 'IncrementalImportTests|IncrementalStoreTests'
```

Результат: 18 тестов, 2 suites, passed.

```text
swift test --filter 'AccountingTests|IncrementalImportTests|IncrementalStoreTests|SourceRecoveryTests|ExistingDatabaseBackfillTests'
```

Результат: 37 тестов, 5 suites, passed.

Также targeted SwiftLint для изменённых core/runtime/store и связанных тестов: passed после исправления line length/type-body split. `git diff --check`: passed.

## Ограничения

- Metadata backfill работает только для rollout-файлов, доступных во время штатного directory scan.
- При изменении файла во время metadata read операция получает обычную `RolloutReadError` и будет повторена следующим запуском.
- Текущая модель provenance источника остаётся одной `SessionProvenance` на decoded rollout; parent/subagent/fork tree не добавлялся.

## Оставшиеся проблемы

- Для недоступных или удалённых rollout-файлов историческую provenance восстановить невозможно; она намеренно остаётся Unknown/отсутствующей.
- GUI и полный `make check` в рамках SM-302a не запускались по scope задачи.
