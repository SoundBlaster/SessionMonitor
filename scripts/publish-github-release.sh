#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

release_root="${RELEASE_ROOT:-.build/release-github}"
notary_profile="${NOTARY_PROFILE:-}"
version_file="Apps/MonitorMac/project.yml"
version="${RELEASE_VERSION:-$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([^"[:space:]]+)"?[[:space:]]*$/\1/p' "$version_file" | head -n 1)}"
tag="v$version"
dmg_name="SessionMonitor-$version.dmg"
checksum_name="$dmg_name.sha256"
dmg_path="$release_root/$dmg_name"
checksum_path="$release_root/$checksum_name"
cli_archive_name="codex-monitor-$version-macos-universal.zip"
cli_checksum_name="$cli_archive_name.sha256"
cli_archive_path="$release_root/$cli_archive_name"
cli_checksum_path="$release_root/$cli_checksum_name"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]] || {
    echo "Invalid release version: '$version'" >&2
    exit 2
}
[[ -f "$dmg_path" && -f "$checksum_path" && -f "$cli_archive_path" && -f "$cli_checksum_path" \
    && -f "$release_root/notary-app.json" && -f "$release_root/notary-cli.json" \
    && -f "$release_root/notary-dmg.json" && -f "$release_root/source-revision.txt" ]] || {
    echo "Notarized app DMG, universal CLI archive, or checksum is missing. Run make release-github first." >&2
    exit 2
}
command -v gh >/dev/null 2>&1 || { echo "GitHub CLI (gh) is required." >&2; exit 2; }
command -v xcrun >/dev/null 2>&1 || { echo "Xcode command line tools are required." >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "Python 3 is required." >&2; exit 2; }
[[ -n "$notary_profile" ]] || { echo "Set NOTARY_PROFILE to revalidate Apple's notarization records." >&2; exit 2; }
gh auth status >/dev/null 2>&1 || { echo "Authenticate gh with access to this repository." >&2; exit 2; }

for receipt in notary-app.json notary-cli.json notary-dmg.json; do
    submission_id="$(python3 - "$release_root/$receipt" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as source:
    data = json.load(source)
if data.get("status") != "Accepted" or not data.get("id"):
    raise SystemExit("Stored Apple notarization result is missing or not accepted")
print(data["id"])
PY
)"
    submission_info="$(xcrun notarytool info "$submission_id" --keychain-profile "$notary_profile" --output-format json)"
    submission_status="$(printf '%s' "$submission_info" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status", ""))')"
    [[ "$submission_status" == "Accepted" ]] || {
        echo "Apple notarization status is not Accepted for $receipt ($submission_status)." >&2
        exit 2
    }
done

[[ -z "$(git status --porcelain)" ]] || {
    echo "Refusing publication from a dirty working tree." >&2
    exit 2
}
[[ "$(git branch --show-current)" == "main" ]] || {
    echo "Refusing publication: checkout main after the release commit is merged." >&2
    exit 2
}
git fetch --quiet origin
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || {
    echo "Refusing publication: local main is not the current origin/main." >&2
    exit 2
}
artifact_revision="$(cat "$release_root/source-revision.txt")"
[[ "$artifact_revision" == "$(git rev-parse HEAD)" ]] || {
    echo "Refusing publication: artifacts were prepared from $artifact_revision, not current main $(git rev-parse HEAD)." >&2
    echo "Rebuild the release artifacts from this exact main commit." >&2
    exit 2
}

if git show-ref --verify --quiet "refs/tags/$tag"; then
    echo "Refusing publication: local tag $tag already exists." >&2
    exit 2
fi
remote_tags="$(git ls-remote --tags origin "refs/tags/$tag" "refs/tags/$tag^{}")"
[[ -z "$remote_tags" ]] || {
    echo "Refusing publication: remote tag $tag already exists." >&2
    exit 2
}
if gh release view "$tag" >/dev/null 2>&1; then
    echo "Refusing publication: GitHub release $tag already exists." >&2
    exit 2
fi

(cd "$release_root" && shasum -a 256 -c "$checksum_name")
(cd "$release_root" && shasum -a 256 -c "$cli_checksum_name")
xcrun stapler validate "$dmg_path" >/dev/null
spctl -a -vv -t open --context context:primary-signature "$dmg_path" >/dev/null

temporary_download="$(mktemp -d "${TMPDIR:-/tmp}/sessionmonitor-release.XXXXXX")"
cleanup() { rm -rf "$temporary_download"; }
trap cleanup EXIT

if [[ "${GITHUB_RELEASE_CONFIRM:-NO}" != "YES" ]]; then
    if [[ ! -t 0 ]]; then
        echo "Publication not confirmed in a non-interactive shell. Set GITHUB_RELEASE_CONFIRM=YES to confirm." >&2
        exit 2
    fi
    printf 'Publish %s with %s to GitHub? [y/N] ' "$tag" "$dmg_path"
    read -r answer
    [[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "Cancelled."; exit 1; }
fi

gh release create "$tag" "$dmg_path" "$checksum_path" "$cli_archive_path" "$cli_checksum_path" \
    --title "SessionMonitor $version" --generate-notes
gh release download "$tag" --pattern "$dmg_name" --dir "$temporary_download" >/dev/null
gh release download "$tag" --pattern "$cli_archive_name" --dir "$temporary_download" >/dev/null
published_dmg_sha="$(shasum -a 256 "$temporary_download/$dmg_name" | cut -d ' ' -f 1)"
local_dmg_sha="$(shasum -a 256 "$dmg_path" | cut -d ' ' -f 1)"
published_cli_sha="$(shasum -a 256 "$temporary_download/$cli_archive_name" | cut -d ' ' -f 1)"
local_cli_sha="$(shasum -a 256 "$cli_archive_path" | cut -d ' ' -f 1)"
[[ "$published_dmg_sha" == "$local_dmg_sha" && "$published_cli_sha" == "$local_cli_sha" ]] || {
    echo "A published asset checksum differs from its validated local artifact." >&2
    exit 1
}
echo "Published $tag; downloaded DMG and CLI checksums match."
