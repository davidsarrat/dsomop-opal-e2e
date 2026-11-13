"""Collect failure evidence and redact credentials before either publication route."""
import json
import os
from pathlib import Path
import subprocess


def collect():
    out = Path(os.environ["OUT"])
    out.mkdir(parents=True, exist_ok=True)
    stack = os.environ["STACK"]
    commands = {
        "rock.log": ["docker", "logs", f"{stack}-rock"],
        "opal.log": ["docker", "logs", f"{stack}-opal"],
        "stack-status.txt": ["docker", "compose", "-f", "compose/opal-matrix.yml", "ps", "-a"],
    }
    for filename, command in commands.items():
        with (out / filename).open("wb") as handle:
            try:
                result = subprocess.run(command, stdout=handle, stderr=subprocess.STDOUT, timeout=30)
                handle.write(f"\n[collector exit={result.returncode}]\n".encode())
            except (OSError, subprocess.TimeoutExpired) as error:
                handle.write(f"\n[collector unavailable: {error}]\n".encode())
    metadata = {key: os.environ.get(key, "") for key in (
        "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_SHA", "GITHUB_REPOSITORY",
        "OPAL_VERSION", "E2E_PATH", "MODE", "JOB_STATUS")}
    metadata["steps"] = json.loads(os.environ.get("STEPS_JSON", "{}"))
    metadata["captured_at"] = "before results publication and stack removal"
    (out / "workflow-status.json").write_text(json.dumps(metadata, indent=2) + "\n")
    secrets = sorted({os.environ[key].encode() for key in (
        "OPAL_ADMIN_PW", "ANALYST_PW", "ANALYST2_PW", "OMOPDB_PW", "READER_PW",
        "GITHUB_PAT", "GITHUB_TOKEN") if os.environ.get(key)}, key=len, reverse=True)
    # Literal byte replacement handles punctuation, empty/unset values and raw
    # HTTP bodies without sed expressions or text-decoding assumptions.
    for path in out.rglob("*"):
        if path.is_file() and ".git" not in path.relative_to(out).parts:
            data = path.read_bytes()
            for secret in secrets:
                data = data.replace(secret, b"***")
            path.write_bytes(data)


if __name__ == "__main__":
    collect()
