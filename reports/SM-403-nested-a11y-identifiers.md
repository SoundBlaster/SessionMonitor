# SM-403 — hierarchical accessibility identifiers

## Outcome

Added the MIT [NestedA11yIDs 1.0.0](https://github.com/SoundBlaster/NestedA11yIDs/releases/tag/1.0.0)
Swift package to the macOS app target only. Existing identifiers now use component roots and
semantic child identifiers for the request timeline, viewport controls, cache-hit widget,
chart distribution, settings palette, and Session Explorer toolbar actions. Identifiers remain
separate from VoiceOver labels, values, hints, and display copy.

The migration replaces existing `.contain` boundaries with the package root/nested modifiers
where those boundaries already existed. It does not apply nested IDs to session rows using
`.combine`. A new `MonitorMacUITests` target includes a UI test for the primary toolbar controls.

## Validation

- `make generate` — passed.
- `xcodebuild -resolvePackageDependencies -project Apps/MonitorMac/MonitorMac.xcodeproj -scheme MonitorMac` — passed; NestedA11yIDs resolved to tag `1.0.0`, revision `ad123fbc8dda58f20de1e6fbd21120bcfbaabf85`.
- Xcode MCP `XcodeListTargets` — confirmed `MonitorMacUITests` is in the generated project.
- Xcode MCP `GetTestList` — confirmed `AccessibilityIdentifierUITests/testSessionExplorerControlsExposeStableAccessibilityIdentifiers()` is in the active scheme.
- `make lint lint-architecture` — passed; SwiftLint reported 0 violations and FSD strict architecture lint reported 0 errors and 0 warnings.
- `make test-architecture` — passed; its fixture intentionally prints the rejected `shared -> pages` dependency as a regression check.
- `git diff --check` — passed.
- Xcode MCP `BuildProject` — blocked before compilation because Xcode requires package macro execution to be enabled again for the changed `SpecificationCoreMacros` and `SpecificationKitMacros` sources. No macro-validation bypass was used. Consequently, the local UI test and app build have not run; GitHub CI is the next build validation.
- GitHub CI on revision `6301531` found one UI-test failure: `sessionExplorer.accountScope` was not exposed as a button. Import, Update, and Inspector controls were found. Replaced the root wrapper on native `Button` controls with direct accessibility identifiers so the AX button role is retained; the current revision still needs CI validation.

## Boundaries

No accounting, navigation, or VoiceOver copy was intentionally changed. The UI test verifies toolbar IDs; final runtime inspection of timeline, DatePicker, and Charts accessibility grouping remains dependent on a successful Xcode build and is a review limitation for this PR.

PR: [#64](https://github.com/SoundBlaster/SessionMonitor/pull/64). The current revision's GitHub checks run after push and are not actively polled, following the project no-poll rule.
