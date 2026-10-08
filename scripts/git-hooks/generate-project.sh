#!/bin/sh
# Regenerates the local, Git-ignored Xcode project when the files it is generated from changed.
# Reads changed repository paths, one per line, from standard input.
#   --soft  never fail: used by post-* hooks, where a failure cannot undo the Git operation.
set -eu

soft=0
if [ "${1:-}" = "--soft" ]; then
    soft=1
fi

# The Xcode project and XcodeGen exist only on macOS; elsewhere app files can be committed freely.
# SESSIONMONITOR_OS overrides `uname -s` for the tests.
os=${SESSIONMONITOR_OS:-$(uname -s)}
if [ "$os" != Darwin ]; then
    exit 0
fi

repository_root=$(git rev-parse --show-toplevel)
cd "$repository_root"

if ! grep -Eq '^(Apps/MonitorMac/project\.yml|Apps/MonitorMac/Package\.resolved|Apps/MonitorMac/Sources/)'; then
    exit 0
fi

fail() {
    printf '%s\n' "$1" >&2
    if [ "$soft" -eq 1 ]; then
        exit 0
    fi
    exit 1
}

if [ "$soft" -eq 1 ]; then
    hint='Run make generate before building the app in Xcode.'
else
    hint='Fix it and retry the commit.'
fi

printf '%s\n' 'SessionMonitor: regenerating the local Xcode project for changed app files.'

pinned_xcodegen="$repository_root/.build/ci-tools/bin/xcodegen"
if [ -x "$pinned_xcodegen" ]; then
    XCODEGEN="$pinned_xcodegen" make generate || fail "make generate failed. $hint"
elif command -v xcodegen >/dev/null 2>&1; then
    make generate || fail "make generate failed. $hint"
else
    fail "XcodeGen is required. Run rtk proxy bash scripts/ci/install-tools.sh native or install the project-pinned XcodeGen. $hint"
fi
