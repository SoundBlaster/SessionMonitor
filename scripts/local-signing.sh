#!/bin/sh
# Local signing overrides for the generated Xcode project.
#   local-signing.sh ensure FILE  create FILE with the ad-hoc default when it is missing
#   local-signing.sh hint FILE    say what to do when FILE sets no DEVELOPMENT_TEAM
# FILE is Git-ignored and never rewritten once it exists. Signing set in the Xcode UI belongs to the
# generated project and is lost by every `make generate` (also after a pull), so it has to live here.
set -eu

mode=${1:-}
file=${2:-}
if [ -z "$mode" ] || [ -z "$file" ]; then
    printf 'usage: %s ensure|hint FILE\n' "$0" >&2
    exit 2
fi

case "$mode" in
ensure)
    if [ ! -f "$file" ]; then
        cat >"$file" <<'TEMPLATE'
// Local signing overrides (not committed). Unlike settings made in the Xcode UI, this file survives
// `make generate` and the Git hooks that regenerate the project after a pull.
CODE_SIGN_IDENTITY = -
// To sign with your team, uncomment these lines; later lines override the ad-hoc identity above.
// DEVELOPMENT_TEAM = YOUR_TEAM_ID
// CODE_SIGN_IDENTITY = Apple Development
TEMPLATE
    fi
    ;;
hint)
    if [ -f "$file" ] && grep -Eq '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[^[:space:]/]' "$file"; then
        exit 0
    fi
    printf '%s\n' "Signing: $file sets no DEVELOPMENT_TEAM, so the app builds with ad-hoc signing." \
        'Signing chosen in the Xcode UI belongs to the generated project and is lost on every make generate' \
        '(also after git pull). Put DEVELOPMENT_TEAM and CODE_SIGN_IDENTITY into that file to keep them.'
    ;;
*)
    printf 'unknown mode: %s\n' "$mode" >&2
    exit 2
    ;;
esac
