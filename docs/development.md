# Development

[← SessionMonitor](../README.md) · [Contribution workflow](../CONTRIBUTING.md)

## Build from source

The app targets macOS 15+. Development uses Xcode and Swift, with pinned SwiftLint, XcodeGen,
and FSD tooling. Current native CI uses Xcode 27, with an additional Xcode 26.0 compatibility
build; consult the [workflow](../.github/workflows/ci.yml) for the exact toolchain configuration.

```sh
git clone https://github.com/SoundBlaster/SessionMonitor.git
cd SessionMonitor
make init
open Apps/MonitorMac/MonitorMac.xcodeproj
```

Select the **MonitorMac** scheme and **My Mac**, then build/run. `make init` installs the pinned
tools and Git hooks, resolves packages, and generates the Xcode project. Run it on first setup
and after pulling tool/workflow changes. It produces build/cache artifacts: honor any local
external-disk cache policy and pass the appropriate Make/Xcode path overrides before running it.

`Apps/MonitorMac/project.yml` is the canonical project definition. `make generate` regenerates
the `.xcodeproj`; installed post-checkout/merge/rewrite hooks do this after Git operations.
Install/update hooks with `make install-hooks`. If hooks are unavailable, run generation manually
when new files are missing in Xcode. Preserve root and app `Package.resolved` files.

## Local signing and macros

Use the ignored `Apps/MonitorMac/Local.xcconfig` for persistent signing overrides:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
CODE_SIGN_IDENTITY = Apple Development
```

Signing changes made only in the generated Xcode project are lost on regeneration.
`make generate` creates an ad-hoc local configuration if absent and does not overwrite an
existing one. Signed app/widget behavior requires the appropriate App Group provisioning;
a successful ad-hoc build does not establish widget distribution readiness.

The Makefile’s build path uses `-skipMacroValidation` for the pinned SpecificationCore/Kit
macros without changing global Xcode trust settings. Review the dependency pins before using
that bypass; after granting trust in Xcode, pass `XCODEBUILD_FLAGS=` if no bypass is needed.
When working with an open Xcode through an agent, use xcode-tools MCP for discovery, scheme/
destination selection, builds, tests, and debugging. The package scheme and app scheme cover
different suites; do not interchange their results.

## CLI and Linux

```sh
make build-cli-release
swift run codex-monitor import ~/.codex/sessions
swift run codex-monitor report --json
```

When installing a locally built CLI, use the same flags/scratch path for building and locating it:

```sh
make build-cli-release
install -m 755 "$(swift build -c release --show-bin-path)/codex-monitor" ~/.local/bin/codex-monitor
```

Create `~/.local/bin` first and put it on `PATH`. If you supplied `SWIFT_FLAGS`, include the same
flags in `swift build --show-bin-path`. Do not assume a default `.build` path when using custom caches.

The CLI also builds on Linux (CI uses Ubuntu 24.04 / Swift 6.2):

```sh
swift build --product codex-monitor
make check-linux
```

Linux Watch polls every two seconds, file identity uses device/inode without birth time, and
App Group widget snapshots are not written. The GUI, widgets, and macOS notifications are macOS-only.

## Quality checks

| Command | Scope |
| --- | --- |
| `make check-core` | CLI build, core lint/tests, and CLI process smoke. |
| `make test-cli` | Watch, snapshot, quota, and performance smoke after a CLI build. |
| `make build-macos` | Generated-project app build via xcodebuild. |
| `make build-mcp` | App build through the separate XcodeBuildMCP CLI. |
| `make test-macos` | App/model/render and configured UI tests. |
| `make lint-architecture` | FSD architecture rules. |
| `make check` | Sequential local quality gates. |
| `make ci` | Native gates with locked packages and ad-hoc signing. |
| `make lint-ci` | Workflow validation with actionlint. |
| `make check-linux` | CLI/core/process checks without Xcode or GUI. |

Use a verified build/cache location before artifact-producing commands. Documentation-only
changes need link, command, status, and formatting checks; they do not require a fresh app build.
CI still runs on every PR. Build/test success does not establish visual, runtime, notification,
widget, or clean-install behavior: record those checks separately.

Use `make benchmark` for isolated archive measurements and [the performance guide](performance/README.md)
for methodology. Raw logs, personal audit outputs, signing material, and build artifacts stay out of Git.

## Architecture and project references

The app, CLI, menu bar, and widgets share the core domain/query layer. SpecificationCore holds
policies, SpecificationKit connects reactive GUI state, and the app follows Pages First FSD.
Keep ownership/deduplication, unknown values, provenance, and atomic writes intact.

- [Architecture](../monitor-design.md), [roadmap](../ROADMAP.md), and [agent rules](../AGENTS.md).
- [Design System](design-system.md) and [Context insights](context-insights.md).
- [Dependency provenance and compatibility](../Dependencies/README.md).
- [Reuse policy](../quality-and-reuse.md) and [dogfooding plan](../dogfooding-plan.md).
- [Third-party licenses](../THIRD_PARTY_NOTICES.md).

See [Contributing](../CONTRIBUTING.md) for required PR gates, hooks, and workflow details.
