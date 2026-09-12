#!/usr/bin/env python3
"""Reproducible, isolated macOS CLI baseline. Raw corpus and detailed evidence stay in .build."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys
import time

from measure import idle, timed

REPOSITORY = Path(__file__).resolve().parents[2]
MAPPING = {'requests': 'requests', 'inputTokens': 'input_tokens', 'cachedInputTokens': 'cached_input_tokens',
           'cacheWriteInputTokens': 'cache_write_input_tokens', 'outputTokens': 'output_tokens',
           'reasoningOutputTokens': 'reasoning_output_tokens', 'totalTokens': 'total_tokens'}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def digest(path):
    hasher = hashlib.sha256()
    with path.open('rb') as source:
        while chunk := source.read(1024*1024):
            hasher.update(chunk)
    return hasher.hexdigest()


def version(path):
    value = path.stat()
    return value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns, value.st_ctime_ns


def copy_corpus(source, destination):
    paths = sorted(path for path in source.rglob('*.jsonl')
                   if not any(part.startswith('.') for part in path.relative_to(source).parts))
    if not paths:
        raise ValueError('No visible JSONL corpus files')
    required = sum(path.stat().st_size for path in paths) + 1024**3
    if shutil.disk_usage(destination.parent.parent).free < required:
        raise OSError('Insufficient free space for independent corpus copy plus 1 GiB working reserve')
    destination.mkdir(parents=True)
    manifest = []
    for index, path in enumerate(paths):
        target = destination / f'{index:06}.jsonl'
        for attempt in range(3):
            before = version(path)
            hasher = hashlib.sha256()
            with path.open('rb') as reader, target.open('wb') as writer:
                while chunk := reader.read(1024*1024):
                    writer.write(chunk)
                    hasher.update(chunk)
            if before == version(path) and target.stat().st_size == before[2]:
                break
            if attempt == 2:
                raise RuntimeError('Source changed repeatedly while copying; retry with a stable corpus')
        manifest.append({'source': str(path), 'copy': target.name,
                         'bytes': before[2], 'sha256': hasher.hexdigest()})
    return manifest


def report(binary, database, since=None, until=None):
    command = [str(binary), 'report', '--database', str(database), '--json']
    if since:
        command += ['--since', since, '--until', until]
    return json.loads(subprocess.check_output(command, timeout=60))


def database_size(path):
    sizes = {suffix or 'database': Path(str(path)+suffix).stat().st_size
             if Path(str(path)+suffix).exists() else 0 for suffix in ('', '-wal', '-shm')}
    return {'files_bytes': sizes, 'total_bytes': sum(sizes.values()), 'state': 'all measured CLI writers exited'}


def summarize(samples):
    return {key: {'median': statistics.median(sample[key] for sample in samples),
                  'min': min(sample[key] for sample in samples), 'max': max(sample[key] for sample in samples)}
            for key in ('wall_seconds', 'cpu_seconds', 'peak_rss_bytes')}


def append_fixture(root, until):
    complete = []
    for path in root.glob('*.jsonl'):
        if path.stat().st_size:
            with path.open('rb') as source:
                source.seek(-1, 2)
                if source.read(1) == b'\n':
                    complete.append(path)
    if not complete:
        raise ValueError('Append baseline needs a source ending with a complete newline')
    target = max(complete, key=lambda path: path.stat().st_size)
    before = target.stat().st_size
    instant = dt.datetime.fromisoformat(until.replace('Z', '+00:00')) + dt.timedelta(seconds=1)
    timestamp = instant.isoformat()
    session = 'sessionmonitor-benchmark-' + str(time.time_ns())
    events = [
        {'type': 'session_meta', 'timestamp': timestamp, 'payload': {'id': session, 'timestamp': timestamp}},
        {'type': 'event_msg', 'timestamp': timestamp,
         'payload': {'type': 'task_started', 'turn_id': session, 'started_at': int(instant.timestamp())}},
        {'type': 'token_usage_record', 'timestamp': timestamp,
         'payload': {'thread_id': session, 'turn_id': session, 'response_id': session, 'usage': {
             'input_tokens': 100, 'cached_input_tokens': 80, 'cache_write_input_tokens': 0,
             'output_tokens': 10, 'reasoning_output_tokens': 0, 'total_tokens': 110}}},
    ]
    data = ''.join(json.dumps(event, separators=(',', ':'))+'\n' for event in events).encode()
    with target.open('ab') as output:
        output.write(data)
    return {'file': target.name, 'old_bytes': before, 'appended_bytes': len(data), 'timestamp': timestamp}


def run(args):
    output = args.output.resolve()
    source = args.source.expanduser().resolve(strict=True)
    binary = args.binary.resolve(strict=True)
    if not output.is_relative_to(REPOSITORY / '.build') or output == REPOSITORY / '.build':
        raise ValueError('Output must be a new subdirectory of repository .build (contains private copies)')
    if output.is_relative_to(source) or source.is_relative_to(output):
        raise ValueError('Corpus source and output must not overlap')
    output.mkdir(parents=True, exist_ok=False)
    home = output / 'corpus'
    root = home / 'sessions'
    print('Copying stable independent corpus', flush=True)
    manifest = copy_corpus(source, root)
    write_json(output / 'private-manifest.json', manifest)
    corpus = {'files': len(manifest), 'bytes': sum(item['bytes'] for item in manifest),
              'sha256': hashlib.sha256(''.join(item['sha256'] for item in manifest).encode()).hexdigest()}
    metadata = {'schema_version': 1, 'created_at': dt.datetime.now(dt.timezone.utc).isoformat(),
                'corpus': corpus, 'repetitions': args.repetitions, 'binary_sha256': digest(binary),
                'build_configuration': args.configuration, 'machine': platform.machine(),
                'macos': platform.mac_ver()[0], 'python': platform.python_version(),
                'hardware': subprocess.check_output(['/usr/sbin/sysctl', '-n', 'hw.model'], text=True).strip(),
                'memory_bytes': int(subprocess.check_output(['/usr/sbin/sysctl', '-n', 'hw.memsize'])),
                'swift': subprocess.check_output(['xcrun', 'swift', '--version'], text=True).strip(),
                'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
                'git_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPOSITORY, text=True).strip(),
                'harness_sha256': {name: digest(Path(__file__).with_name(name))
                                   for name in ('baseline.py', 'measure.py')},
                'window': {'since': args.since, 'until_exclusive': args.until, 'timezone': 'UTC'},
                'cache_condition': 'OS cache uncontrolled; corpus copy precedes timing; fresh index is not cold disk'}
    print(f'Corpus: {corpus["files"]} files, {corpus["bytes"]} bytes; running fresh imports', flush=True)
    databases, first, unchanged = [], [], []
    for index in range(args.repetitions):
        database = output / f'index-{index}.sqlite'
        databases.append(database)
        for name, samples in [('first', first), ('unchanged', unchanged)]:
            destination = output / f'{name}-{index}.json'
            measurement = timed([binary, 'import', root, '--database', database], destination)
            measurement['import'] = json.loads(destination.read_text())
            samples.append(measurement)
            if name == 'unchanged':
                assert measurement['import']['ioMetrics']['bytesRead'] == 0, 'Unchanged body was read'
                assert measurement['import']['ioMetrics']['filesSkipped'] == corpus['files']
        print(f'Import repetition {index+1}/{args.repetitions} complete', flush=True)
    baseline = report(binary, databases[-1])
    window = report(binary, databases[-1], args.since, args.until)
    write_json(output / 'window-report.json', window)
    print('Running existing Python reference audit on the same private corpus', flush=True)
    with (output / 'audit.stdout').open('wb') as stdout, (output / 'audit.stderr').open('wb') as stderr:
        subprocess.run([sys.executable, str(REPOSITORY / 'audit_codex.py'), '--codex-home', str(home),
                        '--out', str(output / 'audit'), '--all-files', '--since', args.since,
                        '--until', args.until, '--timezone', 'UTC'], stdout=stdout, stderr=stderr,
                       check=True, timeout=600)
    reference = json.loads((output / 'audit/summary.json').read_text())['totals']
    parity = {swift: window['totals'].get(swift) == reference[python] for swift, python in MAPPING.items()}
    if not all(parity.values()) or window['totals']['unknownCacheRequests'] != 0:
        write_json(output / 'parity-failure.json', {'matched': parity, 'swift': window['totals'], 'audit': reference})
        raise AssertionError('Audit mismatch or unknown counters: inspect private parity-failure.json')
    append = append_fixture(root, args.until)
    appended = []
    for index, database in enumerate(databases):
        destination = output / f'append-{index}.json'
        measurement = timed([binary, 'import', root, '--database', database], destination)
        measurement['import'] = json.loads(destination.read_text())
        assert measurement['import']['ioMetrics']['filesResumed'] == 1
        assert measurement['import']['ioMetrics']['filesSkipped'] == corpus['files']-1
        after = report(binary, database)
        assert after['totals']['requests'] == baseline['totals']['requests']+1
        assert after['totals']['inputTokens'] == baseline['totals']['inputTokens']+100
        assert report(binary, database, args.since, args.until) == window
        appended.append(measurement)
    # Independent complete decode must match every incremental report field, not only total input.
    rebuilt = output / 'rebuild.sqlite'
    timed([binary, 'import', root, '--database', rebuilt], output / 'rebuild.json')
    assert report(binary, rebuilt) == report(binary, databases[-1]), 'Incremental/full report mismatch'
    print('Audit and append/full-rebuild parity passed; sampling idle CPU', flush=True)
    idle_watch = idle(binary, root, databases[-1], output, args.idle_seconds, combined=False)
    idle_combined = idle(binary, root, databases[-1], output, args.idle_seconds, combined=True)
    metadata.update(first={'samples': first, 'summary': summarize(first)},
                    unchanged={'samples': unchanged, 'summary': summarize(unchanged)},
                    append={'fixture': append, 'samples': appended, 'summary': summarize(appended),
                            'reads_only_delta': all(item['import']['ioMetrics']['bytesRead'] == append['appended_bytes']
                                                    for item in appended)},
                    audit_parity={'matched': parity, 'unknown_cache_requests': 0,
                                  'totals': window['totals'], 'incremental_full_report_equal': True},
                    database=database_size(databases[-1]), idle_watch=idle_watch, idle_combined=idle_combined)
    metadata['corpus_retained'] = args.keep_corpus
    write_json(output / 'baseline.json', metadata)
    if not args.keep_corpus:
        shutil.rmtree(home)
    print(json.dumps({'result': str(output / 'baseline.json'), 'audit_parity': True,
                      'append_reads_only_delta': metadata['append']['reads_only_delta']}, indent=2), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True, help='Read-only directory of real JSONL files')
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='New directory under repository .build')
    parser.add_argument('--keep-corpus', action='store_true', help='Retain private copied logs after success')
    parser.add_argument('--configuration', choices=['debug', 'release'], default='release')
    parser.add_argument('--since', required=True)
    parser.add_argument('--until', required=True)
    parser.add_argument('--repetitions', type=int, default=3)
    parser.add_argument('--idle-seconds', type=float, default=30)
    args = parser.parse_args()
    if not 1 <= args.repetitions <= 10 or not 0.1 <= args.idle_seconds <= 300:
        parser.error('Use 1...10 repetitions and 0.1...300 idle seconds (30+ recommended for real measurement)')
    start = dt.datetime.fromisoformat(args.since.replace('Z', '+00:00'))
    end = dt.datetime.fromisoformat(args.until.replace('Z', '+00:00'))
    if start.tzinfo is None or end.tzinfo is None or start >= end:
        parser.error('Period requires ordered timezone-aware timestamps')
    run(args)


if __name__ == '__main__':
    main()
