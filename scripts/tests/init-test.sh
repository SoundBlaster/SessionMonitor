#!/bin/sh
# Runs scripts/init.sh in a throwaway repository whose make targets and tool installer are stubs.
set -eu

source_root=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export HOME="$work/home"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
mkdir -p "$HOME"

repo="$work/repo"
log="$work/init.log"
export INIT_LOG="$log"

mkdir -p "$repo/scripts/ci"
cp "$source_root/scripts/init.sh" "$repo/scripts/init.sh"

# Stub make targets: record the call, fail when FAIL_TARGET names the target.
# The dollar signs are for make, not for this shell.
# shellcheck disable=SC2016
{
    for target in install-hooks resolve generate doctor; do
        printf '%s:\n\t@echo "%s SWIFT=$(SWIFT)" >>"$$INIT_LOG"; test "$$FAIL_TARGET" != %s\n' "$target" "$target" "$target"
    done
} >"$repo/Makefile"

# Stub installer: record the call and create the three pinned tools like the real one.
cat >"$repo/scripts/ci/install-tools.sh" <<'STUB'
#!/usr/bin/env bash
echo "install-tools $1" >>"$INIT_LOG"
mkdir -p .build/ci-tools/bin
for tool in swiftlint xcodegen fsd-ios; do
    printf '#!/bin/sh\n' >".build/ci-tools/bin/$tool"
    chmod 755 ".build/ci-tools/bin/$tool"
done
STUB

git -C "$repo" init -q -b main

failures=0
check() {
    description=$1
    shift
    if "$@"; then
        printf 'ok   %s\n' "$description"
    else
        printf 'FAIL %s\n' "$description" >&2
        failures=$((failures + 1))
    fi
}

run_init() {
    (cd "$repo" && INIT_OS=$1 FAIL_TARGET=${2:-none} sh scripts/init.sh) >"$work/out.txt" 2>"$work/err.txt"
}

log_is() {
    printf '%s\n' "$@" >"$work/expected.log"
    diff "$work/expected.log" "$log" >/dev/null
}

# macOS, first run: tools are installed before anything uses them, then everything in order.
: >"$log"
check "macOS first run succeeds" run_init Darwin
check "macOS first run runs every step in order" log_is \
    'install-tools native' 'install-hooks SWIFT=' 'resolve SWIFT=' \
    'generate SWIFT=' 'doctor SWIFT='
check "macOS first run says what to do next" grep -q 'Open Apps/MonitorMac/MonitorMac.xcodeproj' "$work/out.txt"

# macOS, second run: pinned tools are not downloaded again.
: >"$log"
check "macOS second run succeeds" run_init Darwin
check "macOS second run skips the tool download" log_is \
    'install-hooks SWIFT=' 'resolve SWIFT=' 'generate SWIFT=' \
    'doctor SWIFT='
check "macOS second run reports the tools as current" grep -q 'match the pins' "$work/out.txt"

# A changed pin in the installer makes the installed tools stale, so they are installed again.
printf '# new pin\n' >>"$repo/scripts/ci/install-tools.sh"
: >"$log"
check "macOS run after a pin change succeeds" run_init Darwin
check "a changed pin reinstalls the tools" log_is \
    'install-tools native' 'install-hooks SWIFT=' 'resolve SWIFT=' 'generate SWIFT=' 'doctor SWIFT='
: >"$log"
check "the run after the reinstall skips the download again" run_init Darwin
check "the reinstall was recorded" sh -c "! grep -q install-tools '$log'"

# Tools without a record of their pins (installed by hand or by an older init) are installed again.
rm "$repo/.build/ci-tools/installed-pins"
: >"$log"
check "macOS run without a pin record succeeds" run_init Darwin
check "tools without a pin record are installed again" grep -q 'install-tools native' "$log"

# One broken tool does not hide the other results, and the exit code says so.
: >"$log"
if (cd "$repo" && INIT_OS=Darwin FAIL_TARGET=install-hooks sh scripts/init.sh) >"$work/out.txt" 2>"$work/err.txt"; then
    printf 'FAIL init succeeded although a step failed\n' >&2
    failures=$((failures + 1))
else
    printf 'ok   init exits non-zero when a step fails\n'
fi
check "later steps still ran after the failure" grep -q '^generate' "$log"
check "the summary names the failed step" grep -q 'Git hooks' "$work/err.txt"

# Linux: only the steps that apply, with the plain swift binary.
rm -rf "$repo/.build"
: >"$log"
check "Linux run succeeds" run_init Linux
check "Linux runs hooks and resolve only" log_is 'install-hooks SWIFT=' 'resolve SWIFT=swift'
check "Linux explains what was skipped" grep -q 'need macOS' "$work/out.txt"

if [ "$failures" -ne 0 ]; then
    printf '%s init checks failed.\n' "$failures" >&2
    exit 1
fi
printf 'make init test passed.\n'
