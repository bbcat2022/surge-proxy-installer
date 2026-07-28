import subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; PATHS=ROOT/'lib'/'orchestrators'/'deploy_paths.sh'
class DeployPathsTests(unittest.TestCase):
 def test_creates_private_new_absolute_transaction_workdir(self):
  with tempfile.TemporaryDirectory() as t:
   state=Path(t)/'state'
   r=subprocess.run(['bash','-c',f'source "{PATHS}"; deploy_paths_prepare_workdir "{state}" deploy-1'],text=True,capture_output=True,check=False)
   work=Path(r.stdout.strip())
  self.assertEqual(r.returncode,0,r.stderr); self.assertEqual(work.name,'deploy-1')
 def test_rejects_relative_or_reused_workdir(self):
  with tempfile.TemporaryDirectory() as t:
   state=Path(t)/'state'; state.mkdir()
   bad=subprocess.run(['bash','-c',f'source "{PATHS}"; deploy_paths_prepare_workdir state x'],check=False)
   first=subprocess.run(['bash','-c',f'source "{PATHS}"; deploy_paths_prepare_workdir "{state}" x'],check=False)
   second=subprocess.run(['bash','-c',f'source "{PATHS}"; deploy_paths_prepare_workdir "{state}" x'],check=False)
  self.assertNotEqual(bad.returncode,0); self.assertEqual(first.returncode,0); self.assertNotEqual(second.returncode,0)
if __name__=='__main__': unittest.main()
