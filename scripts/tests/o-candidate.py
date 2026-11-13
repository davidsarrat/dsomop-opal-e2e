"""Preflight must accept the coordinated backport and reject incomplete sources."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("candidate", "scripts/o/check_candidate.py")
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)

class CandidateTests(unittest.TestCase):
    def test_integrated_checkout(self):
        self.assertEqual(candidate.check_candidate(), "2.10.3")

    def test_mismatch_old_and_incomplete_candidates(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for package in ("dsOMOP", "dsOMOPClient"):
                pkg = root / package
                (pkg / "R").mkdir(parents=True)
                (pkg / "DESCRIPTION").write_text("Version: 2.10.3\n")
                for file in ("plan_normalize_v2.R", "concept_labels.R"):
                    (pkg / "R" / file).touch()
            fixtures = root / "dsOMOP/tests/fixtures"
            fixtures.mkdir(parents=True)
            for file in ("create_reach_db.R", "extend_reach_db.R", "load_reach_pg.R"):
                (fixtures / file).touch()
            plans = root / "dsOMOP/inst/plans/acceptance"
            for n in range(15):
                (plans / str(n)).mkdir(parents=True)
                (plans / str(n) / "plan.json").touch()
            self.assertEqual(candidate.check_candidate(root), "2.10.3")
            desc = root / "dsOMOPClient/DESCRIPTION"
            desc.write_text("Version: 2.10.4\n")
            with self.assertRaisesRegex(SystemExit, "versions differ"):
                candidate.check_candidate(root)
            for package in ("dsOMOP", "dsOMOPClient"):
                (root / package / "DESCRIPTION").write_text("Version: 2.10.2\n")
            with self.assertRaisesRegex(SystemExit, "integrated native-language"):
                candidate.check_candidate(root)
            for package in ("dsOMOP", "dsOMOPClient"):
                (root / package / "DESCRIPTION").write_text("Version: 2.10.4\n")
            self.assertEqual(candidate.check_candidate(root), "2.10.4")
            (plans / "14/plan.json").unlink()
            with self.assertRaisesRegex(SystemExit, "15 frozen"):
                candidate.check_candidate(root)
            (plans / "14/plan.json").touch()
            (root / "dsOMOP/R/plan_normalize_v2.R").unlink()
            with self.assertRaisesRegex(SystemExit, "Missing integrated source"):
                candidate.check_candidate(root)

if __name__ == "__main__":
    unittest.main()
