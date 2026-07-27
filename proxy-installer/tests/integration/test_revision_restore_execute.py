import os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; EXEC=ROOT/'lib'/'orchestrators'/'revision_restore_execute.sh'; PACKAGES=ROOT.parent/'.python-packages'
S=lambda rev: f'schema_version: 1\nconfig_revision: {rev}\ndesired: {{}}\napplied: {{}}\nobserved: {{}}\nhistory: {{}}\n'
class RevisionRestoreExecuteTests(unittest.TestCase):
 def run_case(self,health='ok'):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t); config=p/'config'; current=p/'current'; target=p/'target'; config.write_text(S(2)); current.write_text(S(2)); target.write_text(S(1))
   body=f'''source "{EXEC}"
snapshot() {{ return 0; }}
health() {{ return {0 if health=='ok' else 1}; }}
commit() {{ return 0; }}
export_cb() {{ return 0; }}
history() {{ return 0; }}
revision_restore_execute "{p}/lock" op "{config}" "{current}" "{target}" snapshot health commit export_cb history
code=$?; printf 'RESULT=%s' "$TX_RESULT"; exit "$code"
'''
   r=subprocess.run(['bash','-c',body],text=True,capture_output=True,env=dict(os.environ,PYTHONPATH=str(PACKAGES)),check=False); data=config.read_text()
  return r,data
 def test_success_restores_target_revision(self):
  r,d=self.run_case(); self.assertEqual(r.returncode,0); self.assertIn('RESULT=success',r.stdout); self.assertIn('config_revision: 1',d)
 def test_health_failure_restores_current_revision(self):
  r,d=self.run_case('fail'); self.assertNotEqual(r.returncode,0); self.assertIn('RESULT=rollback-success',r.stdout); self.assertIn('config_revision: 2',d)
if __name__=='__main__': unittest.main()
