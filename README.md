# dsOMOP on a real Opal, end to end

Private harness. One workflow (`dsomop-opal-e2e`, manual dispatch) brings up an easy-opal stack (Opal, Rock, MongoDB,
nginx) on a GitHub runner, a PostgreSQL OMOP CDM (OHDSI Eunomia GiBleed, CDM 5.3) on the stack's network, and runs:

- **fresh**: a clean Opal; dsOMOP installed through Opal's DataSHIELD package install (auto-published as a new
  package); publication check against the installed DESCRIPTION; the analyst's script; the method audit (scenario D).
- **upgrade**: dsOMOP `old_ref` installed first, then upgraded through the same install call (scenario A reproduces
  "No such DataSHIELD 'ASSIGN' method with name: omopInitDS"); scenario B publishes and retries.
- **scenario C** (both paths): resources created with dsOMOP 1.x's form (`omop.cdm.db`).

`mode=candidate` installs dsOMOP and dsOMOPClient from `pkgs/` instead of GitHub refs. Results are in the job
summary and in the `e2e-*` artifacts (`out/`).
