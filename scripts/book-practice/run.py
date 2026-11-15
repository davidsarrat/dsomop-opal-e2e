#!/usr/bin/env python3
"""Execute the frozen book, with only the approved package-source substitution."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
BOOK = ROOT / "book"
HEADER = """Book: Use the same two resources on Opal
Only package-source substitution: dsOMOP and dsOMOPClient 2.10.5 are not on
GitHub yet. Install archives of this checkout's vendored pkgs/ sources instead.
pkgs/ contains unpacked source archives; the runner packs those exact trees.
Book helpers in book/ are byte-identical to the recorded docs/book revision.
The working copy receives the book's required Opal connection configuration.
The file chooser/editor and credential placeholders are automated as described
by the book. Each R block runs through Rscript in a fresh R session.
Credentials alone are redacted; command output is otherwise retained in full.
Failures are recorded, and subsequent walkthrough commands are still attempted.
Alternative pipx installation, optional maintenance commands and future-host
instructions are not additional steps in this initial-deployment walkthrough.
"""


def blocks(section, language):
    return re.findall(r"^```" + language + r"\n(.*?)^```\s*$", section,
                      flags=re.MULTILINE | re.DOTALL)


def extract(destination):
    """Extract, rather than retype, every executable fenced walkthrough block."""
    manifest = json.loads((BOOK / "source.json").read_text())
    for name, expected in manifest["files"].items():
        assert hashlib.sha256((BOOK / name).read_bytes()).hexdigest() == expected, name
    chapter = (BOOK / "book-00-start.Rmd").read_text()
    section = chapter.split("## Use the same two resources on Opal\n", 1)[1].split("\n## Try it", 1)[0]
    shell = blocks(section, "sh")
    chunks = blocks(section, "r")
    assert len(shell) == 2 and len(chunks) == 2
    commands = shell[0].strip().splitlines() + shell[1].strip().splitlines()
    assert len(commands) == 9
    install = blocks(chapter.split("## Get the book helpers", 1)[0], "r")[0]
    for package, variable in [("dsOMOP", "BOOK_SERVER_ARCHIVE"),
                              ("dsOMOPClient", "BOOK_CLIENT_ARCHIVE")]:
        old = f'remotes::install_github("isglobal-brge/{package}@2.10.5", upgrade = "never", auth_token = "")'
        assert install.count(old) == 1
        install = install.replace(old, f'remotes::install_local(Sys.getenv("{variable}"), upgrade = "never")')
    loader = blocks(chapter.split("## Load two public synthetic datasets", 1)[1]
                    .split("## Open the practice server", 1)[0], "r")[0]
    destination.mkdir(parents=True, exist_ok=True)
    for name, code in [("install.R", install), ("load.R", loader),
                       ("admin.R", chunks[0]), ("analyst.R", chunks[1])]:
        (destination / name).write_text(code)
    (destination / "commands.sh").write_text("#!/usr/bin/env bash\n" + "\n".join(commands) + "\n")
    return commands, manifest


def configure(work):
    # These are exactly the manual configuration choices requested in the book.
    config = work / "tools/book/connection.R"
    code = config.read_text()
    assert code.count('book_driver <- "DSLite"') == 1
    config.write_text(code.replace('book_driver <- "DSLite"', 'book_driver <- "Opal"'))
    secret_file = Path.home() / ".easy-opal/instances/book/secrets.env"
    values = dict(line.strip().split("=", 1) for line in secret_file.read_text().splitlines()
                  if line.strip() and not line.lstrip().startswith("#") and "=" in line)
    credentials = {
        "BOOK_OPAL_URL": "http://localhost:8080",
        "BOOK_OPAL_ADMIN_PASSWORD": values["OPAL_ADMIN_PASSWORD"],
        "BOOK_OPAL_USER": "bookreader",
        "BOOK_OPAL_PASSWORD": "Book1@" + secrets.token_hex(16),
    }
    # Rscript reads this at startup, implementing the documented restart of R.
    environ = work / ".Renviron"
    with open(environ, "x", opener=lambda p, f: os.open(p, f, 0o600)) as stream:
        stream.write("".join(f'{key}={json.dumps(value)}\n' for key, value in credentials.items()))
    print('Configured book_driver <- "Opal", http://localhost:8080, practice, default, bookreader.', flush=True)
    print("Wrote private book-work/.Renviron; subsequent Rscript processes load it.", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--extract-only", type=Path)
    args = parser.parse_args()
    if args.extract_only:
        extract(args.extract_only)
        return 0
    print(HEADER, flush=True)
    work = Path.home() / "book-work"
    work.mkdir(exist_ok=False)
    generated = work / "ci-chunks"
    commands, manifest = extract(generated)
    print(json.dumps(manifest, indent=2), flush=True)
    print("Harness commit:", subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(), flush=True)
    helpers = work / "tools/book"
    helpers.mkdir(parents=True)
    for name in manifest["files"]:
        if name != "book-00-start.Rmd":
            shutil.copyfile(BOOK / name, helpers / name)
    for package, variable in [("dsOMOP", "BOOK_SERVER_ARCHIVE"),
                              ("dsOMOPClient", "BOOK_CLIENT_ARCHIVE")]:
        source = ROOT / "pkgs" / package
        assert re.search(r"^Version: 2\.10\.5$", (source / "DESCRIPTION").read_text(), re.MULTILINE)
        archive = generated / f"{package}_2.10.5.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(source, arcname=package)
        os.environ[variable] = str(archive)
        print(f"Archive {archive.name}: SHA256 {hashlib.sha256(archive.read_bytes()).hexdigest()}", flush=True)
    os.environ["BOOK_ARCHIVE_INSTALLER"] = str(ROOT / "scripts/book-practice/install-server.R")
    admin = helpers / "opal-admin.R"
    code = admin.read_text()
    old = 'dsadmin.install_github_package(opal, "dsOMOP", username = "isglobal-brge",\n    ref = "2.10.5", profile = opal_profile)'
    assert code.count(old) == 1
    replacement = 'local({\n    source(Sys.getenv("BOOK_ARCHIVE_INSTALLER"), local = TRUE)\n    book_install_archive(opal, opal_profile)\n  })'
    admin.write_text(code.replace(old, replacement))
    print("Approved server install substitution in the working copy:\n" + replacement, flush=True)
    failed = []

    def run(label, argv, code=None):
        print("\n===== " + label + " =====", flush=True)
        if code is not None:
            print(code, end="" if code.endswith("\n") else "\n", flush=True)
        try:
            result = subprocess.run(argv, cwd=work, check=False).returncode
        except OSError as error:
            print(error, flush=True)
            result = 127
        print(f"\n[exit status: {result}]", flush=True)
        if result:
            failed.append(label)

    def run_r(name):
        path = generated / name
        run("Rscript " + name, ["Rscript", str(path)], path.read_text())

    run_r("install.R")
    run_r("load.R")
    for command in commands:
        run("shell", ["bash", "-c", command], command)
    print("\n===== Book's manual configuration / private credentials =====", flush=True)
    try:
        configure(work)
    except Exception as error:
        print(f"Configuration failed: {error}", flush=True)
        failed.append("configuration")
    run_r("admin.R")
    environ = work / ".Renviron"
    if environ.exists():
        environ.write_text("".join(line + "\n" for line in environ.read_text().splitlines()
                                  if not line.startswith("BOOK_OPAL_ADMIN_PASSWORD=")))
        print("\nRemoved administrator credentials before the fresh analyst R session.", flush=True)
    run_r("analyst.R")
    print("\n===== Walkthrough result =====", flush=True)
    print("FAIL: " + ", ".join(failed) if failed else "PASS: all walkthrough commands and R chunks completed", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
