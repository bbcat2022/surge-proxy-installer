import subprocess,tempfile,unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
EXEC=ROOT/'lib'/'orchestrators'/'update_execute.sh'
class UpdateExecuteTests(unittest.TestCase):
 def run_case(self,health='ok',export='ok'):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t); active=p/'active'; backup=p/'backup'; candidate=p/'candidate'
   active.write_text('old'); backup.write_text('#!/usr/bin/env bash\necho old\n'); candidate.write_text('#!/usr/bin/env bash\necho new v1.2.3\n')
   backup.chmod(0o700); candidate.chmod(0o700); active.chmod(0o700)
   body=f'''source "{EXEC}"
snapshot() {{ return 0; }}
health() {{ return {0 if health=='ok' else 1}; }}
commit() {{ return 0; }}
export_cb() {{ return {0 if export=='ok' else 1}; }}
update_execute_binary "{p}/lock" op "{candidate}" "{active}" "{backup}" --version v1.2.3 snapshot health commit export_cb
code=$?; printf 'RESULT=%s' "$TX_RESULT"; exit "$code"
'''
   r=subprocess.run(['bash','-c',body],text=True,capture_output=True,check=False)
   content=active.read_text()
  return r,content
 def test_update_success_replaces_active_binary(self):
  r,c=self.run_case(); self.assertEqual(r.returncode,0); self.assertIn('RESULT=success',r.stdout); self.assertIn('echo new',c)
 def test_health_failure_restores_backup_binary(self):
  r,c=self.run_case(health='fail'); self.assertNotEqual(r.returncode,0); self.assertIn('RESULT=rollback-success',r.stdout); self.assertIn('echo old',c)
 def test_export_failure_is_partial_success(self):
  r,c=self.run_case(export='fail'); self.assertEqual(r.returncode,0); self.assertIn('RESULT=partial-success',r.stdout); self.assertIn('echo new',c)
if __name__=='__main__': unittest.main()
