#!/usr/bin/env python3
"""Always collect the complete transcript, including failed setup/commands."""
import json
import os
from pathlib import Path
import subprocess
from urllib.parse import quote, quote_plus

from run import HEADER


def redact(text, values):
    replacements = set()
    for value in values:
        if value:
            replacements.update((value, quote(value, safe=""), quote_plus(value),
                                 json.dumps(value)[1:-1]))
    for value in sorted(replacements, key=len, reverse=True):
        text = text.replace(value, "[REDACTED]")
    return text


def main():
    out = Path(os.environ["OUT"])
    out.mkdir(parents=True, exist_ok=True)
    raw = Path(os.environ["BOOK_RAW_TRANSCRIPT"])
    # Read every generated easy-opal secret, even when setup failed before the
    # manual credential step. Never copy the private files themselves to out/.
    values = []
    secret_file = Path.home() / ".easy-opal/instances/book/secrets.env"
    if secret_file.exists():
        for line in secret_file.read_text().splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                values.append(line.split("=", 1)[1].strip())
    environ = Path.home() / "book-work/.Renviron"
    if environ.exists():
        for line in environ.read_text().splitlines():
            if "PASSWORD=" in line:
                values.append(json.loads(line.split("=", 1)[1]))
    for key in ("GITHUB_TOKEN", "GITHUB_PAT"):
        values.append(os.environ.get(key, ""))
    transcript = raw.read_text(errors="replace") if raw.exists() else (
        HEADER + "\nWalkthrough did not start. See workflow step outcomes below.\n")
    steps = json.loads(os.environ.get("STEPS_JSON", "{}"))
    metadata = {"run_id": os.environ.get("GITHUB_RUN_ID"),
                "attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
                "commit": os.environ.get("GITHUB_SHA"),
                "job_status_before_collection": os.environ.get("JOB_STATUS"),
                "steps": steps}
    transcript += "\n===== Workflow outcome =====\n" + json.dumps(metadata, indent=2) + "\n"
    for command in (["docker", "ps", "-a"], ["docker", "logs", "book-opal"],
                    ["docker", "logs", "book-rock"]):
        transcript += "\n===== Diagnostic: " + " ".join(command) + " =====\n"
        try:
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    timeout=30, check=False)
            transcript += result.stdout.decode(errors="replace")
            transcript += f"\n[exit status: {result.returncode}]\n"
        except (OSError, subprocess.TimeoutExpired) as error:
            transcript += f"Diagnostic unavailable: {error}\n"
    # Atomic publication: the publisher refuses to use an unfinished transcript.
    temporary = out / "transcript.tmp"
    temporary.write_text(redact(transcript, values))
    temporary.replace(out / "transcript.txt")
    (out / "result.json").write_text(redact(json.dumps(metadata, indent=2) + "\n", values))
    (out / "redaction-complete").write_text("Only transcript.txt and result.json may be published.\n")
    print("Collected full transcript with credentials redacted.")


if __name__ == "__main__":
    main()
