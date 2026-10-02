# SM-413 — Cache Hit Rate analytics window

Implemented on feat/sm-413-cache-analytics-window, independent of the pending core audit stack.

- Singleton SwiftUI Window: Sidebar button focuses/reuses the same analytics scene.
- Shared renderer, palette and exact privacy-safe report; no additional database aggregation.
- Slot-based zoom/pan preserves empty and DST calendar buckets; Y uses the complete report.
- Native Charts selection and keyboard-accessible bucket picker show aggregate details.
- The explorer that last opened the window owns updates. Other explorers cannot replace its report.
- On query change the old report is cleared before a report for the new scope is published.
- New viewport/ownership/scope-change and light/dark render regression tests.

## Validation

Passed: project generation, SwiftLint, FSD lint, architecture negative regression and git diff --check.
Architecture negative probe intentionally emits an invalid-dependency error and exits successfully.

Not run: app build, GUI tests and native interaction checks.
The disk repeatedly exhausted free space (100–500 MiB); source writes and XcodeGen failed during implementation.
Only this project's regenerated DerivedData index was removed, leaving dependencies and build products intact.
Xcode MCP diagnostics retrieval also failed with SourceEditorCallableDiagnosticError 5.
No command-line build was used. CI must compile and execute the new tests before merge.

The analytics report remains the last source-window snapshot if that explorer is closed;
opening from another explorer replaces its owner. No background duplicate queries were introduced.
