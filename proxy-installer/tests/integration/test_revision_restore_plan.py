import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
PLANNER=ROOT/'lib'/'orchestrators'/'revision_restore.sh'
class RevisionRestorePlanTests(unittest.TestCase):
 def run_plan(self,e): return subprocess.run(['bash','-c',f'source "{PLANNER}"; {e}'],text=True,capture_output=True,check=False)
 def test_valid_revision_requires_full_transaction_restore(self):
  with tempfile.TemporaryDirectory() as temp:
   root=Path(temp); revision=root/'revisions'/'r1'; revision.mkdir(parents=True); (revision/'config.yaml').write_text('schema_version: 1\n',encoding='utf-8')
   r=self.run_plan(f'revision_restore_plan "{root}" r1')
  self.assertEqual(r.returncode,0); self.assertIn('snapshot-current=true',r.stdout); self.assertIn('commit-new-revision=true',r.stdout)
 def test_missing_or_unsafe_revision_is_rejected(self):
  with tempfile.TemporaryDirectory() as temp:
   self.assertNotEqual(self.run_plan(f'revision_restore_plan "{temp}" ../bad').returncode,0)
   self.assertNotEqual(self.run_plan(f'revision_restore_plan "{temp}" missing').returncode,0)
if __name__=='__main__': unittest.main()
