#!/usr/bin/env python3
"""Measure Release CLI queries on an isolated SQLite backup; outputs contain private metadata."""

import argparse
import datetime as dt
import hashlib
import json
import math
from pathlib import Path
import platform
import sqlite3
import statistics
import subprocess

from measure import timed


def percentile(values, fraction):
    """Nearest-rank descriptive percentile; small samples do not establish a tail SLA."""
    ordered = sorted(values)
    if not ordered or not 0 < fraction <= 1:
        raise ValueError('A percentile needs samples and a fraction in (0, 1]')
    return ordered[math.ceil(len(ordered) * fraction) - 1]


def summary(samples):
    walls = [sample['wall_seconds'] for sample in samples]
    return {
        'samples': len(samples), 'wall_median_seconds': statistics.median(walls),
        'wall_p95_seconds': percentile(walls, 0.95), 'wall_min_seconds': min(walls),
        'wall_max_seconds': max(walls),
        'cpu_median_seconds': statistics.median(sample['cpu_seconds'] for sample in samples),
        'peak_rss_max_bytes': max(sample['peak_rss_bytes'] for sample in samples),
        'stdout_max_bytes': max(sample['stdout_bytes'] for sample in samples),
    }


def backup(source, destination):
    """Read the live index through SQLite's backup API, including committed WAL data."""
    source = source.expanduser().resolve(strict=True)
    if destination.exists() or source == destination.resolve():
        raise ValueError('Backup destination must be a new file separate from the source')
    with sqlite3.connect(source.as_uri() + '?mode=ro', uri=True) as reader:
        with sqlite3.connect(destination) as writer:
            reader.backup(writer)
            if writer.execute('PRAGMA quick_check').fetchone()[0] != 'ok':
                raise ValueError('SQLite backup failed quick_check')


def query_cases(database, since, until, session):
    index = ['--database', str(database)]
    window = ['--since', since, '--until', until, '--time-zone', 'UTC']
    return [
        ('version', ['--version']),
        ('report-all', ['report', *index, '--json']),
        ('report-window', ['report', *index, *window, '--json']),
        ('sessions-window', ['sessions', *index, *window, '--json']),
        ('snapshot-window', ['snapshot', *index, *window]),
        ('activity-session-window', ['activity', *index, *window, '--session', session, '--json']),
        ('quota-window', ['quota', *index, *window, '--json']),
        ('quota-all', ['quota', *index, '--json']),
        ('quota-summary-all', ['quota', *index, '--summary', '--json']),
        ('agent-latest-24h', ['agent', 'status', *index, '--json']),
        ('agent-session-168h', ['agent', 'status', *index, '--session', session,
                                '--lookback-hours', '168', '--json']),
        ('inspect-session-window', ['inspect', session, *index, *window, '--json']),
        ('doctor-window', ['doctor', *index, *window, '--json']),
        ('alerts-list', ['alerts', 'list', *index, '--status', 'all', '--json']),
    ]


def measure_case(binary, arguments, destination, timeout):
    result = timed([binary, *arguments], destination, timeout=timeout)
    data = destination.read_bytes()
    result['stdout_bytes'] = len(data)
    result['stdout_sha256'] = hashlib.sha256(data).hexdigest()
    if arguments != ['--version']:
        decoded = json.loads(data)
        result['json_kind'] = type(decoded).__name__
    return result


def run(args):
    binary = args.binary.expanduser().resolve(strict=True)
    output = args.output.expanduser().resolve()
    source = args.database.expanduser().resolve(strict=True)
    if output.exists() or output == source or output in source.parents:
        raise ValueError('Output must be a new private directory separate from the source database')
    output.mkdir(parents=True, mode=0o700)
    database = output / 'index.sqlite'
    backup(source, database)
    with sqlite3.connect(database) as connection:
        corpus = {table: connection.execute('SELECT COUNT(*) FROM ' + table).fetchone()[0]
                  for table in ('source_records', 'source_timeline_events', 'source_usage_limit_snapshots')}
        session = args.session or connection.execute(
            'SELECT session FROM source_records WHERE timestamp >= ? AND timestamp < ? '
            'GROUP BY session ORDER BY COUNT(*) DESC, session LIMIT 1',
            (dt.datetime.fromisoformat(args.since.replace('Z', '+00:00')).timestamp(),
             dt.datetime.fromisoformat(args.until.replace('Z', '+00:00')).timestamp()),
        ).fetchone()
        if not session:
            raise ValueError('No session in selected period')
        if not args.session:
            session = session[0]
        watermark = connection.execute('SELECT * FROM query_watermark').fetchall()

    result = {
        'schema_version': 1, 'created_at': dt.datetime.now(dt.timezone.utc).isoformat(),
        'binary_version': subprocess.check_output([binary, '--version'], text=True).strip(),
        'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
        'binary_source_revision': args.source_revision,
        'os': platform.platform(), 'architecture': platform.machine(),
        'database_bytes': database.stat().st_size, 'corpus': corpus,
        'window': {'since': args.since, 'until_exclusive': args.until, 'time_zone': 'UTC'},
        'condition': 'Fresh CLI process for every sample. First call separate from repeats. '
                     'OS cache uncontrolled; SQLite backup precedes timing; not cold-disk latency.',
        'wall_resolution_seconds': 0.01 if platform.system() == 'Darwin' else None,
        'cases': {},
    }
    private = {'source_database': str(source), 'session': session, 'commands': {}}
    for name, arguments in query_cases(database, args.since, args.until, session):
        private['commands'][name] = arguments
        print('Measuring ' + name, flush=True)
        directory = output / name
        directory.mkdir()
        try:
            first = measure_case(binary, arguments, directory / 'first.json', args.timeout)
            samples = [measure_case(binary, arguments, directory / f'repeat-{i}.json', args.timeout)
                       for i in range(args.repetitions)]
            result['cases'][name] = {'first': first, 'repeated': summary(samples), 'samples': samples}
            print(name + ': ' + json.dumps(result['cases'][name]['repeated']), flush=True)
        except (subprocess.SubprocessError, ValueError) as error:
            result['cases'][name] = {'error_type': type(error).__name__, 'timeout_seconds': args.timeout}
            print(name + ': failed (' + type(error).__name__ + ')', flush=True)
        (output / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
    with sqlite3.connect(database) as connection:
        if connection.execute('SELECT * FROM query_watermark').fetchall() != watermark:
            raise ValueError('A supposedly read-only command changed the snapshot watermark')
    result['watermark_unchanged'] = True
    (output / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
    (output / 'private-commands.json').write_text(json.dumps(private, indent=2) + '\n')
    print('Completed; snapshot watermark unchanged. Detailed output is private.', flush=True)
    if any('error_type' in case for case in result['cases'].values()):
        raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--source-revision', required=True, help='Source commit used to build this binary')
    parser.add_argument('--database', type=Path, required=True, help='Read-only source for a SQLite backup')
    parser.add_argument('--output', type=Path, required=True, help='New private directory for backup and raw outputs')
    parser.add_argument('--since', required=True)
    parser.add_argument('--until', required=True)
    parser.add_argument('--session', help='Exact session, otherwise choose the largest in the selected period')
    parser.add_argument('--repetitions', type=int, default=10)
    parser.add_argument('--timeout', type=float, default=60)
    args = parser.parse_args()
    if not 3 <= args.repetitions <= 30 or args.timeout <= 0:
        parser.error('Use 3...30 repetitions and a positive timeout')
    try:
        dates = [dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
                 for value in (args.since, args.until)]
        if any(value.utcoffset() is None for value in dates) or dates[0] >= dates[1]:
            raise ValueError('Expected an increasing timezone-aware [since, until) interval')
    except ValueError as error:
        parser.error(str(error))
    run(args)


if __name__ == '__main__':
    main()
