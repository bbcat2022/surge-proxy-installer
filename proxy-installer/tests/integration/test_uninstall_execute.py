import os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; EXEC=ROOT/'lib'/'orchestrators'/'uninstall_execute.sh'
class UninstallExecuteTests(unittest.TestCase):
 def run_case(self,health='ok'):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t); systemctl=p/'systemctl'; systemctl.write_text('#!/usr/bin/env bash\nexit 0\n'); systemctl.chmod(0o700)
   runtime=p/'runtime'; unit=p/'demo.service'; runtime.write_text('runtime'); unit.write_text('unit')
   body=f'''source "{EXEC}"
snapshot() {{ return 0; }}
health() {{ return {0 if health=='ok' else 1}; }}
commit() {{ return 0; }}
export_cb() {{ return 0; }}
uninstall_execute_materials "{p}/lock" op "{runtime}" "{unit}" demo.service "{p}/stash" snapshot health commit export_cb
code=$?; printf 'RESULT=%s' "$TX_RESULT"; exit "$code"
'''
   r=subprocess.run(['bash','-c',body],text=True,capture_output=True,env=dict(os.environ,SYSTEMCTL_BIN=str(systemctl)),check=False)
   exists=(runtime.exists(),unit.exists())
  return r,exists
 def test_success_stages_files_instead_of_deleting(self):
  r,exists=self.run_case(); self.assertEqual(r.returncode,0); self.assertIn('RESULT=success',r.stdout); self.assertEqual(exists,(False,False))
 def test_health_failure_restores_files(self):
  r,exists=self.run_case('fail'); self.assertNotEqual(r.returncode,0); self.assertIn('RESULT=rollback-success',r.stdout); self.assertEqual(exists,(True,True))
if __name__=='__main__': unittest.main()
