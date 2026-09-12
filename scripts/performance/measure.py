"""macOS measurement primitives; standard library and Apple's time/ps only."""
import contextlib
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import time


def timed(command, destination, timeout=600):
    """Apple time -l reports peak RSS in bytes; elapsed/CPU have centisecond resolution."""
    destination = Path(destination)
    timing = destination.with_suffix('.time')
    with destination.open('wb') as output, destination.with_suffix('.stderr').open('wb') as errors:
        arguments = ['/usr/bin/time', '-l', '-p', '-o', str(timing), *map(str, command)]
        process = subprocess.Popen(arguments, stdout=output, stderr=errors, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
            if code:
                raise subprocess.CalledProcessError(code, arguments)
        except BaseException:
            # time may supervise a child CLI: stop the whole group we created on timeout/interruption.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)
            raise
    fields = {}
    for line in timing.read_text().splitlines():
        parts = line.split()
        if parts and parts[0] in ('real', 'user', 'sys'):
            fields[parts[0]] = float(parts[1])
        elif 'maximum resident set size' in line:
            fields['peak_rss_bytes'] = int(parts[0])
    if set(fields) != {'real', 'user', 'sys', 'peak_rss_bytes'}:
        raise ValueError('Unexpected /usr/bin/time format: ' + str(timing))
    fields['cpu_seconds'] = fields.pop('user') + fields.pop('sys')
    fields['wall_seconds'] = fields.pop('real')
    return fields


def cpu_seconds(pid):
    raw = subprocess.check_output(['/bin/ps', '-o', 'time=', '-p', str(pid)], text=True).strip()
    seconds = 0.0
    for part in raw.split(':'):
        seconds = seconds * 60 + float(part)
    return seconds


class StreamProcess:
    def __init__(self, command, errors):
        self.process = subprocess.Popen(list(map(str, command)), stdout=subprocess.PIPE, stderr=errors)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.pending = b''

    def next(self, timeout=600):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if b'\n' in self.pending:
                line, self.pending = self.pending.split(b'\n', 1)
                return json.loads(line)
            if self.selector.select(timeout=min(0.5, max(0, deadline-time.monotonic()))):
                data = os.read(self.process.stdout.fileno(), 65536)
                if not data:
                    raise RuntimeError('Process ended before expected JSON line')
                self.pending += data
        raise TimeoutError('Process did not emit expected JSON line')

    def stop(self):
        if self.process.poll() is None:
            self.process.send_signal(signal.SIGTERM)
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
                raise
        if self.process.returncode != 0:
            raise RuntimeError('Unexpected process exit: ' + str(self.process.returncode))

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait(timeout=5)
        self.process.stdout.close()
        self.selector.close()


@contextlib.contextmanager
def stream(command, errors):
    child = StreamProcess(command, errors)
    try:
        yield child
    finally:
        child.close()


def idle(binary, root, database, directory, seconds, combined):
    with contextlib.ExitStack() as stack:
        errors = stack.enter_context((directory / ('idle-combined.stderr' if combined else 'idle-watch.stderr')).open('wb'))
        watch = stack.enter_context(stream([binary, 'watch', root, '--database', database], errors))
        status = watch.next()
        while status['phase'] != 'watching':
            if status['phase'] == 'recovering':
                raise RuntimeError('Idle watch failed: ' + status.get('error', 'unknown'))
            status = watch.next()
        if status['lastImport']['ioMetrics']['bytesRead'] != 0:
            raise AssertionError('Idle measurement requires an already-current index')
        children = {'watch': watch}
        if combined:
            observer = stack.enter_context(stream([binary, 'snapshot', '--follow', '--database', database], errors))
            observer.next()
            children['observer'] = observer
        # Allow initial FSEvents batches/startup queries to settle outside the sample.
        time.sleep(1)
        before = {name: cpu_seconds(child.process.pid) for name, child in children.items()}
        start = time.monotonic()
        time.sleep(seconds)
        elapsed = time.monotonic() - start
        samples = {name: cpu_seconds(child.process.pid)-before[name] for name, child in children.items()}
        for child in children.values():
            if child.pending or child.selector.select(timeout=0):
                raise AssertionError('Unexpected activity during idle sample')
            child.stop()
        return {'wall_seconds': elapsed, 'cpu_seconds': samples,
                'one_core_percent': {name: 100*cpu/elapsed for name, cpu in samples.items()},
                'cpu_resolution_seconds': 0.01}
