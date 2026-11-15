# Optional Opal walkthrough evidence

`source.json` identifies the docs/book commit and SHA256 of every copied helper
and the complete Getting started source. These files are copied byte-for-byte.
The source closure is the eight helpers here: load-practice.R sources
load-numeric.R; the administrator and analyst scripts source connection.R;
connection.R can source practice.R for DSLite. No other helper is required.

The coordinator pushes this harness commit and dispatches `book-practice.yml`.
No push or dispatch is performed by the developer. The workflow is manual only,
uses ubuntu-latest and real Docker/easy-opal, and publishes results even when the
walkthrough fails to `results/<run_id>-book-practice`. The branch contains
`transcript.txt` and `result.json`; artifacts are a secondary copy.

The runner extracts all nine shell commands and both executable R blocks from
the optional section in their book order. The preceding installation and
two-database loader blocks run first, because the walkthrough explicitly
requires them. R blocks run with Rscript. Commands are logged before execution,
with complete combined stdout/stderr and exit status. A failed command does not
silently skip later commands. Workflow step outcomes and full Opal/Rock Docker
logs are appended by an always-running collector. Only generated credentials
are redacted. Raw output stays in RUNNER_TEMP and is never uploaded or committed.

The repository has unpacked candidate source archives in `pkgs/`, not tarballs.
The runner creates tar.gz archives of those exact trees and records their hashes.
The only package-source substitution is dsOMOP/dsOMOPClient 2.10.5 from these
archives instead of GitHub. Local installation uses remotes::install_local;
the server archive is copied to Rock and installed with remotes in Rock's service
R library, following the service-library approach in scripts/common.R. Its full
installation log and exit status are captured. Publication remains the book's
unmodified dsadmin.publish_package calls. dsBase 6.3.5 still comes from GitHub.

The runner automates obtaining the helper files, editing book_driver to Opal,
setting the printed localhost:8080 URL and writing generated credentials into
the working directory's private .Renviron. Each later Rscript starts a new R
session. These are the book's required manual setup choices, not repairs to its
deployment logic. The committed helper files are untouched; only the disposable
working copies receive configuration and the approved server install replacement.

The alternative pipx command, informational Compose maintenance examples,
conditional configuration-change instructions, browser UI check and future-host
migration guidance are prose alternatives, not additional initial-deployment
steps. YAML and text blocks are configuration/examples, not executable R chunks.
No automatic package-management enablement, retry workaround, method mutation,
threshold change or server-side fixture is added. Book defects should fail visibly.

Local extraction without Docker or installation:

```sh
bash scripts/book-practice.sh --extract-only /tmp/book-practice-chunks
for script in scripts/book-practice.sh scripts/book-practice/publish-results.sh book/book-compose.sh /tmp/book-practice-chunks/commands.sh; do
  bash -n "$script" || exit
done
Rscript -e 'for (f in c(list.files("book", "[.]R$", full.names=TRUE), list.files("scripts/book-practice", "[.]R$", full.names=TRUE), list.files("/tmp/book-practice-chunks", "[.]R$", full.names=TRUE))) { parse(f); cat("PARSE OK:", f, "\n") }'
```

Successful local static checks do not constitute live Opal output. The final
runtime verdict and outputs are supplied by the dispatched workflow.
