#!/usr/bin/env python3
"""Read-only Codex rollout audit. Standard library only; never sends data online.

Canonical token_usage_record entries are deduplicated by response_id. Legacy
token_count snapshots are differenced, not summed, and mirrored records skipped.
Copied fork history is excluded using thread ownership and creation timestamps.
Reports contain metrics and local source pointers, never conversation bodies.
"""
import argparse
import collections as C
import csv
import datetime as D
import hashlib
import json
from pathlib import Path
import re
import sqlite3
from zoneinfo import ZoneInfo

UTC = D.timezone.utc
KEYS = ['input_tokens', 'cached_input_tokens', 'cache_write_input_tokens',
        'output_tokens', 'reasoning_output_tokens', 'total_tokens']

def stamp(s):
    return D.datetime.fromisoformat(s.replace('Z', '+00:00')).astimezone(UTC)

def usage(u):
    return {k: int(u.get(k, 0) or 0) for k in KEYS}

def signature(u):
    return tuple(u.get(k, 0) for k in KEYS)

def legacy_delta(total, previous, last):
    if previous is not None and signature(total) == signature(previous):
        return None, 'duplicate'
    if previous is None:
        return usage(last or total), 'initial'
    delta = {k: total.get(k, 0) - previous.get(k, 0) for k in KEYS}
    if any(v < 0 for v in delta.values()):
        return usage(last or total), 'reset'
    return delta, 'delta'

def rows(db, query, args=()):
    if not db.exists():
        return []
    con = sqlite3.connect('file:' + str(db) + '?mode=ro', uri=True)
    con.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in con.execute(query, args)]
    finally:
        con.close()

def aggregate(rs):
    out = {'requests': len(rs)}
    for k in KEYS:
        out[k] = sum(r[k] for r in rs)
    out['uncached_input_tokens'] = out['input_tokens'] - out['cached_input_tokens']
    out['cache_hit_pct'] = round(100 * out['cached_input_tokens'] / max(1, out['input_tokens']), 3)
    out['zero_cache_requests'] = sum(r['cached_input_tokens'] == 0 for r in rs)
    out['large_low_cache_requests'] = sum(r['input_tokens'] >= 32000 and r['cached_input_tokens'] < .1 * r['input_tokens'] for r in rs)
    return out

def group(rs, key):
    groups = C.defaultdict(list)
    for r in rs:
        groups[r[key]].append(r)
    return {k: aggregate(v) for k, v in sorted(groups.items())}

def write_csv(path, rs):
    if not rs:
        path.write_text('')
        return
    fields = list(dict.fromkeys(k for r in rs for k in r))
    with path.open('w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rs)

def tool_details(p):
    name = p.get('name', '')
    raw = p.get('arguments', p.get('input', ''))
    raw = raw if isinstance(raw, str) else json.dumps(raw)
    names = [name]
    # This is lexical evidence of calls inside code-mode, not runtime proof.
    if name in ['functions.exec', 'exec']:
        names += re.findall(r'\btools\.([A-Za-z0-9_]+)\s*\(', raw)
    allnames = ' '.join(names)
    kind = 'other'
    if re.search(r'(clock[._]|clock__)sleep|\bsleep$', allnames):
        kind = 'clock_sleep'
    elif re.search(r'wait_agent|wait_threads|wait_thread|wait_for', allnames):
        kind = 'agent_wait'
    elif re.search(r'write_stdin', allnames):
        kind = 'process_poll'
    elif name in ['functions.wait', 'wait']:
        kind = 'code_wait'
    elif re.search(r'read_thread|list_threads|get_handoff_status', allnames):
        kind = 'thread_read'
    elif re.search(r'exec_command|shell_command|\bshell\b', allnames):
        kind = 'shell'
    durations = [int(x) for x in re.findall(r'["\']?duration_ms["\']?\s*:\s*(\d+)', raw)]
    # Exact-call repetition detection uses a digest; no command content exported.
    digest = hashlib.sha256((name + '\n' + raw).encode()).hexdigest()[:16]
    reads_context = bool(re.search(r'read_thread|read_mcp_resource', allnames) or
                         (kind == 'shell' and re.search(r'AGENTS\.md|SKILL\.md|MEMORY\.md|memory_summary|\.codex/sessions', raw)))
    return kind, names, digest, durations, reads_context

def audit(args):
    home, out = Path(args.codex_home).expanduser(), Path(args.out).expanduser()
    start, end = stamp(args.since), stamp(args.until)
    tz = ZoneInfo(args.timezone)
    out.mkdir(parents=True, exist_ok=True)
    state_rows = rows(home / 'state_5.sqlite', 'select id,rollout_path,name,title,cwd,source,model,reasoning_effort,updated_at from threads')
    state = {r['id']: r for r in state_rows}
    goals = rows(home / 'goals_1.sqlite', 'select thread_id,status,token_budget,tokens_used,time_used_seconds,created_at_ms,updated_at_ms from thread_goals')
    paths = set()
    all_count = 0
    for folder in ['sessions', 'archived_sessions']:
        for p in (home / folder).rglob('*.jsonl'):
            all_count += 1
            if args.all_files or p.stat().st_mtime >= start.timestamp():
                paths.add(p)
    for s in state_rows:
        if s['updated_at'] >= start.timestamp() and Path(s['rollout_path']).exists():
            paths.add(Path(s['rollout_path']))
    quality = C.Counter()
    quality['files_discovered'] = all_count
    quality['files_selected'] = len(paths)
    records, legacy, rates, tools, turns, goal_events, compacts, goal_prompts = [], [], [], [], [], [], [], []
    sessions = {}
    response_ids = set()
    legacy_seen = set()
    for path in sorted(paths):
        quality['bytes_scanned'] += path.stat().st_size
        meta, model, effort, turn_id = {}, 'unknown', 'unknown', ''
        previous, last_explicit, previous_request_ts = None, None, None
        after_kind, after_digest = '', ''
        calls = {}
        compact_pending = False
        seen_turns = set()
        native_turn = False
        for line_no, line in enumerate(path.open(), 1):
            try:
                x = json.loads(line)
                p = x.get('payload') or {}
                ts = stamp(x['timestamp'])
            except (ValueError, KeyError):
                quality['malformed_lines'] += 1
                continue
            typ, sub = x.get('type'), p.get('type')
            if typ == 'session_meta':
                meta = p
                sid = p.get('id', path.stem)
                created = stamp(p.get('timestamp', x['timestamp']))
                src = p.get('source', '')
                sessions[sid] = {'thread_id': sid, 'path': str(path), 'created': created.isoformat(),
                                 'title': state.get(sid, {}).get('name') or state.get(sid, {}).get('title', '')[:120], 'cwd': p.get('cwd', ''),
                                 'source': json.dumps(src, ensure_ascii=False) if isinstance(src, dict) else src,
                                 'cli_version': p.get('cli_version', ''), 'thread_source': str(p.get('thread_source', ''))}
                continue
            if not meta:
                quality['lines_without_metadata'] += 1
                continue
            if typ == 'turn_context':
                model = p.get('model', model)
                effort = p.get('effort', p.get('reasoning_effort', effort))
                turn_id = p.get('turn_id', turn_id)
            if typ == 'event_msg' and sub == 'task_started':
                turn_id = p.get('turn_id', turn_id)
                # Fork serialization rewrites outer timestamps, but preserves
                # started_at. Replayed turns must never become new usage.
                actual_start = p.get('started_at')
                if actual_start is not None:
                    native_turn = actual_start >= int(created.timestamp()) and not re.fullmatch(r'rollout-\d+', turn_id)
            in_window = start <= ts < end
            owned = ts >= created and native_turn
            if in_window and not native_turn and (typ == 'token_usage_record' or sub == 'token_count'):
                quality['replayed_usage_entries'] += 1
            if typ == 'token_usage_record':
                if p.get('thread_id') and p['thread_id'] != sid:
                    quality['inherited_explicit_records'] += int(in_window)
                    last_explicit = (ts, signature(usage(p.get('usage', {}))))
                    continue
                u = usage(p.get('usage', {}))
                last_explicit = (ts, signature(u))
                if not in_window or not owned:
                    quality['out_of_window_explicit_records'] += 1
                    continue
                rid = p.get('response_id') or (sid, p.get('turn_id'), x.get('ordinal'), x['timestamp'])
                if rid in response_ids:
                    quality['duplicate_response_ids'] += 1
                    continue
                response_ids.add(rid)
                tid = p.get('turn_id', turn_id)
                r = {'timestamp': ts.isoformat(), 'date': ts.astimezone(tz).date().isoformat(),
                     'thread_id': sid, 'turn_id': tid, 'model': model, 'effort': effort,
                     'cli_version': meta.get('cli_version', ''), 'source': 'token_usage_record',
                     'path': str(path), 'line': line_no, 'response_id': str(rid),
                     'after_tool': after_kind, 'after_digest': after_digest,
                     'after_compaction': compact_pending, 'first_in_turn': tid not in seen_turns,
                     'gap_seconds': round((ts - previous_request_ts).total_seconds(), 3) if previous_request_ts else None, **u}
                records.append(r)
                seen_turns.add(tid)
                previous_request_ts = ts
                compact_pending = False
                after_kind, after_digest = '', ''
                continue
            if typ == 'event_msg' and sub == 'token_count':
                if in_window and owned and p.get('rate_limits'):
                    rl = p['rate_limits']
                    for w in ['primary', 'secondary']:
                        q = rl.get(w)
                        if q:
                            rates.append({'timestamp': ts.isoformat(), 'thread_id': sid, 'limit_id': rl.get('limit_id'),
                                          'window': w, **q})
                info = p.get('info') or {}
                total = info.get('total_token_usage')
                if not total:
                    continue
                u, status = legacy_delta(total, previous, info.get('last_token_usage'))
                previous = total
                if not in_window or not owned:
                    continue
                quality['legacy_snapshot_' + status] += 1
                if u is None:
                    continue
                # The snapshot may be delayed by a long tool wait. Its matching
                # request record can be minutes/hours earlier, not just seconds.
                if last_explicit and signature(u) == last_explicit[1]:
                    quality['mirrored_token_count_skipped'] += 1
                    continue
                key = (x['timestamp'], signature(u), signature(total))
                if key in legacy_seen:
                    quality['duplicate_legacy_events'] += 1
                    continue
                legacy_seen.add(key)
                legacy.append({'timestamp': ts.isoformat(), 'date': ts.astimezone(tz).date().isoformat(),
                               'thread_id': sid, 'turn_id': turn_id, 'model': model, 'effort': effort,
                               'cli_version': meta.get('cli_version', ''), 'source': 'legacy_' + status,
                               'path': str(path), 'line': line_no, 'response_id': '',
                               'after_tool': after_kind, 'after_digest': after_digest,
                               'after_compaction': compact_pending, 'first_in_turn': turn_id not in seen_turns,
                               'gap_seconds': round((ts - previous_request_ts).total_seconds(), 3) if previous_request_ts else None, **u})
                seen_turns.add(turn_id)
                previous_request_ts = ts
                compact_pending = False
                after_kind, after_digest = '', ''
                continue
            if not in_window or not owned:
                continue
            if typ == 'compacted':
                compacts.append({'thread_id': sid, 'timestamp': ts.isoformat(), 'path': str(path), 'line': line_no})
                compact_pending = True
            if typ == 'event_msg':
                if sub in ['task_started', 'task_complete', 'turn_aborted']:
                    turns.append({'thread_id': sid, 'turn_id': p.get('turn_id', turn_id),
                                  'type': sub, 'timestamp': ts.isoformat(), 'path': str(path), 'line': line_no})
                if sub and 'goal' in sub:
                    g = p.get('goal') or {}
                    if p.get('threadId', sid) == sid:
                        goal_events.append({'thread_id': sid, 'type': sub, 'timestamp': ts.isoformat(),
                                            'status': g.get('status'), 'path': str(path), 'line': line_no})
            if typ == 'response_item' and sub == 'message' and p.get('role') in ['user', 'developer']:
                message = '\n'.join(c.get('text', '') for c in p.get('content', []))
                if re.match(r'\s*(?:<codex_internal_context source="goal">\s*)?Continue working toward the active thread goal', message):
                    goal_prompts.append({'thread_id': sid, 'turn_id': turn_id, 'timestamp': ts.isoformat(),
                                         'path': str(path), 'line': line_no})
            if typ == 'response_item' and sub in ['function_call', 'custom_tool_call']:
                kind, names, digest, durations, read_context = tool_details(p)
                call_id = p.get('call_id', '')
                calls[call_id] = (kind, digest)
                tools.append({'thread_id': sid, 'turn_id': turn_id, 'timestamp': ts.isoformat(), 'model': model,
                              'name': p.get('name'), 'nested_names': ','.join(names[1:]), 'kind': kind,
                              'digest': digest, 'requested_sleep_ms': sum(durations), 'context_read': read_context,
                              'path': str(path), 'line': line_no})
            if typ == 'response_item' and sub in ['function_call_output', 'custom_tool_call_output']:
                after_kind, after_digest = calls.get(p.get('call_id'), ('', ''))
    records.extend(legacy)
    records.sort(key=lambda r: r['timestamp'])
    active_ids = {r['thread_id'] for r in records}
    quality['explicit_requests'] = sum(r['source'] == 'token_usage_record' for r in records)
    quality['legacy_requests'] = len(legacy)
    quality['active_sessions'] = len(active_ids)
    quality['invalid_cache_counts'] = sum(r['cached_input_tokens'] > r['input_tokens'] for r in records)
    session_usage = group(records, 'thread_id')
    tool_groups = C.defaultdict(list)
    for t in tools:
        tool_groups[t['thread_id']].append(t)
    for sid, stats in session_usage.items():
        sessions[sid].update(stats)
        ts = tool_groups[sid]
        sessions[sid]['tool_calls'] = len(ts)
        for kind in ['clock_sleep', 'agent_wait', 'process_poll', 'code_wait', 'thread_read']:
            sessions[sid][kind] = sum(t['kind'] == kind for t in ts)
        sessions[sid]['compactions'] = sum(c['thread_id'] == sid for c in compacts)
        sessions[sid]['goal_events'] = sum(g['thread_id'] == sid for g in goal_events)
        sessions[sid]['context_reads'] = sum(t['context_read'] for t in ts)
        sessions[sid]['turns_started'] = sum(t['thread_id'] == sid and t['type'] == 'task_started' for t in turns)
    session_list = sorted((sessions[s] for s in active_ids), key=lambda r: r['input_tokens'], reverse=True)
    turn_usage = C.defaultdict(list)
    for r in records:
        turn_usage[(r['thread_id'], r['turn_id'])].append(r)
    turn_list = []
    for (sid, tid), rs in turn_usage.items():
        turn_list.append({'thread_id': sid, 'turn_id': tid, 'title': sessions[sid]['title'],
                          'first_request': rs[0]['timestamp'], 'last_request': rs[-1]['timestamp'],
                          'span_seconds': (stamp(rs[-1]['timestamp']) - stamp(rs[0]['timestamp'])).total_seconds(),
                          **aggregate(rs)})
    turn_list.sort(key=lambda r: r['input_tokens'], reverse=True)
    buckets = C.defaultdict(list)
    for r in records:
        slot = int(stamp(r['timestamp']).timestamp()) // 1800 * 1800
        buckets[(r['thread_id'], slot)].append(r)
    busy = [{'thread_id': sid, 'title': sessions[sid]['title'], 'start': D.datetime.fromtimestamp(slot, UTC).isoformat(),
             **aggregate(rs)} for (sid, slot), rs in buckets.items()]
    busy.sort(key=lambda r: r['input_tokens'], reverse=True)
    repeats = C.defaultdict(list)
    for t in tools:
        repeats[(t['thread_id'], t['digest'])].append(t)
    repeated = [{'thread_id': sid, 'digest': digest, 'kind': rs[0]['kind'], 'name': rs[0]['name'],
                 'calls': len(rs), 'first': rs[0]['timestamp'], 'last': rs[-1]['timestamp'],
                 'path': rs[0]['path'], 'line': rs[0]['line']} for (sid, digest), rs in repeats.items() if len(rs) >= 5]
    repeated.sort(key=lambda r: r['calls'], reverse=True)
    rate_unique = {tuple(sorted(r.items())): r for r in rates}
    rates = sorted(rate_unique.values(), key=lambda r: r['timestamp'])
    summary = {'window': {'since': start.isoformat(), 'until_exclusive': end.isoformat(), 'timezone': args.timezone},
               'quality': dict(quality), 'totals': aggregate(records), 'daily': group(records, 'date'),
               'models': group(records, 'model'), 'efforts': group(records, 'effort'),
               'versions_at_session_creation': group(records, 'cli_version'),
               'by_preceding_tool': group(records, 'after_tool'),
               'first_in_turn': aggregate([r for r in records if r['first_in_turn']]),
               'within_turn': aggregate([r for r in records if not r['first_in_turn']]),
               'after_compaction': aggregate([r for r in records if r['after_compaction']]),
               'tools': dict(C.Counter(t['kind'] for t in tools)), 'compactions': len(compacts),
               'turn_events': dict(C.Counter(t['type'] for t in turns)),
               'goal_events': goal_events, 'goal_continuations': goal_prompts, 'goal_db': goals,
               'recent_goal_db': [g for g in goals if start.timestamp() * 1000 <= g['updated_at_ms'] < end.timestamp() * 1000],
               'top_sessions': session_list[:20], 'top_turns': turn_list[:20], 'top_half_hours': busy[:20],
               'repeated_calls': repeated[:30]}
    (out / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    for name, data in [('requests', records), ('sessions', session_list), ('turns', turn_list), ('tool_calls', tools),
                       ('compactions', compacts), ('rate_limits', rates), ('repeated_calls', repeated)]:
        write_csv(out / (name + '.csv'), data)
    print(json.dumps({'window': summary['window'], 'quality': summary['quality'], 'totals': summary['totals'],
                      'daily': summary['daily'], 'models': summary['models'], 'tools': summary['tools'],
                      'goal_events': len(goal_events), 'recent_goal_db': len(summary['recent_goal_db']),
                      'top_sessions': [{k: s[k] for k in ['thread_id','title','input_tokens','uncached_input_tokens','cache_hit_pct','requests','turns_started','compactions','clock_sleep']} for s in session_list[:10]]}, ensure_ascii=False, indent=2))

def self_test():
    a = usage({'input_tokens': 100, 'cached_input_tokens': 80, 'output_tokens': 10, 'total_tokens': 110})
    b = {k: v * 2 for k, v in a.items()}
    assert legacy_delta(a, a, a) == (None, 'duplicate')
    assert legacy_delta(b, a, a) == (a, 'delta')
    assert legacy_delta(a, b, a) == (a, 'reset')
    assert legacy_delta(b, None, a) == (a, 'initial')
    assert aggregate([a, a])['uncached_input_tokens'] == 40
    assert tool_details({'name': 'clock.sleep', 'arguments': '{"duration_ms":60000}'})[0] == 'clock_sleep'
    assert tool_details({'name': 'functions.exec', 'input': 'await tools.write_stdin({session_id:3})'})[0] == 'process_poll'
    # Regression: copied history with freshly rewritten timestamps and a mirror
    # published only after a 30-second tool wait must not double-count usage.
    import tempfile
    import contextlib
    import io
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        (root / 'sessions').mkdir()
        def event(t, typ, payload):
            return {'timestamp': '2026-09-05T' + t + 'Z', 'type': typ, 'payload': payload}
        fixture = [
            event('12:00:00', 'session_meta', {'id': 'child', 'timestamp': '2026-09-05T12:00:00Z'}),
            event('12:00:00', 'event_msg', {'type': 'task_started', 'turn_id': 'old', 'started_at': 1}),
            event('12:00:00', 'event_msg', {'type': 'token_count', 'info': {'total_token_usage': a, 'last_token_usage': a}}),
            event('12:01:00', 'event_msg', {'type': 'task_started', 'turn_id': 'native', 'started_at': int(stamp('2026-09-05T12:01:00Z').timestamp())}),
            event('12:01:00', 'turn_context', {'turn_id': 'native', 'model': 'test'}),
            event('12:01:01', 'token_usage_record', {'thread_id': 'child', 'turn_id': 'native', 'response_id': 'unique', 'usage': a}),
            event('12:01:31', 'event_msg', {'type': 'token_count', 'info': {'total_token_usage': b, 'last_token_usage': a}}),
            event('12:01:32', 'token_usage_record', {'thread_id': 'child', 'turn_id': 'native', 'response_id': 'unique', 'usage': a}),
        ]
        (root / 'sessions' / 'fixture.jsonl').write_text('\n'.join(json.dumps(e) for e in fixture))
        opts = argparse.Namespace(codex_home=str(root), out=str(root/'out'), since='2026-09-05T00:00:00Z', until='2026-09-06T00:00:00Z', timezone='UTC', all_files=True)
        with contextlib.redirect_stdout(io.StringIO()):
            audit(opts)
        result = json.loads((root/'out'/'summary.json').read_text())
        assert result['totals']['requests'] == 1
        assert result['totals']['input_tokens'] == 100
        assert result['quality']['duplicate_response_ids'] == 1
        assert result['quality']['legacy_requests'] == 0
    print('7 unit checks and replay/delayed-mirror/response-dedup integration fixture passed')

if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--codex-home', default='~/.codex')
    ap.add_argument('--since', default='2026-09-05T05:27:20Z')
    ap.add_argument('--until', default='2026-09-12T05:27:20Z')
    ap.add_argument('--timezone', default='Europe/Moscow')
    ap.add_argument('--out', default=str(Path(__file__).parent))
    ap.add_argument('--all-files', action='store_true', help='Ignore mtime prefilter; event timestamps still bound the report')
    ap.add_argument('--self-test', action='store_true')
    args = ap.parse_args()
    self_test() if args.self_test else audit(args)
