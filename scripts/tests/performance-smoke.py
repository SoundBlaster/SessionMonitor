#!/usr/bin/env python3
"""Exercise the complete baseline workflow using a tiny synthetic corpus."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def run(binary):
    repository = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix='performance-smoke-', dir=repository / '.build') as temporary:
        base = Path(temporary)
        source = base / 'source'
        source.mkdir()
        fixture = source / 'fixture.jsonl'
        timestamp = '1970-01-01T00:01:40Z'
        events = [
            {'timestamp': timestamp, 'type': 'session_meta', 'payload': {'id': 'S', 'timestamp': timestamp}},
            {'timestamp': timestamp, 'type': 'event_msg',
             'payload': {'type': 'task_started', 'turn_id': 'T', 'started_at': 100}},
            {'timestamp': timestamp, 'type': 'token_usage_record', 'payload': {
                'thread_id': 'S', 'turn_id': 'T', 'response_id': 'R', 'usage': {
                    'input_tokens': 100, 'cached_input_tokens': 80, 'cache_write_input_tokens': 0,
                    'output_tokens': 10, 'reasoning_output_tokens': 0, 'total_tokens': 110}}},
        ]
        fixture.write_text(''.join(json.dumps(event)+'\n' for event in events))
        before = hashlib.sha256(fixture.read_bytes()).digest()
        subprocess.run([sys.executable, str(repository / 'scripts/performance/baseline.py'),
                        '--binary', str(binary), '--source', str(source), '--output', str(base / 'result'),
                        '--since', '1970-01-01T00:00:00Z', '--until', '1970-01-01T01:00:00Z',
                        '--repetitions', '1', '--idle-seconds', '0.1', '--configuration', 'debug'],
                       check=True, timeout=60)
        result = json.loads((base / 'result/baseline.json').read_text())
        assert all(result['audit_parity']['matched'].values())
        assert result['audit_parity']['incremental_full_report_equal']
        assert result['unchanged']['samples'][0]['import']['ioMetrics']['bytesRead'] == 0
        assert result['first']['samples'][0]['peak_rss_bytes'] > 0
        assert result['append']['samples'][0]['import']['ioMetrics']['bytesRead'] > result['append']['fixture']['appended_bytes']
        assert hashlib.sha256(fixture.read_bytes()).digest() == before, 'Original fixture was mutated'
    print('Performance harness smoke passed: isolated copy, native metrics, audit and incremental parity')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', type=Path, required=True)
    run(parser.parse_args().binary.resolve(strict=True))
