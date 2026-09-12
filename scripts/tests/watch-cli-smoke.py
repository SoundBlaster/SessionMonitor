#!/usr/bin/env python3
"""Bounded process-level verification of the Swift CLI, using only Python's standard library."""

import argparse
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import tempfile
import time


def record(response):
    return json.dumps({
        "timestamp": "1970-01-01T00:01:42Z", "type": "token_usage_record",
        "payload": {"thread_id": "S", "turn_id": "T", "response_id": response,
                    "usage": {"input_tokens": 100, "cached_input_tokens": 80, "output_tokens": 10}},
    }) + "\n"


class WatchProcess:
    def __init__(self, binary, root, database, errors, backpressure=False):
        self.blocked_reader = None
        destination = subprocess.PIPE
        if backpressure:
            self.blocked_reader, destination = os.pipe()
            os.set_blocking(destination, False)
            try:
                while True:
                    os.write(destination, b"x" * 4096)
            except BlockingIOError:
                pass
            os.set_blocking(destination, True)
        self.process = subprocess.Popen(
            [str(binary), "watch", str(root), "--database", str(database), "--debounce-milliseconds", "40"],
            stdout=destination, stderr=errors,
        )
        self.selector = selectors.DefaultSelector()
        if backpressure:
            os.close(destination)
        else:
            self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.pending = b""

    def wait_status(self, phase, timeout=10):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            while b"\n" in self.pending:
                line, self.pending = self.pending.split(b"\n", 1)
                status = json.loads(line)
                if status["phase"] == phase:
                    return status
            if self.selector.select(timeout=0.1):
                data = os.read(self.process.stdout.fileno(), 65536)
                if not data:
                    raise AssertionError(f"CLI exited before status {phase}: {self.process.poll()}")
                self.pending += data
        raise AssertionError(f"Timed out waiting for CLI status {phase}")

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait(timeout=5)
        self.selector.close()
        if self.process.stdout is not None:
            self.process.stdout.close()
        if self.blocked_reader is not None:
            os.close(self.blocked_reader)


def run(binary, stop_signal, exercise_pause, backpressure=False):
    with tempfile.TemporaryDirectory(prefix="sessionmonitor-watch-") as temporary:
        root = Path(temporary) / "rollouts"
        root.mkdir()
        source = root / "session.jsonl"
        header = [
            {"timestamp": "1970-01-01T00:01:40Z", "type": "session_meta",
             "payload": {"id": "S", "timestamp": "1970-01-01T00:01:40Z"}},
            {"timestamp": "1970-01-01T00:01:41Z", "type": "event_msg",
             "payload": {"type": "task_started", "turn_id": "T", "started_at": 101}},
        ]
        source.write_text("".join(json.dumps(item) + "\n" for item in header) + record("R1"))
        database = Path(temporary) / "usage.sqlite"
        with tempfile.TemporaryFile() as errors:
            watch = WatchProcess(binary, root, database, errors, backpressure=backpressure)
            try:
                if backpressure:
                    deadline = time.monotonic() + 10
                    while True:
                        assert time.monotonic() < deadline, "Blocked-output watch did not import initial source"
                        assert watch.process.poll() is None, "Blocked-output watch exited before stop"
                        if database.exists():
                            report = subprocess.run(
                                [str(binary), "report", "--database", str(database), "--json"],
                                capture_output=True, timeout=5,
                            )
                            if report.returncode == 0 and json.loads(report.stdout)["totals"]["requests"] == 1:
                                break
                        time.sleep(0.05)
                    watch.process.send_signal(stop_signal)
                    assert watch.process.wait(timeout=5) == 0
                    return
                watch.wait_status("watching")
                if exercise_pause:
                    watch.process.send_signal(signal.SIGUSR1)
                    watch.wait_status("paused")
                    with source.open("a") as output:
                        output.write(record("R2"))
                    time.sleep(0.35)
                    report = subprocess.run(
                        [str(binary), "report", "--database", str(database), "--json"],
                        check=True, capture_output=True, timeout=5,
                    )
                    assert json.loads(report.stdout)["totals"]["requests"] == 1
                    watch.process.send_signal(signal.SIGUSR2)
                    resumed = watch.wait_status("watching")
                    assert resumed["lastImport"]["records"] == 1
                    report = subprocess.run(
                        [str(binary), "report", "--database", str(database), "--json"],
                        check=True, capture_output=True, timeout=5,
                    )
                    assert json.loads(report.stdout)["totals"]["requests"] == 2
                watch.process.send_signal(stop_signal)
                watch.wait_status("stopped")
                assert watch.process.wait(timeout=5) == 0
            except Exception:
                errors.seek(0)
                print(errors.read().decode(errors="replace"))
                raise
            finally:
                watch.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True, type=Path)
    arguments = parser.parse_args()
    executable = arguments.binary.resolve(strict=True)
    run(executable, signal.SIGTERM, exercise_pause=True)
    run(executable, signal.SIGINT, exercise_pause=False)
    run(executable, signal.SIGTERM, exercise_pause=False, backpressure=True)
    print("CLI watch smoke passed: pause/resume, accounting, SIGTERM/SIGINT and blocked-stdout cleanup")
