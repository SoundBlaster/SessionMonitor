#!/bin/sh
# One-command setup and refresh of the development environment. Safe to run again after every pull.
# INIT_OS overrides `uname -s`; the tests use it to exercise both platforms.
set -eu

repository_root=$(git rev-parse --show-toplevel)
cd "$repository_root"

os=${INIT_OS:-$(uname -s)}
pinned=.build/ci-tools/bin
failed=""

step() {
    printf '\n==> %s\n' "$1"
}

# A failed step is recorded and the routine goes on: one missing tool should not hide the other results.
run() {
    name=$1
    shift
    step "$name"
    if "$@"; then
        return 0
    fi
    failed="$failed
  - $name"
}

tools_present() {
    for tool in swiftlint xcodegen fsd-ios; do
        [ -x "$pinned/$tool" ] || return 1
    done
}

if [ "$os" = Darwin ]; then
    if tools_present; then
        step 'Pinned tools'
        printf '%s\n' "SwiftLint, XcodeGen and fsd-ios are already installed in $pinned."
    else
        run 'Pinned tools' bash scripts/ci/install-tools.sh native
    fi
    run 'Git hooks' make install-hooks
    run 'Swift packages' make resolve
    run 'Xcode project' make generate
    run 'Toolchain' make doctor
else
    run 'Git hooks' make install-hooks
    run 'Swift packages' make resolve SWIFT=swift
    step 'Skipped'
    printf '%s\n' 'Pinned tools, the Xcode project and the app need macOS; the CLI and core tests are ready.'
fi

printf '\n'
if [ -n "$failed" ]; then
    printf 'make init finished with problems:%s\nFix them and run make init again.\n' "$failed" >&2
    exit 1
fi

if [ "$os" = Darwin ]; then
    printf '%s\n' 'Ready. Open Apps/MonitorMac/MonitorMac.xcodeproj in Xcode. Run make init again after every pull.'
else
    printf '%s\n' 'Ready. Run make check-linux to build and test the CLI.'
fi
