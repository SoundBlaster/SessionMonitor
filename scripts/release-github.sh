#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

skip_notarization=0
case "${1:-}" in
    "") ;;
    --skip-notarize) skip_notarization=1 ;;
    --help|-h)
        cat <<'EOF'
Usage: scripts/release-github.sh [--skip-notarize]

Builds a clean Release archive signed with Developer ID, verifies the app and
WidgetKit extension, and creates a notarized/stapled DMG. The skip option is
only for local signing/package checks; that artifact cannot be published.

Configuration is supplied through Makefile variables. See README.md.
EOF
        exit 0
        ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
esac

project="${PROJECT:-Apps/MonitorMac/MonitorMac.xcodeproj}"
scheme="${SCHEME:-MonitorMac}"
xcodebuild_bin="${XCODEBUILD:-xcodebuild}"
xcodegen_bin="${XCODEGEN:-xcodegen}"
swift_bin="${SWIFT:-swift}"
release_root="${RELEASE_ROOT:-.build/release-github}"
derived_data="${DERIVED_DATA:-$release_root/DerivedData}"
cli_scratch_root="${CLI_SCRATCH_ROOT:-$release_root/SwiftPM}"
swiftpm_cache="${SWIFTPM_CACHE_PATH:-$release_root/SwiftPMCache}"
notary_profile="${NOTARY_PROFILE:-}"
allow_provisioning_updates="${ALLOW_PROVISIONING_UPDATES:-NO}"
expected_bundle_id="ru.egormerkushev.session-monitor"
widget_bundle_id="ru.egormerkushev.session-monitor.widget"
app_group_id="group.ru.egormerkushev.session-monitor"

for command_name in "$xcodebuild_bin" "$xcodegen_bin" "$swift_bin" security codesign lipo ditto hdiutil xcrun python3; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Required command not found: $command_name" >&2
        exit 2
    }
done

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Refusing a release build from a dirty working tree. Commit or preserve local changes first." >&2
    exit 2
fi
[[ "$(git branch --show-current)" == "main" ]] || {
    echo "Refusing a release build: check out main after the release changes are merged." >&2
    exit 2
}
git fetch --quiet origin
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || {
    echo "Refusing a release build: local main is not the current origin/main." >&2
    exit 2
}
source_revision="$(git rev-parse HEAD)"

make generate XCODEGEN="$xcodegen_bin" >/dev/null
[[ -d "$project" ]] || { echo "Generated Xcode project not found: $project" >&2; exit 2; }

xcodebuild_flags=()
has_xcodebuild_flags=0
if [[ -n "${XCODEBUILD_FLAGS:-}" && -n "${XCODEBUILD_FLAGS//[[:space:]]/}" ]]; then
    read -r -a xcodebuild_flags <<< "$XCODEBUILD_FLAGS"
    has_xcodebuild_flags=1
fi
run_xcodebuild() {
    if (( has_xcodebuild_flags )); then
        "$xcodebuild_bin" "${xcodebuild_flags[@]}" "$@"
    else
        "$xcodebuild_bin" "$@"
    fi
}

settings_json="$(run_xcodebuild -project "$project" -scheme "$scheme" \
    -configuration Release -showBuildSettings -json)"
release_metadata="$(printf '%s' "$settings_json" | python3 -c '
import json, sys
records = json.load(sys.stdin)
target = next((r for r in records if r.get("target") == "MonitorMac"), None)
if target is None:
    raise SystemExit("MonitorMac target build settings were not returned")
settings = target["buildSettings"]
print("\t".join((settings.get("MARKETING_VERSION", ""),
                  settings.get("DEVELOPMENT_TEAM", ""),
                  settings.get("PRODUCT_BUNDLE_IDENTIFIER", ""))))
')"
IFS=$'\t' read -r version team_id actual_bundle_id <<< "$release_metadata"
[[ "$actual_bundle_id" == "$expected_bundle_id" ]] || {
    echo "Refusing to archive unexpected bundle ID: $actual_bundle_id" >&2
    exit 2
}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]] || {
    echo "Invalid MARKETING_VERSION in the Release target: '$version'" >&2
    exit 2
}
[[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] || {
    echo "No valid DEVELOPMENT_TEAM is configured for Release. Set it in Local.xcconfig or the environment." >&2
    exit 2
}

identity_candidates="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -nE 's/.*"(Developer ID Application: [^"]+)"/\1/p' \
    | grep -F "($team_id)" || true)"
identity_count="$(printf '%s\n' "$identity_candidates" | awk 'NF { count++ } END { print count + 0 }')"
[[ "$identity_count" == "1" ]] || {
    echo "Expected exactly one valid Developer ID Application identity for team $team_id; found $identity_count." >&2
    echo "Install/select the correct certificate and private key in Keychain, then retry." >&2
    exit 2
}
signing_identity="$identity_candidates"

if (( ! skip_notarization )); then
    [[ -n "$notary_profile" ]] || {
        echo "Set NOTARY_PROFILE to a notarytool Keychain profile (for example, an existing local profile)." >&2
        exit 2
    }
    xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1 || {
        echo "Cannot use notarytool profile '$notary_profile'. Configure it locally with notarytool first." >&2
        exit 2
    }
fi

mkdir -p "$release_root" "$derived_data"
release_root="$(cd "$release_root" && pwd)"
derived_data="$(cd "$derived_data" && pwd)"
archive_path="$release_root/SessionMonitor-$version.xcarchive"
export_path="$release_root/export"
export_options_path="$release_root/DeveloperIDExportOptions.plist"
dmg_path="$release_root/SessionMonitor-$version.dmg"
checksum_path="$release_root/SessionMonitor-$version.dmg.sha256"
cli_arm64_scratch="$cli_scratch_root/arm64"
cli_x86_64_scratch="$cli_scratch_root/x86_64"
cli_package_path="$release_root/codex-monitor-$version-macos-universal"
cli_archive_path="$release_root/codex-monitor-$version-macos-universal.zip"
cli_binary_path="$cli_package_path/codex-monitor"
cli_checksum_path="$release_root/codex-monitor-$version-macos-universal.zip.sha256"
app_path="$export_path/SessionMonitor.app"

for path in "$archive_path" "$export_path" "$export_options_path" "$dmg_path" "$checksum_path" "$cli_arm64_scratch" \
    "$cli_x86_64_scratch" "$cli_package_path" "$cli_archive_path" "$cli_checksum_path" \
    "$release_root/source-revision.txt" \
    "$release_root/notary-app.json" "$release_root/notary-cli.json" "$release_root/notary-dmg.json"; do
    [[ ! -e "$path" ]] || {
        echo "Refusing to overwrite existing release artifact: $path" >&2
        exit 2
    }
done

archive_args=(
    -project "$project"
    -scheme "$scheme"
    -configuration Release
    -destination generic/platform=macOS
    -derivedDataPath "$derived_data"
    -archivePath "$archive_path"
    CODE_SIGN_STYLE=Automatic
    "DEVELOPMENT_TEAM=$team_id"
    ENABLE_HARDENED_RUNTIME=YES
    REGISTER_APP_GROUPS=YES
    ARCHS="arm64 x86_64"
    ONLY_ACTIVE_ARCH=NO
)
if [[ "${CLONED_SOURCE_PACKAGES_DIR:-}" != "" ]]; then
    mkdir -p "$CLONED_SOURCE_PACKAGES_DIR"
    archive_args+=(-clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_DIR")
fi
if [[ "${PACKAGE_CACHE_PATH:-}" != "" ]]; then
    mkdir -p "$PACKAGE_CACHE_PATH"
    archive_args+=(-packageCachePath "$PACKAGE_CACHE_PATH")
fi
if [[ "$allow_provisioning_updates" == "YES" ]]; then
    archive_args+=(-allowProvisioningUpdates)
elif [[ "$allow_provisioning_updates" != "NO" ]]; then
    echo "ALLOW_PROVISIONING_UPDATES must be YES or NO." >&2
    exit 2
fi
archive_args+=(archive)

echo "Archiving SessionMonitor $version for Developer ID ($team_id)..."
run_xcodebuild "${archive_args[@]}"

python3 - "$export_options_path" "$team_id" <<'PY'
import plistlib, sys
path, team_id = sys.argv[1:]
options = {
    "destination": "export",
    "method": "developer-id",
    "signingStyle": "automatic",
    "stripSwiftSymbols": True,
    "teamID": team_id,
}
with open(path, "wb") as output:
    plistlib.dump(options, output)
PY

export_args=(
    -exportArchive
    -archivePath "$archive_path"
    -exportPath "$export_path"
    -exportOptionsPlist "$export_options_path"
)
if [[ "$allow_provisioning_updates" == "YES" ]]; then
    export_args+=(-allowProvisioningUpdates)
fi
echo "Exporting SessionMonitor with Developer ID signing..."
run_xcodebuild "${export_args[@]}"
[[ -d "$app_path" ]] || { echo "Exported app not found: $app_path" >&2; exit 1; }

mkdir -p "$cli_package_path" "$cli_arm64_scratch" "$cli_x86_64_scratch" "$swiftpm_cache"
echo "Building universal codex-monitor CLI $version..."
"$swift_bin" build --package-path "$repo_root" --scratch-path "$cli_arm64_scratch" \
    --cache-path "$swiftpm_cache" --triple arm64-apple-macosx15.0 \
    --configuration release --product codex-monitor
"$swift_bin" build --package-path "$repo_root" --scratch-path "$cli_x86_64_scratch" \
    --cache-path "$swiftpm_cache" --triple x86_64-apple-macosx15.0 \
    --configuration release --product codex-monitor
arm64_cli="$cli_arm64_scratch/arm64-apple-macosx/release/codex-monitor"
x86_64_cli="$cli_x86_64_scratch/x86_64-apple-macosx/release/codex-monitor"
[[ -x "$arm64_cli" && -x "$x86_64_cli" ]] || {
    echo "SwiftPM did not produce both architecture-specific codex-monitor executables." >&2
    exit 1
}
lipo -create "$arm64_cli" "$x86_64_cli" -output "$cli_binary_path"
codesign --force --options runtime --timestamp --sign "$signing_identity" "$cli_binary_path"
codesign --verify --strict --verbose=2 "$cli_binary_path"
cli_signature="$(codesign -d --verbose=4 "$cli_binary_path" 2>&1)"
grep -F "TeamIdentifier=$team_id" <<< "$cli_signature" >/dev/null || {
    echo "CLI signature team mismatch." >&2
    exit 1
}
grep -E 'flags=.*\(runtime\)' <<< "$cli_signature" >/dev/null || {
    echo "CLI hardened runtime is missing." >&2
    exit 1
}
cli_architectures="$(lipo -archs "$cli_binary_path")"
[[ " $cli_architectures " == *" arm64 "* && " $cli_architectures " == *" x86_64 "* ]] || {
    echo "Expected universal CLI binary; found: $cli_architectures" >&2
    exit 1
}
cat > "$cli_package_path/Install.txt" <<EOF
codex-monitor $version (macOS universal)

Install the executable in a directory on your PATH, for example:
  install -m 755 codex-monitor ~/.local/bin/codex-monitor

The CLI reads Codex session logs locally. Run codex-monitor --help for commands.
EOF
cp LICENSE THIRD_PARTY_NOTICES.md "$cli_package_path/"
ditto -c -k --sequesterRsrc --keepParent "$cli_package_path" "$cli_archive_path"

check_bundle() {
    local bundle_path="$1"
    local expected_id="$2"
    local actual_id executable signature profile_path profile_file entitlements_file

    actual_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle_path/Contents/Info.plist")"
    [[ "$actual_id" == "$expected_id" ]] || {
        echo "Unexpected bundle ID in $bundle_path: $actual_id" >&2
        return 1
    }

    executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle_path/Contents/Info.plist")"
    local binary_path="$bundle_path/Contents/MacOS/$executable"
    local architectures
    architectures="$(lipo -archs "$binary_path")"
    [[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]] || {
        echo "Expected arm64 and x86_64 in $binary_path; found: $architectures" >&2
        return 1
    }

    signature="$(codesign -d --verbose=4 "$bundle_path" 2>&1)"
    grep -F "TeamIdentifier=$team_id" <<< "$signature" >/dev/null || {
        echo "Code signature team mismatch in $bundle_path." >&2
        return 1
    }
    grep -F 'Authority=Developer ID Application:' <<< "$signature" >/dev/null || {
        echo "Bundle is not signed by a Developer ID Application certificate: $bundle_path" >&2
        return 1
    }
    grep -E 'flags=.*\(runtime\)' <<< "$signature" >/dev/null || {
        echo "Hardened runtime is missing from $bundle_path." >&2
        return 1
    }

    profile_path="$bundle_path/Contents/embedded.provisionprofile"
    [[ -f "$profile_path" ]] || {
        echo "Missing embedded Developer ID provisioning profile in $bundle_path." >&2
        return 1
    }
    profile_file="$(mktemp "${TMPDIR:-/tmp}/sessionmonitor-profile.XXXXXX")"
    if ! security cms -D -i "$profile_path" > "$profile_file"; then
        rm -f "$profile_file"
        echo "Cannot decode embedded provisioning profile in $bundle_path." >&2
        return 1
    fi
    if ! python3 - "$profile_file" "$expected_id" "$team_id" "$app_group_id" <<'PY'
import datetime, fnmatch, plistlib, sys
path, bundle_id, team_id, app_group = sys.argv[1:]
with open(path, "rb") as source:
    profile = plistlib.load(source)
entitlements = profile.get("Entitlements", {})
expected_app_id = f"{team_id}.{bundle_id}"
if team_id not in profile.get("TeamIdentifier", []):
    raise SystemExit("Provisioning profile has the wrong Team ID")
if not fnmatch.fnmatchcase(expected_app_id, entitlements.get("com.apple.application-identifier", "")):
    raise SystemExit("Provisioning profile does not authorize this bundle ID")
groups = entitlements.get("com.apple.security.application-groups", [])
if not any(fnmatch.fnmatchcase(app_group, allowed) for allowed in groups):
    raise SystemExit("Provisioning profile does not authorize the SessionMonitor App Group")
expires = profile.get("ExpirationDate")
if expires is not None:
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=datetime.timezone.utc)
    if expires <= datetime.datetime.now(datetime.timezone.utc):
        raise SystemExit("Embedded provisioning profile has expired")
PY
    then
        rm -f "$profile_file"
        echo "Embedded provisioning profile validation failed in $bundle_path." >&2
        return 1
    fi
    rm -f "$profile_file"

    entitlements_file="$(mktemp "${TMPDIR:-/tmp}/sessionmonitor-entitlements.XXXXXX")"
    if ! codesign -d --entitlements :- "$bundle_path" 2>/dev/null > "$entitlements_file"; then
        rm -f "$entitlements_file"
        echo "Cannot read signed entitlements from $bundle_path." >&2
        return 1
    fi
    if ! python3 - "$entitlements_file" "$app_group_id" <<'PY'
import fnmatch, plistlib, sys
path, app_group = sys.argv[1:]
with open(path, "rb") as source:
    entitlements = plistlib.load(source)
groups = entitlements.get("com.apple.security.application-groups", [])
if not any(fnmatch.fnmatchcase(app_group, allowed) for allowed in groups):
    raise SystemExit("Signed entitlements do not include the SessionMonitor App Group")
if entitlements.get("com.apple.security.get-task-allow") is True:
    raise SystemExit("get-task-allow must not be enabled in a distribution build")
PY
    then
        rm -f "$entitlements_file"
        echo "Signed entitlement validation failed in $bundle_path." >&2
        return 1
    fi
    rm -f "$entitlements_file"
}

widget_path="$app_path/Contents/PlugIns/SessionMonitorWidgetExtension.appex"
[[ -d "$widget_path" ]] || { echo "Embedded WidgetKit extension not found: $widget_path" >&2; exit 1; }
check_bundle "$app_path" "$expected_bundle_id"
check_bundle "$widget_path" "$widget_bundle_id"
codesign --verify --deep --strict --verbose=2 "$app_path"

if (( ! skip_notarization )); then
    app_zip="$release_root/.SessionMonitor-$version-notary.zip"
    trap 'rm -f "$app_zip"' EXIT
    ditto -c -k --keepParent "$app_path" "$app_zip"
    echo "Submitting app to Apple notarization..."
    app_submission="$(xcrun notarytool submit "$app_zip" --keychain-profile "$notary_profile" \
        --wait --output-format json)"
    printf '%s\n' "$app_submission" > "$release_root/notary-app.json"
    app_submission_id="$(printf '%s' "$app_submission" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))')"
    app_status="$(printf '%s' "$app_submission" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status", ""))')"
    if [[ "$app_status" != "Accepted" ]]; then
        if [[ -n "$app_submission_id" ]]; then
            xcrun notarytool log "$app_submission_id" --keychain-profile "$notary_profile" \
                "$release_root/notary-app-log.json" || true
        fi
        echo "Apple did not accept the app submission (status: $app_status)." >&2
        exit 1
    fi
    xcrun stapler staple "$app_path"
    xcrun stapler validate "$app_path"
    spctl -a -vv -t exec "$app_path"
    rm -f "$app_zip"
    trap - EXIT

    echo "Submitting standalone CLI archive to Apple notarization..."
    cli_submission="$(xcrun notarytool submit "$cli_archive_path" --keychain-profile "$notary_profile" \
        --wait --output-format json)"
    printf '%s\n' "$cli_submission" > "$release_root/notary-cli.json"
    cli_submission_id="$(printf '%s' "$cli_submission" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))')"
    cli_status="$(printf '%s' "$cli_submission" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status", ""))')"
    if [[ "$cli_status" != "Accepted" ]]; then
        if [[ -n "$cli_submission_id" ]]; then
            xcrun notarytool log "$cli_submission_id" --keychain-profile "$notary_profile" \
                "$release_root/notary-cli-log.json" || true
        fi
        echo "Apple did not accept the CLI archive (status: $cli_status)." >&2
        exit 1
    fi
fi

stage_path="$(mktemp -d "$release_root/.dmg-stage.XXXXXX")"
trap 'rm -rf "$stage_path"' EXIT
cp -R "$app_path" "$stage_path/"
ln -s /Applications "$stage_path/Applications"
mkdir -p "$stage_path/CLI"
cp "$cli_binary_path" "$stage_path/CLI/"
cp LICENSE THIRD_PARTY_NOTICES.md "$stage_path/"
cat > "$stage_path/Install.txt" <<EOF
SessionMonitor $version

Drag SessionMonitor.app to Applications and launch it from there.
Session history and settings are stored locally in ~/Library/Application Support/SessionMonitor.
Replacing the app when installing an update does not remove that local data.

The app and its WidgetKit extension are signed and notarized for direct macOS distribution.
The universal codex-monitor CLI is in the CLI folder; a standalone CLI archive is also attached to the GitHub release.
Third-party notices and the license are included beside the app.
EOF

hdiutil create -volname "SessionMonitor $version" -srcfolder "$stage_path" \
    -fs HFS+ -format UDZO -ov "$dmg_path" >/dev/null
codesign --force --timestamp --sign "$signing_identity" "$dmg_path"
rm -rf "$stage_path"
trap - EXIT

if (( ! skip_notarization )); then
    echo "Submitting DMG to Apple notarization..."
    dmg_submission="$(xcrun notarytool submit "$dmg_path" --keychain-profile "$notary_profile" \
        --wait --output-format json)"
    printf '%s\n' "$dmg_submission" > "$release_root/notary-dmg.json"
    dmg_submission_id="$(printf '%s' "$dmg_submission" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))')"
    dmg_status="$(printf '%s' "$dmg_submission" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status", ""))')"
    if [[ "$dmg_status" != "Accepted" ]]; then
        if [[ -n "$dmg_submission_id" ]]; then
            xcrun notarytool log "$dmg_submission_id" --keychain-profile "$notary_profile" \
                "$release_root/notary-dmg-log.json" || true
        fi
        echo "Apple did not accept the DMG submission (status: $dmg_status)." >&2
        exit 1
    fi
    xcrun stapler staple "$dmg_path"
    xcrun stapler validate "$dmg_path"
    spctl -a -vv -t open --context context:primary-signature "$dmg_path"
fi

(cd "$release_root" && shasum -a 256 "$(basename "$dmg_path")" > "$(basename "$checksum_path")")
(cd "$release_root" && shasum -a 256 "$(basename "$cli_archive_path")" > "$(basename "$cli_checksum_path")")
printf '%s\n' "$source_revision" > "$release_root/source-revision.txt"
echo "Created: $dmg_path"
echo "SHA-256: $(cut -d ' ' -f 1 "$checksum_path")"
echo "Created: $cli_archive_path"
echo "SHA-256: $(cut -d ' ' -f 1 "$cli_checksum_path")"
if (( skip_notarization )); then
    echo "NOT notarized: local validation only; this artifact is ineligible for GitHub publication." >&2
fi
