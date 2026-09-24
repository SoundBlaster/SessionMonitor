#!/usr/bin/env python3
"""Exercise imported quota reporting without network access or private data."""

import json
import argparse
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    binary = Path(parser.parse_args().binary).resolve()
    with tempfile.TemporaryDirectory(prefix="sessionmonitor-quota-smoke-") as temporary:
        directory = Path(temporary)
        database = directory / "usage.sqlite"
        rollout = directory / "rollout.jsonl"
        observed_at = datetime.now(timezone.utc).replace(second=0, microsecond=0) - timedelta(minutes=6)
        reset_at = int((observed_at + timedelta(hours=4)).timestamp())
        used_percent = 25.0
        rates = [0.8, 0.9, 1.0, 1.1, 1.2, 20.0]
        events = []
        first_used = used_percent
        for index in range(len(rates) + 1):
            event = {
                "timestamp": observed_at.isoformat().replace("+00:00", "Z"),
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "rate_limits": {
                        "limit_id": "fixture-limit",
                        "plan_type": "fixture",
                        "account_id": "fixture-account",
                        "primary": {"used_percent": used_percent, "resets_at": reset_at, "window_minutes": 300},
                        "secondary": None,
                        "individual_limit": None,
                    },
                },
            }
            events.append(json.dumps(event))
            if index < len(rates):
                used_percent += rates[index] / 60
                observed_at += timedelta(minutes=1)
        rollout.write_text("\n".join(events) + "\n", encoding="utf-8")
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
        assert snapshot["scope"] == "account"
        assert window["usedPercent"] == first_used
        assert window["windowMinutes"] == 300

        text_result = subprocess.run(
            [str(binary), "quota", "--database", str(database)],
            check=True,
            capture_output=True,
            text=True,
        )
        assert "used=25.4%" in text_result.stdout
        assert "remaining=74.6% (derived)" in text_result.stdout
        assert "scope=account" in text_result.stdout

        doctor_json = subprocess.run(
            [str(binary), "doctor", "--database", str(database), "--json"],
            check=True,
            capture_output=True,
            text=True,
        )
        doctor_report = json.loads(doctor_json.stdout)
        assert "quotaAssessments" in doctor_report
        assert any(item["outcome"] == "sharp_shift" for item in doctor_report["quotaAssessments"])
        assert all(
            not evidence.get("sessionIDs", [])
            for item in doctor_report["quotaAssessments"]
            for evidence in item["evidence"]["observed"]
        )
        doctor_text = subprocess.run(
            [str(binary), "doctor", "--database", str(database)],
            check=True,
            capture_output=True,
            text=True,
        )
        assert "[quota sharp_shift]" in doctor_text.stdout

        usage_result = subprocess.run(
            [str(binary), "report", "--database", str(database), "--json"],
            check=True,
            capture_output=True,
            text=True,
        )
        usage = json.loads(usage_result.stdout)
        assert usage["totals"]["requests"] == 0
        assert usage["accountScope"]["kind"] == "allAccounts"

        profile_root = directory / "profile-root"
        profile_root.mkdir()
        profile_source = profile_root / "session.jsonl"
        profile_source.write_text(
            json.dumps({
                "timestamp": "1970-01-01T00:01:40Z",
                "type": "session_meta",
                "payload": {
                    "id": "profile-session",
                    "timestamp": "1970-01-01T00:01:40Z",
                    "creator_account_id": "synthetic-account",
                },
            }) + "\n"
            + json.dumps({
                "timestamp": "1970-01-01T00:01:41Z",
                "type": "event_msg",
                "payload": {"type": "task_started", "turn_id": "turn", "started_at": 101},
            }) + "\n"
            + json.dumps({
                "timestamp": "1970-01-01T00:01:41Z",
                "type": "turn_context",
                "payload": {"turn_id": "turn", "model": "fixture"},
            }) + "\n"
            + json.dumps({
                "timestamp": "1970-01-01T00:01:42Z",
                "type": "token_usage_record",
                "payload": {
                    "thread_id": "profile-session",
                    "turn_id": "turn",
                    "response_id": "profile-response",
                    "usage": {"input_tokens": 100, "cached_input_tokens": 80, "output_tokens": 10},
                },
            }) + "\n",
            encoding="utf-8",
        )
        subprocess.run(
            [str(binary), "import", str(profile_root), "--database", str(database)],
            check=True,
            capture_output=True,
            text=True,
        )
        mapped = subprocess.run(
            [str(binary), "profiles", "map-root", "--root", str(profile_root), "--id", "home",
             "--label", "Home", "--database", str(database)],
            check=True,
            capture_output=True,
            text=True,
        )
        assert json.loads(mapped.stdout)["mappingState"] == "assigned"
        profile_report = subprocess.run(
            [str(binary), "report", "--profile", "home", "--database", str(database), "--json"],
            check=True,
            capture_output=True,
            text=True,
        )
        scoped = json.loads(profile_report.stdout)
        assert scoped["accountScope"] == {"kind": "profile", "profileID": "home"}
        assert scoped["totals"]["requests"] == 1
        unknown_report = subprocess.run(
            [str(binary), "report", "--unknown-or-mixed", "--database", str(database), "--json"],
            check=True,
            capture_output=True,
            text=True,
        )
        assert json.loads(unknown_report.stdout)["totals"]["requests"] == 0

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

    print("Quota CLI smoke passed: production import reaches sharp-shift detection, evidence boundaries and accounting")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
