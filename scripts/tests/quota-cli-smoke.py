#!/usr/bin/env python3
"""Exercise imported quota reporting without network access or private data."""

import json
import argparse
import subprocess
import sys
import tempfile
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    binary = Path(parser.parse_args().binary).resolve()
    with tempfile.TemporaryDirectory(prefix="sessionmonitor-quota-smoke-") as temporary:
        directory = Path(temporary)
        database = directory / "usage.sqlite"
        rollout = directory / "rollout.jsonl"
        event = {
            "timestamp": "2026-09-20T10:00:00Z",
            "type": "event_msg",
            "payload": {
                "type": "token_count",
                "rate_limits": {
                    "limit_id": "fixture-limit",
                    "plan_type": "fixture",
                    "primary": {"used_percent": 82, "resets_at": 1790422316, "window_minutes": 300},
                    "secondary": None,
                    "individual_limit": None,
                },
            },
        }
        rollout.write_text(json.dumps(event) + "\n", encoding="utf-8")
        subprocess.run(
            [str(binary), "import", str(rollout), "--database", str(database)],
            check=True,
            capture_output=True,
            text=True,
        )

        json_result = subprocess.run(
            [str(binary), "quota", "--database", str(database), "--json"],
            check=True,
            capture_output=True,
            text=True,
        )
        report = json.loads(json_result.stdout)
        assert report["coverage"]["state"] == "observed"
        snapshot = report["snapshots"][0]
        window = snapshot["windows"][0]
        assert snapshot["scope"] == "unknown"
        assert window["usedPercent"] == 82
        assert window["windowMinutes"] == 300

        text_result = subprocess.run(
            [str(binary), "quota", "--database", str(database)],
            check=True,
            capture_output=True,
            text=True,
        )
        assert "used=82.0%" in text_result.stdout
        assert "remaining=18.0% (derived)" in text_result.stdout
        assert "scope=unknown" in text_result.stdout

        usage_result = subprocess.run(
            [str(binary), "report", "--database", str(database), "--json"],
            check=True,
            capture_output=True,
            text=True,
        )
        usage = json.loads(usage_result.stdout)
        assert usage["totals"]["requests"] == 0

        unsupported_database = directory / "unsupported.sqlite"
        unsupported_rollout = directory / "unsupported.jsonl"
        unsupported_event = {
            "timestamp": "2026-09-20T10:01:00Z",
            "type": "event_msg",
            "payload": {"type": "token_count", "rate_limits": "future-schema"},
        }
        unsupported_rollout.write_text(json.dumps(unsupported_event) + "\n", encoding="utf-8")
        subprocess.run(
            [str(binary), "import", str(unsupported_rollout), "--database", str(unsupported_database)],
            check=True,
            capture_output=True,
            text=True,
        )
        unsupported_result = subprocess.run(
            [str(binary), "quota", "--database", str(unsupported_database)],
            check=True,
            capture_output=True,
            text=True,
        )
        assert "Quota events were observed, but no supported window observation was available" in (
            unsupported_result.stdout
        )
        assert "No quota event was observed in this interval" not in unsupported_result.stdout

    print("Quota CLI smoke passed: observed snapshot, unsupported coverage, derived remaining and isolated accounting")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
