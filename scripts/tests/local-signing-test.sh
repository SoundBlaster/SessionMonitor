#!/bin/sh
# Checks scripts/local-signing.sh in a throwaway directory.
set -eu

source_root=$(git rev-parse --show-toplevel)
script="$source_root/scripts/local-signing.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
file="$work/Local.xcconfig"
passed=0

check() {
    if "$@"; then
        passed=$((passed + 1))
        printf 'ok   %s\n' "$description"
    else
        printf 'FAIL %s\n' "$description" >&2
        exit 1
    fi
}

contains() { grep -Fq -- "$1" "$2"; }
lacks() { ! grep -Fq -- "$1" "$2"; }
is_empty() { [ ! -s "$1" ]; }
rejects() { ! sh "$script" "$@" 2>/dev/null; }

description='ensure creates the ad-hoc default when the file is missing'
sh "$script" ensure "$file"
check contains 'CODE_SIGN_IDENTITY = -' "$file"

description='the template carries the commented team lines and no active team'
check contains '// DEVELOPMENT_TEAM = YOUR_TEAM_ID' "$file"
check lacks 'DEVELOPMENT_TEAM = TEAMID' "$file"

description='the ad-hoc identity comes first, so an uncommented override below it wins'
first=$(grep -n '^CODE_SIGN_IDENTITY = -' "$file" | cut -d : -f 1)
override=$(grep -n '^// CODE_SIGN_IDENTITY = Apple Development' "$file" | cut -d : -f 1)
check test "$first" -lt "$override"

description='ensure never rewrites an existing file'
printf '%s\n' 'DEVELOPMENT_TEAM = ABCDE12345' 'CODE_SIGN_IDENTITY = Apple Development' >"$file"
sh "$script" ensure "$file"
check contains 'ABCDE12345' "$file"
check lacks 'ad-hoc' "$file"

description='no hint once a team is set'
sh "$script" hint "$file" >"$work/out"
check is_empty "$work/out"

description='hint names the file and the fix when the team is only commented out'
sh "$script" ensure "$work/Other.xcconfig"
sh "$script" hint "$work/Other.xcconfig" >"$work/out"
check contains 'sets no DEVELOPMENT_TEAM' "$work/out"
check contains 'lost on every make generate' "$work/out"

description='an empty DEVELOPMENT_TEAM counts as not set'
printf '%s\n' 'DEVELOPMENT_TEAM =' >"$work/Empty.xcconfig"
sh "$script" hint "$work/Empty.xcconfig" >"$work/out"
check contains 'sets no DEVELOPMENT_TEAM' "$work/out"

description='a missing file gets the hint too'
sh "$script" hint "$work/Missing.xcconfig" >"$work/out"
check contains 'sets no DEVELOPMENT_TEAM' "$work/out"

description='bad usage fails'
check rejects frobnicate "$file"

printf 'Local signing test passed (%s checks).\n' "$passed"
