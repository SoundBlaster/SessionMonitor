# App guide

[← SessionMonitor](../README.md) · [First run](getting-started.md)

## Accounts, periods, and sessions

The report-scope popover selects **All accounts**, an assigned profile, or **Unknown/Mixed**,
plus a calendar period and timezone. The selection is shared by Session Explorer and the menu
bar and survives relaunches. Creating and mapping profiles is a [CLI operation](cli.md#account-profiles).
Sources with unconfirmed attribution stay Unknown/Mixed; mixed roots are excluded from a
profile’s report, with a warning about incomplete coverage. All accounts keeps quota windows
grouped by profile rather than summing them.

Periods are All Time, Today, Last 7 Days, and Last 30 Days. Calendar boundaries follow the
selected timezone, including daylight saving transitions. Search narrows the list without
changing report totals. The session list can be sorted by first/last request, cache hit, request
count, or input + output tokens, in either direction. Unknown sort values remain last. First/last
request dates describe the session’s imported history, not just the selected period.

## Cache Hit Rate

The sidebar chart follows the report’s account and period. Today uses hourly buckets from
midnight; Last 7/30 Days use daily buckets. Empty intervals keep their positions. For All Time,
the chart uses its configured cache-widget period. A long session contributes to each bucket
in which its requests were observed, rather than only its start date.

Hover an interval for its weighted average, typical range, and outliers. Single-request sessions
are excluded from the distribution: a cold start would otherwise distort its range. They still
contribute to the period’s token totals and overall cache hit rate. An interval containing only
single-request sessions has no distribution bar but can still narrow the report.

Click an interval to narrow the session list, totals, and inspector to its intersection with the
report period. Click the date chip to clear that filter. This temporary selection resets when
you change account, period, or timezone; the menu bar continues to show the overall selected period.

The expand button opens a larger chart and focuses that window on subsequent clicks:

- Click to pin an interval; hover does not replace that selection.
- Drag or scroll to pan; pinch to zoom.
- Use the compact controls for keyboard-accessible zoom, reset, and interval navigation.
- VoiceOver exposes a **Select bucket** action on each interval.

The vertical scale is based on the full report and stays fixed while panning or zooming.
The expanded chart follows the opening Session Explorer’s data and scope.

## Context anatomy and request timeline

Context anatomy plots input size across requests. Background colors represent a share of the
reported usable context window; when that window is unavailable, the display uses the session
peak and identifies the inference. The token strip separates new input, output, and known
reasoning; markers show compactions, human turns, and other observed events.

Hover or use the arrow keys to inspect a request snapshot: context size, change from the
previous request, cached/new input, output, time, model, and available signals. The snapshot
is an overlay and does not move the chart. Logs describe token volumes and events, not the
contents of the context.

Triangle markers highlight representative insights. Expand **Context insights** for evidence
and limitations; all signals remain available even when dense charts show fewer markers.
A fall in input does not prove a reset, and a pause does not prove cache expiry.
See [Context insights](context-insights.md) for the detailed rules.

The request timeline shows usage and events over time. Fit to data, Last events, Full query,
and a custom interval control the visible range. Dense views aggregate the presentation;
the evidence list retains the underlying observations.

## Findings and alerts

**Findings** in the toolbar opens diagnostic findings and alerts for the selected account and
period. Filter findings by kind or alerts by active/resolved status. Each entry includes
confidence or coverage, evidence, limitations, and links to affected sessions in the current report.
The underlying results are also available through `doctor --json` and `alerts --status all --json`.

## Menu bar and widgets

The menu bar summary shows the selected scope, input/output, known cached input, cache coverage,
and the time of the latest committed index change. Unknown values remain unknown. The index time
does not prove that every source log is fresh.

Opening the panel reads the index; it does not start an import or Watch. Windows with the same
query share an upstream snapshot stream. After an observation error, the last result stays visible
with a warning; reopening retries the subscription.

**Open Window** opens Session Explorer. **Settings…** can hide or restore the menu bar icon.
Closing a window or hiding the icon does not stop Watch. Quitting waits for Watch cleanup;
relaunching does not automatically resume it. Widgets have independent periods and use the
app’s shared snapshot. See [widget setup](getting-started.md#add-a-widget).
