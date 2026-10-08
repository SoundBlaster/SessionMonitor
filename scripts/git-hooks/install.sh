#!/bin/sh
# Copies the SessionMonitor hooks into the repository's hooks directory. They are copies, not links into
# the working tree, so they keep working on branches that do not contain these files. Run it again
# (make init does) after the hooks change.
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

mkdir -p "$hooks_directory"

marker='# SessionMonitor Git hook'

# Installs a copy unless an identical one is there. Returns 1 for a hook that is not ours.
install_copy() {
    source=$1
    destination=$2
    label=$3

    if [ -f "$destination" ] && [ ! -L "$destination" ] && cmp -s "$source" "$destination"; then
        printf '%s\n' "SessionMonitor $label is up to date."
        return 0
    fi

    if [ -L "$destination" ]; then
        # Earlier versions linked into the working tree; only those links are ours to replace.
        if [ "$(readlink "$destination")" != "$source" ]; then
            return 1
        fi
        rm "$destination"
    elif [ -e "$destination" ]; then
        # A regular file is ours only when it carries the marker (an older copy of this hook).
        if ! grep -q "$marker" "$destination" && [ "$label" != helper ]; then
            return 1
        fi
    fi

    cp "$source" "$destination"
    chmod 755 "$destination"
    printf '%s\n' "Installed SessionMonitor $label at $destination."
}

status=0

helper_source="$repository_root/scripts/git-hooks/generate-project.sh"
helper_destination="$hooks_directory/sessionmonitor-generate-project.sh"
install_copy "$helper_source" "$helper_destination" helper || {
    printf '%s\n' "An existing file was found at $helper_destination; leaving it unchanged." >&2
    status=1
}

for hook in pre-commit post-merge post-checkout post-rewrite; do
    hook_source="$repository_root/.githooks/$hook"
    hook_destination="$hooks_directory/$hook"
    install_copy "$hook_source" "$hook_destination" "$hook hook" || {
        printf '%s\n' "An existing $hook hook was found at $hook_destination; leaving it unchanged. Integrate .githooks/$hook manually." >&2
        status=1
    }
done

exit "$status"
