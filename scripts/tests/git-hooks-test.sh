#!/bin/sh
# Exercises the SessionMonitor Git hooks in a throwaway repository with a fake XcodeGen.
set -eu

source_root=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Keep the user's Git configuration (global hooks path, identity, signing) out of the test.
export HOME="$work/home"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
mkdir -p "$HOME"

repo="$work/repo"
log="$work/generate.log"
export GENERATE_LOG="$log"
: >"$log"

fake_bin="$work/bin"
mkdir -p "$fake_bin"
printf '#!/bin/sh\nexit 0\n' >"$fake_bin/xcodegen"
chmod 755 "$fake_bin/xcodegen"
PATH="$fake_bin:$PATH"
export PATH

# A PATH with the tools the hooks need and no XcodeGen, even on a machine that has one.
minimal_bin="$work/minimal"
mkdir -p "$minimal_bin"
for tool in git sh make grep cat readlink mkdir ln sed awk dirname basename env true false; do
    tool_path=$(command -v "$tool" || true)
    if [ -n "$tool_path" ]; then
        ln -s "$tool_path" "$minimal_bin/$tool"
    fi
done

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

generations() { grep -c . "$log" || true; }

expect_generations() {
    [ "$(generations)" -eq "$1" ]
}

expect_more_generations_than() {
    [ "$(generations)" -gt "$1" ]
}

git_in_repo() { git -C "$repo" "$@"; }

mkdir -p "$repo/Apps/MonitorMac/Sources" "$repo/scripts"
cp -R "$source_root/.githooks" "$repo/.githooks"
cp -R "$source_root/scripts/git-hooks" "$repo/scripts/git-hooks"
# The dollar signs are for make, not for this shell.
# shellcheck disable=SC2016
printf 'generate:\n\t@echo generated >>"$$GENERATE_LOG"\n' >"$repo/Makefile"
printf 'one\n' >"$repo/README.md"
printf 'struct Old {}\n' >"$repo/Apps/MonitorMac/Sources/Old.swift"

git -C "$repo" init -q -b main
git_in_repo config user.name Test
git_in_repo config user.email test@example.com
git_in_repo config commit.gpgsign false

git_in_repo add -A
git_in_repo commit -q -m initial
: >"$log"

# Installation: every hook and the helper are copied, and a second run changes nothing.
(cd "$repo" && sh scripts/git-hooks/install.sh >/dev/null)
for hook in pre-commit post-merge post-checkout post-rewrite; do
    check "$hook is installed as a copy" sh -c "test -x '$repo/.git/hooks/$hook' && ! test -L '$repo/.git/hooks/$hook'"
done
check "the helper is installed" test -x "$repo/.git/hooks/sessionmonitor-generate-project.sh"
check "reinstall is idempotent" sh -c "cd '$repo' && sh scripts/git-hooks/install.sh | grep -qv Installed"

# A changed hook is refreshed by installing again; a link from an earlier version is replaced by a copy.
printf '# changed\n' >>"$repo/.githooks/post-merge"
rm "$repo/.git/hooks/post-checkout"
ln -s "$repo/.githooks/post-checkout" "$repo/.git/hooks/post-checkout"
(cd "$repo" && sh scripts/git-hooks/install.sh >/dev/null)
check "a changed hook is refreshed" cmp -s "$repo/.githooks/post-merge" "$repo/.git/hooks/post-merge"
check "an old link is replaced by a copy" sh -c "! test -L '$repo/.git/hooks/post-checkout' && cmp -s '$repo/.githooks/post-checkout' '$repo/.git/hooks/post-checkout'"
git_in_repo checkout -q -- .githooks/post-merge
(cd "$repo" && sh scripts/git-hooks/install.sh >/dev/null)

# A foreign hook is left alone, the others are still installed.
conflict="$work/conflict"
cp -R "$repo" "$conflict"
rm "$conflict/.git/hooks/post-merge"
printf '#!/bin/sh\necho mine\n' >"$conflict/.git/hooks/post-merge"
check "a foreign hook is not overwritten" \
    sh -c "cd '$conflict' && ! sh scripts/git-hooks/install.sh >/dev/null 2>&1 && grep -q mine .git/hooks/post-merge && cmp -s .githooks/post-rewrite .git/hooks/post-rewrite"

# Branch switch: relevant files differ between branches -> regenerate; unrelated ones do not.
git_in_repo checkout -q -b feature
printf 'struct New {}\n' >"$repo/Apps/MonitorMac/Sources/New.swift"
git_in_repo add -A
git_in_repo commit -q -m "add app source"
check "pre-commit regenerates for staged app sources" expect_generations 1

git_in_repo checkout -q main
check "checking out a branch without the new source regenerates" expect_generations 2
git_in_repo checkout -q feature
check "checking out the branch with the new source regenerates" expect_generations 3

git_in_repo checkout -q main
printf 'two\n' >"$repo/README.md"
git_in_repo add -A
git_in_repo commit -q -m "docs only"
git_in_repo checkout -q -b docs
check "an unrelated branch switch does not regenerate" expect_generations 4
git_in_repo checkout -q main
before=$(generations)
check "a docs-only commit does not regenerate" expect_generations "$before"

# File checkout (flag 0) never regenerates.
git_in_repo checkout -q -- README.md
check "a file checkout does not regenerate" expect_generations "$before"

# Merge and fast-forward pull bring the new source in.
git_in_repo merge -q --no-edit feature
check "merge regenerates" expect_more_generations_than "$before"

# Rebase onto a branch with app changes.
git_in_repo checkout -q -b topic docs
printf 'topic\n' >"$repo/topic.txt"
git_in_repo add -A
git_in_repo commit -q -m topic
before=$(generations)
git_in_repo rebase -q main
check "rebase onto app changes regenerates" expect_more_generations_than "$before"

# A branch without any of these files (older than the hooks) still regenerates when it is left or entered.
git_in_repo checkout -q main
git_in_repo checkout -q -b legacy
git_in_repo rm -rq .githooks scripts Apps
git_in_repo commit -q -m "legacy branch without hooks and app sources"
git_in_repo checkout -q main
before=$(generations)
git_in_repo checkout -q legacy
check "entering a branch without the hook files regenerates" expect_more_generations_than "$before"
before=$(generations)
git_in_repo checkout -q main
check "leaving a branch without the hook files regenerates" expect_more_generations_than "$before"

# Without XcodeGen: post hooks never fail Git, pre-commit stops the commit with a hint.
git_in_repo checkout -q feature
git_in_repo checkout -q -b nox
printf 'struct Extra {}\n' >"$repo/Apps/MonitorMac/Sources/Extra.swift"
git_in_repo add -A
check "pre-commit fails without XcodeGen" \
    sh -c "! PATH='$minimal_bin' git -C '$repo' commit -q -m extra 2>'$work/pre-commit.err'"
check "pre-commit explains what to do" grep -q 'XcodeGen is required' "$work/pre-commit.err"
git_in_repo commit -q -m extra

check "post-checkout does not fail without XcodeGen" \
    sh -c "PATH='$minimal_bin' git -C '$repo' checkout -q main 2>'$work/post.err'"
check "post-checkout still tells the user to regenerate" grep -q 'XcodeGen is required' "$work/post.err"
check "the checkout itself took effect" test "$(git_in_repo rev-parse --abbrev-ref HEAD)" = main

# A damaged installation (helper deleted) never makes Git itself fail.
rm "$repo/.git/hooks/sessionmonitor-generate-project.sh"
git_in_repo checkout -q feature 2>"$work/damaged.err" || true
check "a missing helper does not fail a checkout" sh -c "git -C '$repo' checkout -q main 2>/dev/null"
check "a missing helper is reported" grep -q 'make install-hooks' "$work/damaged.err"

if [ "$failures" -ne 0 ]; then
    printf '%s Git hook checks failed.\n' "$failures" >&2
    exit 1
fi
printf 'Git hooks test passed.\n'
