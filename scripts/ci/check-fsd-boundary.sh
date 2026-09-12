#!/usr/bin/env bash
# Confirm that the configured architecture gate rejects a real upward dependency.
set -euo pipefail

fixture=$(mktemp -d "${TMPDIR:-/tmp}/session-monitor-fsd.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/pages/explorer/ui" "$fixture/shared/ui"
printf '%s\n' 'struct ExplorerPage {}' > "$fixture/pages/explorer/ui/ExplorerPage.swift"
printf '%s\n' 'struct Invalid { let page = ExplorerPage() }' > "$fixture/shared/ui/Invalid.swift"

if "${FSD:-fsd-ios}" lint --root "$fixture" --config .fsd-ios.yml --strict --architecture > "$fixture/result.log" 2>&1; then
  echo 'Architecture gate accepted shared -> pages' >&2
  exit 1
fi
cat "$fixture/result.log"
grep -F 'Invalid FSD dependency direction' "$fixture/result.log" > /dev/null
grep -F 'shared' "$fixture/result.log" > /dev/null
grep -F 'ExplorerPage' "$fixture/result.log" > /dev/null
