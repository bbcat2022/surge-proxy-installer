import subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
SNAPSHOT=ROOT/'lib'/'resources'/'snapshot.sh'

class SnapshotResourceTests(unittest.TestCase):
 def test_restores_prior_content(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); target=root/'target'; snapshot=root/'backup'; target.write_text('old')
   result=subprocess.run(['bash','-c',f'source "{SNAPSHOT}"; snapshot_capture_file "{target}" "{snapshot}" false; printf new > "{target}"; snapshot_restore_file "{target}" "{snapshot}" false'],text=True,capture_output=True,check=False)
   self.assertEqual(result.returncode,0,result.stderr); self.assertEqual(target.read_text(),'old')
 def test_restores_absence_by_removing_new_file(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); target=root/'target'; snapshot=root/'backup'
   result=subprocess.run(['bash','-c',f'source "{SNAPSHOT}"; snapshot_capture_file "{target}" "{snapshot}" false; printf new > "{target}"; snapshot_restore_file "{target}" "{snapshot}" false'],text=True,capture_output=True,check=False)
   self.assertEqual(result.returncode,0,result.stderr); self.assertFalse(target.exists())

if __name__=='__main__': unittest.main()
