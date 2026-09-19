#!/bin/sh

set -eu

APP_ID="${ASC_APP_ID:-6812366729}"
EXPECTED_BUNDLE_ID="ru.egormerkushev.session-monitor"
PROJECT="${PROJECT:-Apps/MonitorMac/MonitorMac.xcodeproj}"
SCHEME="${SCHEME:-MonitorMac}"
RELEASE_ROOT="${RELEASE_ROOT:-.build/release-local}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-NO}"
CONFIRM_UPLOAD="${RELEASE_LOCAL_CONFIRM:-NO}"

usage() {
    cat <<'EOF'
Usage: scripts/release-local.sh [--archive-only] [--yes]

Creates a signed macOS archive and package locally. By default it asks before
uploading the package to App Store Connect. No GitHub or CI credentials are used.

Environment:
  ASC_APP_ID                    App Store Connect app ID (default: 6812366729)
  ALLOW_PROVISIONING_UPDATES=YES
                                Allow Xcode to update local provisioning assets
  RELEASE_LOCAL_CONFIRM=YES     Confirm upload without an interactive prompt
  RELEASE_ROOT                  Local artifact directory (default: .build/release-local)
EOF
}

ARCHIVE_ONLY=NO
while [ "$#" -gt 0 ]; do
    case "$1" in
        --archive-only) ARCHIVE_ONLY=YES ;;
        --yes) CONFIRM_UPLOAD=YES ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if [ "$APP_ID" != "6812366729" ]; then
    echo "Refusing to upload: this workflow is scoped to App Store Connect app 6812366729." >&2
    exit 2
fi

command -v asc >/dev/null 2>&1 || { echo "asc CLI is required." >&2; exit 2; }
command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is required." >&2; exit 2; }
command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen is required; run make generate setup first." >&2; exit 2; }

make generate >/dev/null

bundle_id="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null | awk -F ' = ' '$1 ~ /^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER$/ { print $2; exit }' | tr -d '[:space:]')"
if [ "$bundle_id" != "$EXPECTED_BUNDLE_ID" ]; then
    echo "Refusing to archive: project bundle ID is '$bundle_id', expected '$EXPECTED_BUNDLE_ID'." >&2
    exit 2
fi

app_json="$(asc apps view --id "$APP_ID" --output json)"
printf '%s\n' "$app_json" | grep -E '"bundleId"[[:space:]]*:[[:space:]]*"ru\.egormerkushev\.session-monitor"' >/dev/null || {
    echo "Refusing to upload: App Store Connect metadata does not match the expected bundle ID." >&2
    exit 2
}

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive_path="$RELEASE_ROOT/SessionMonitor-$timestamp.xcarchive"
pkg_path="$RELEASE_ROOT/SessionMonitor-$timestamp.pkg"
mkdir -p "$RELEASE_ROOT"

echo "Archiving $SCHEME for macOS..."
if [ "$ALLOW_PROVISIONING_UPDATES" = "YES" ]; then
    asc xcode archive --project "$PROJECT" --scheme "$SCHEME" --configuration Release --clean \
        --archive-path "$archive_path" --xcodebuild-flag=-destination \
        --xcodebuild-flag=generic/platform=macOS --xcodebuild-flag=-allowProvisioningUpdates --output json
else
    asc xcode archive --project "$PROJECT" --scheme "$SCHEME" --configuration Release --clean \
        --archive-path "$archive_path" --xcodebuild-flag=-destination \
        --xcodebuild-flag=generic/platform=macOS --output json
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$archive_path/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$archive_path/Info.plist")"

echo "Exporting version $version ($build_number) to $pkg_path..."
if [ "$ALLOW_PROVISIONING_UPDATES" = "YES" ]; then
    asc xcode export --archive-path "$archive_path" --pkg-path "$pkg_path" \
        --xcodebuild-flag=-allowProvisioningUpdates --output json
else
    asc xcode export --archive-path "$archive_path" --pkg-path "$pkg_path" --output json
fi

if [ "$ARCHIVE_ONLY" = "YES" ]; then
    echo "Archive-only mode: package created at $pkg_path"
    exit 0
fi

if [ "$CONFIRM_UPLOAD" != "YES" ]; then
    if [ ! -t 0 ]; then
        echo "Upload not confirmed in a non-interactive shell. Set RELEASE_LOCAL_CONFIRM=YES or use --yes." >&2
        exit 2
    fi
    printf 'Upload version %s (%s) to App Store Connect app %s? [y/N] ' "$version" "$build_number" "$APP_ID"
    read -r answer
    case "$answer" in
        y|Y|yes|YES) ;;
        *) echo "Upload cancelled. Package remains at $pkg_path"; exit 0 ;;
    esac
fi

echo "Uploading locally generated package..."
asc builds upload --app "$APP_ID" --pkg "$pkg_path" --version "$version" \
    --build-number "$build_number" --wait --output json

echo "Upload completed; App Store Connect processing finished for $version ($build_number)."
