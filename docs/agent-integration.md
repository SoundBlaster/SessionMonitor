# Agent integration

[← SessionMonitor](../README.md) · [CLI guide](cli.md)

## Read a compact status

`agent status` reports session usage and idle time, recent requests/input/waits/compactions,
session and global alerts, and observed quota windows. It excludes prompts, tool output, and
file paths. It only reads the index unless `--evaluate` is supplied; evaluation does not consume
the app’s pending notifications.

```sh
codex-monitor agent status
codex-monitor agent status --session SESSION_ID --json
codex-monitor agent status --evaluate --fail-on warning
```

The default status window is 24 hours. `--fail-on warning` returns exit code 2 when a qualifying
alert is present. Freshness is reported in `index.ageSeconds`; use app/CLI Watch for live data.

## Add alerts to an agent’s context

`agent hook` accepts hook JSON on stdin (`session_id`, `transcript_path`, `hook_event_name`).
When a qualifying alert exists, it emits `hookSpecificOutput` with `hookEventName` and
`additionalContext`; otherwise it stays silent. Context is limited to 2,000 characters.

For each invocation, it incrementally imports its transcript and evaluates signals. If another
Watch owns the database, it skips that import and uses the index. It resolves the caller’s
session by ID, then by transcript; it never substitutes an unrelated “latest session”. Errors
go to stderr and the adapter exits 0 so monitoring does not block the agent.

### Codex

Add to `~/.codex/hooks.json` (or use the hooks table in your Codex configuration):

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "codex-monitor agent hook", "timeout": 10 } ] }
    ]
  }
}
```

Codex hook availability depends on the installed client version. If hooks require a feature
flag in your version, enable `hooks` under `[features]` in `~/.codex/config.toml` (older versions
called it `codex_hooks`). The supplied session ID and transcript should refer to the Codex
rollout indexed by SessionMonitor.

### Claude Code

The same hook configuration can be placed in `~/.claude/settings.json` or the project’s
`.claude/settings.json`. SessionMonitor does not index Claude Code sessions: in that case the
adapter only reports global Codex quota, Watch, and diagnostic alerts and explicitly says
that it did not find its own session. This is useful when Claude Code coordinates Codex work.

`UserPromptSubmit` runs before the model starts a turn. `PostToolUse` can provide updates during
long runs, at the cost of more hook invocations. Avoid `Stop`: in Claude Code, additional context
there can continue the conversation and cause a loop. Codex `notify` runs after a turn but does
not return its stdout to the agent, so it is not a substitute for this hook.

### Inspect the output

```sh
printf '%s\n' '{"session_id":"SESSION_ID","transcript_path":"/path/to/rollout.jsonl","hook_event_name":"UserPromptSubmit"}' \
  | codex-monitor agent hook --always
```

Options: `--always` emits status even without alerts; `--min-severity info|warning|error` sets the
threshold (default warning); `--no-import` leaves the transcript untouched; `--lookback-hours`
sets the session-usage window (default 6). Hook configuration belongs to your local client,
not this repository. Review the installed client’s hook support before enabling it.
