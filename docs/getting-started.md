# Getting started

[← SessionMonitor](../README.md)

## Install the macOS app

1. Open [GitHub Releases](https://github.com/SoundBlaster/SessionMonitor/releases/latest).
2. Download the DMG, open it, and drag **SessionMonitor.app** to **Applications**.
3. Launch the app from Applications. Release builds use Developer ID signing and Apple notarization.

The app requires macOS 15 or later. The release includes Apple silicon and Intel support.
To update, quit SessionMonitor and replace the app with the newer release. Keep your existing
session folders and index; you do not need to delete them. Automatic app updates are not configured.

## Import your sessions

Use **Import Folder…** in the main window and choose `~/.codex/sessions`. In the folder picker,
press **Shift–Command–G** to enter the path. Selecting the parent `sessions` folder includes all
years; selecting `sessions/2026`, for example, includes only that subtree.

Codex can continue an old session in the file where it originally started. Importing only the
current month can therefore miss recent activity written to an older file. Use the full sessions
folder for ongoing monitoring. Archived logs in `~/.codex/archived_sessions` can be imported separately.

The app displays file and byte progress during a large import. **Stop** cancels further work;
completed files remain saved. **Update** reads new or changed files from the last selected folder.
It does not download sessions from a server.

Choose **All Time**, **Today**, **Last 7 Days**, or **Last 30 Days** in the report-scope popover.
Today uses your local calendar day by default. Activity is grouped by request time, so a session
that started weeks ago still contributes on the days when it was active.

## Keep it current

Open the SessionMonitor menu bar panel, choose **Watch Folder…**, and select the sessions folder.
Allow macOS notifications if you want alerts. Watch imports changes and evaluates supported
signals; it must be started explicitly after relaunching the app.

A manual Import, Update, or Retry stops this app’s Watch first. Watch remains stopped afterwards.
**Refresh** in the menu bar only rereads the index; it does not import files.
See [Watching & troubleshooting](watching.md) for database ownership and recovery.

## Add a widget

Launch the installed, signed app and complete an import. Then open the macOS widget gallery
and look for SessionMonitor. Widgets read a shared snapshot written by the app; they do not
import logs themselves and have their own period settings.

If a widget says there is no shared snapshot, open the installed app and update its data.
For a locally built app, check App Group signing for both the app and widget extension;
an unsigned or differently provisioned development build is not equivalent to the distributed app.

## Install the CLI

Download the standalone CLI ZIP from the same release page, extract it, and install the
`codex-monitor` executable into a directory on your `PATH`, for example:

```sh
mkdir -p ~/.local/bin
install -m 755 /path/to/extracted/codex-monitor ~/.local/bin/codex-monitor
codex-monitor --help
codex-monitor import ~/.codex/sessions
codex-monitor report
```

Ensure `~/.local/bin` is on your shell’s `PATH`. The macOS DMG also includes the CLI.
For compilation instructions, use the [development guide](development.md).

## Where data lives

The default shared app/CLI index is:

```text
~/Library/Application Support/SessionMonitor/usage.sqlite
```

The CLI accepts `--database PATH`. `SESSIONMONITOR_DATABASE` selects a separate database for
both interfaces. Linux uses `$XDG_DATA_HOME/SessionMonitor/usage.sqlite`, or
`~/.local/share/SessionMonitor/usage.sqlite` when that variable is unset.

Matching app and CLI totals require the same database, time interval, and account scope.
Sidebar search only narrows the visible list. [Data and coverage](data-and-coverage.md) explains
what is counted and why a result may be unknown.
