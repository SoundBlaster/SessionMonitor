#!/usr/bin/env python3
"""Cross-process query observation, migration and importer ownership; synthetic data only."""

import argparse
import json
import os
from pathlib import Path
import runpy
import selectors
import signal
import subprocess
import tempfile
import time

helpers = runpy.run_path(str(Path(__file__).with_name("watch-cli-smoke.py")))
WatchProcess = helpers["WatchProcess"]
record = helpers["record"]


def command(binary, database, *args, success=True):
    result = subprocess.run([str(binary), *args, "--database", str(database)],
                            capture_output=True, timeout=10)
    if success:
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        return json.loads(result.stdout)
    assert result.returncode != 0, "A second importer acquired ownership"
    assert b"Another importer" in result.stderr, result.stderr


class Observer:
    def __init__(self, binary, database, errors):
        self.process = subprocess.Popen(
            [str(binary), "snapshot", "--follow", "--database", str(database)],
            stdout=subprocess.PIPE, stderr=errors)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.pending = b""

    def next(self):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if b"\n" in self.pending:
                line, self.pending = self.pending.split(b"\n", 1)
                return json.loads(line)
            if self.selector.select(timeout=0.1):
                data = os.read(self.process.stdout.fileno(), 65536)
                assert data, "Observer exited before delivering snapshot"
                self.pending += data
        raise AssertionError("External commit was not observed")

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait(timeout=5)
        self.selector.close()
        self.process.stdout.close()


def run(binary):
    with tempfile.TemporaryDirectory(prefix="sessionmonitor-snapshot-") as temporary:
        base = Path(temporary)
        database = base / "usage.sqlite"
        first_alias = base / "first-alias.sqlite"
        first_alias.symlink_to(database)
        # Independent first-open clients must agree on one migrated database identity.
        clients = [subprocess.Popen([str(binary), "snapshot", "--database",
                                     str(first_alias if index == 0 else database)],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE) for index in range(6)]
        try:
            initial = []
            for client in clients:
                output, errors = client.communicate(timeout=15)
                assert client.returncode == 0, errors.decode(errors="replace")
                initial.append(json.loads(output))
            assert len({item["watermark"]["databaseID"] for item in initial}) == 1
            assert all(item["watermark"]["revision"] == 0 for item in initial)
            assert not Path(str(first_alias) + ".setup-lock").exists()
        finally:
            for client in clients:
                if client.poll() is None:
                    client.kill()
                client.wait(timeout=5)
        root = base / "rollouts"
        root.mkdir()
        source = root / "session.jsonl"
        source.write_text(json.dumps({"timestamp": "1970-01-01T00:01:40Z", "type": "session_meta",
                                      "payload": {"id": "S", "timestamp": "1970-01-01T00:01:40Z"}}) + "\n"
                          + json.dumps({"timestamp": "1970-01-01T00:01:41Z", "type": "event_msg", "payload": {
                              "type": "task_started", "turn_id": "T", "started_at": 101}}) + "\n"
                          + record("R1"))
        with tempfile.TemporaryFile() as errors:
            observer = Observer(binary, database, errors)
            watch = None
            try:
                empty = observer.next()
                assert empty["coverage"]["cache"] == "empty"
                command(binary, database, "import", str(root))
                first = observer.next()
                assert first["report"]["totals"]["requests"] == 1
                assert first["coverage"]["cache"] == "complete"
                assert first["schemaVersion"] == 1
                assert first["watermark"]["revision"] > empty["watermark"]["revision"]
                command(binary, database, "import", str(root))
                unchanged = command(binary, database, "snapshot")
                assert unchanged == first
                assert not observer.pending and not observer.selector.select(timeout=1.2), "Idle duplicate snapshot"
                watch = WatchProcess(binary, root, first_alias, errors)
                watch.wait_status("watching")
                command(binary, database, "watch", str(root), success=False)
                alias = base / "alias.sqlite"
                alias.symlink_to(database)
                command(binary, alias, "watch", str(root), success=False)
                watch.process.send_signal(signal.SIGUSR1)
                watch.wait_status("paused")
                command(binary, database, "import", str(root), success=False)
                assert command(binary, database, "snapshot") == first
                with source.open("a") as output:
                    output.write(record("R2"))
                watch.process.send_signal(signal.SIGUSR2)
                watch.wait_status("watching")
                second = observer.next()
                assert second["report"]["totals"]["requests"] == 2
                assert second["watermark"]["revision"] > first["watermark"]["revision"]
                watch.process.kill()
                watch.process.wait(timeout=5)
                watch.close()
                watch = WatchProcess(binary, root, database, errors)
                watch.wait_status("watching")
                watch.process.send_signal(signal.SIGTERM)
                watch.wait_status("stopped")
                assert watch.process.wait(timeout=5) == 0
                command(binary, database, "import", str(root))
                observer.process.send_signal(signal.SIGTERM)
                assert observer.process.wait(timeout=5) == 0
            except Exception:
                errors.seek(0)
                print(errors.read().decode(errors="replace"))
                raise
            finally:
                if watch is not None:
                    watch.close()
                observer.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True, type=Path)
    arguments = parser.parse_args()
    run(arguments.binary.resolve(strict=True))
    print("Snapshot process smoke passed: external writes, idle suppression, concurrent migration, lease and SIGKILL recovery")
