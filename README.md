# dsOMOP on a real Opal, end to end

Private harness. Two manual workflows; results come back as `results/<run>-<path>-<mode>` (e2e) and
`results/<run>-vendor-candidate` (vendor) branches, plus the job summary.

**`e2e.yml` (`dsomop-opal-e2e`)** brings up an easy-opal stack (Opal, Rock, MongoDB, nginx) on a GitHub runner, a
PostgreSQL OMOP CDM (OHDSI Eunomia GiBleed, CDM 5.3) on the stack's network, and runs:

- **fresh**: a clean Opal; dsOMOP installed through Opal's DataSHIELD package install; publication check against the
  installed DESCRIPTION; the analyst's script.
- **upgrade**: dsOMOP `old_ref` installed first, then upgraded through the same install call. With a 1.x `old_ref`,
  scenario A reproduces "No such DataSHIELD 'ASSIGN' method with name: omopInitDS"; with a 2.x `old_ref` (2.10.2) the
  old server's noise root is created and the new client is run against that real old server
  (`scripts/combo_old_server.R`, V checks) before the upgrade. Scenario B publishes and retries.
- **C** (both paths): resources created with dsOMOP 1.x's form (`omop.cdm.db`). **D** (fresh): the method audit, every
  method of the installed DESCRIPTION. **E** (fresh): recipes. **F** (fresh, last): the RPostgreSQL fallback.
- **G** (both paths): the 2.10.3 checks that need a real Opal/Rock (`scripts/scenario_G.R`; each check states its
  expected result; verdicts in `<path>-G-verdicts.csv`), then the released 2.10.2 client against this server
  (`scripts/scenario_G_old.R`). On the fresh path G16 also builds a synthetic CDM of `big_persons` persons.

`mode=candidate` installs dsOMOP and dsOMOPClient from `pkgs/`.

**`vendor.yml` (`dsomop-vendor-db`)** runs dsOMOP's vendor database CI (PostgreSQL 16, MySQL 8.4, MariaDB 11.4, the
same pinned images and test call as dsOMOP's `vendor-db-integration.yaml`) on `pkgs/dsOMOP`, plus the protected
release routes (`test-vendor-release-routes.R`) on the same servers.

Rerun on a new candidate head:

```sh
REF=<branch or commit> scripts/vendor.sh /workspace/dsomop     # git archive of each committed branch into pkgs/
git add pkgs && git commit -m "Vendor ..." -- pkgs && git push
gh workflow run e2e.yml -f mode=candidate -f old_ref=2.10.2 -f scenarios="C D E F G"
gh workflow run vendor.yml
```
