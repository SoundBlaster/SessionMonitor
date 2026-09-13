# SM-302b — Explicit session relationship tree

## Result

Добавлен pure `SessionTreeBuilder` в `MonitorCore`. Он строит presentation-only
дерево из `SessionSummary` и уже сохранённого `[String: SessionProvenance]`.
`UsageRecord`, `UsageTotals`, формат отчёта и canonical accounting не изменены.

Связь parent → child создаётся только из явного
`SessionProvenance.relationship.parentSessionID`. `rootSessionID` не создаёт
edge и используется только как corroborating evidence: противоречие с цепочкой
явного parent помечается `Conflict`. Никакие fork-отношения из косвенных полей
не выводятся.

Каждый session ID появляется ровно один раз, входной порядок сохраняется, а
totals остаются на собственном `SessionTreeNode` и не суммируются по дереву.
Сессии без provenance — root со state `Unknown`; отсутствующий parent — root
со state `Orphan`; циклические и конфликтующие связи — root со своим state.

GUI Session Explorer показывает эти nodes через `OutlineGroup`, включая state
и сохранение родительского контекста при поиске. CLI и menu bar UI не менялись.

## Verification

- `swift test --filter SessionTreeTests` — 6 tests passed.
- Покрыты: explicit parent → child, orphan, conflict, cycle, flat report без
  provenance, порядок и уникальность сессий.

## Ограничения

- Tree — display model; он не является новым accounting graph и не изменяет
  canonical totals.
- Conflict определяется только при наличии явного parent и противоречащего
  `rootSessionID`; косвенные fork hints намеренно не интерпретируются.
