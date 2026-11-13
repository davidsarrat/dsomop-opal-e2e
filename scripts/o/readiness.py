"""Wait for the pinned Opal API and a running default R server, using curl."""
import json
import os
from pathlib import Path
import re
import subprocess
import time


def validate(body, kind, expected):
    if kind == "version":
        version = body.strip()
        if version == expected:
            return True
        # A real, different version is a configuration error, not slow startup.
        if re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][\w.-]+)?", version):
            raise ValueError(f"Unexpected Opal version: expected {expected!r}, received {version!r}")
        return False
    try:
        clusters = json.loads(body)
    except (ValueError, UnicodeError):
        return False
    if not isinstance(clusters, list):
        return False
    for cluster in clusters:
        if not isinstance(cluster, dict) or cluster.get("name") != "default":
            continue
        servers = cluster.get("servers")
        if isinstance(servers, list) and any(
            isinstance(server, dict) and server.get("running") is True
            for server in servers
        ):
            return True
    return False


def wait_for(kind, endpoint, accept, filename):
    out = Path(os.environ["OUT"])
    attempts = int(os.environ.get("OPAL_READY_ATTEMPTS", "90"))
    interval = float(os.environ.get("OPAL_READY_INTERVAL", "5"))
    if attempts < 1 or interval < 0:
        raise ValueError("Readiness attempts must be positive and interval nonnegative")
    body_file = out / (filename + ".last")
    for attempt in range(1, attempts + 1):
        # Do not parse HTTP status, curl diagnostics or stale/partial bytes as a body.
        body_file.write_bytes(b"")
        response = subprocess.run([
            "curl", "--silent", "--show-error", "--connect-timeout", "5", "--max-time", "15",
            "--header", f"Accept: {accept}", "--user", "administrator:" + os.environ["OPAL_ADMIN_PW"],
            "--output", str(body_file), "--write-out", "%{http_code}",
            os.environ["OPAL_URL"].rstrip("/") + endpoint,
        ], capture_output=True, text=True, timeout=20)
        status = response.stdout.strip()
        body = body_file.read_text(errors="replace")
        (out / (filename + ".http")).write_text(
            f"attempt={attempt} curl_exit={response.returncode} http_status={status}\n" + response.stderr)
        if response.returncode == 0 and status == "200":
            if validate(body, kind, os.environ["OPAL_VERSION"]):
                (out / filename).write_text(body)
                print(f"Opal {kind} ready after {attempt} attempt(s)", flush=True)
                return
        print(f"Waiting for Opal {kind}: attempt {attempt}/{attempts}, "
              f"curl={response.returncode}, HTTP={status or 'none'}", flush=True)
        if attempt < attempts:
            time.sleep(interval)
    raise ValueError(f"Opal {kind} endpoint did not become ready after {attempts} attempts; "
                     f"see {filename}.last and {filename}.http")


if __name__ == "__main__":
    try:
        wait_for("version", "/ws/system/version", "text/plain", "opal-version.txt")
        wait_for("clusters", "/ws/service/r/clusters", "application/json", "opal-clusters.json")
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        raise SystemExit(str(error))
