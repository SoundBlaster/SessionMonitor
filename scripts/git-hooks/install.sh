#!/bin/sh
set -eu

repository_root=$(git rev-parse --show-toplevel)
local_hooks_path=$(git -C "$repository_root" config --local --get core.hooksPath || true)
global_hooks_path=$(git -C "$repository_root" config --global --get core.hooksPath || true)

if [ -z "$local_hooks_path" ] && [ -n "$global_hooks_path" ]; then
    printf '%s\n' 'A global core.hooksPath is configured. Refusing to install a repository hook into a shared hooks directory; set a repository-local core.hooksPath first.' >&2
    exit 1
fi

hooks_directory=$(git -C "$repository_root" rev-parse --path-format=absolute --git-path hooks)
case "$hooks_directory" in
    "$repository_root"/*) ;;
    *)
        printf '%s\n' 'The configured Git hooks directory is outside this repository. Refusing to install into a shared directory.' >&2
        exit 1
        ;;
esac

hook_source="$repository_root/.githooks/pre-commit"
hook_destination="$hooks_directory/pre-commit"
mkdir -p "$hooks_directory"

if [ -L "$hook_destination" ] && [ "$(readlink "$hook_destination")" = "$hook_source" ]; then
    printf '%s\n' 'SessionMonitor pre-commit hook is already installed.'
    exit 0
fi

if [ -e "$hook_destination" ] || [ -L "$hook_destination" ]; then
    printf '%s\n' "An existing pre-commit hook was found at $hook_destination; leaving it unchanged. Integrate .githooks/pre-commit manually." >&2
    exit 1
fi

ln -s "$hook_source" "$hook_destination"
printf '%s\n' "Installed SessionMonitor pre-commit hook at $hook_destination."
