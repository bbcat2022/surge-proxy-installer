import subprocess,tempfile,unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
EXEC=ROOT/'lib'/'orchestrators'/'update_execute.sh'
class UpdateExecuteTests(unittest.TestCase):
 def run_case(self,health='ok',export='ok'):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t); active=p/'active'; backup=p/'backup'; candidate=p/'candidate'; active_metadata=p/'active.metadata'; backup_metadata=p/'backup.metadata'; candidate_metadata=p/'candidate.metadata'
   active.write_text('old'); backup.write_text('#!/usr/bin/env bash\necho old\n'); candidate.write_text('#!/usr/bin/env bash\necho new v1.2.3\n')
   backup.chmod(0o700); candidate.chmod(0o700); active.chmod(0o700)
   metadata=lambda version: f'binary_id=server\nversion={version}\nstability=stable\nrelease_date=2026-01-01\nplatform=linux-amd64\nsource=https://example.test/server\nsha256='+'a'*64+'\n'
   active_metadata.write_text(metadata('v1.2.2')); backup_metadata.write_text(metadata('v1.2.2')); candidate_metadata.write_text(metadata('v1.2.3'))
   body=f'''source "{EXEC}"
snapshot() {{ return 0; }}
health() {{ return {0 if health=='ok' else 1}; }}
commit() {{ return 0; }}
export_cb() {{ return {0 if export=='ok' else 1}; }}
update_execute_binary "{p}/lock" op "{candidate}" "{active}" "{backup}" --version v1.2.3 "{candidate_metadata}" "{active_metadata}" "{backup_metadata}" snapshot health commit export_cb
code=$?; printf 'RESULT=%s' "$TX_RESULT"; exit "$code"
'''
   r=subprocess.run(['bash','-c',body],text=True,capture_output=True,check=False)
   content=active.read_text(); metadata_version=next(line.split('=',1)[1] for line in active_metadata.read_text().splitlines() if line.startswith('version='))
  return r,content,metadata_version
 def test_update_success_replaces_active_binary(self):
  r,c,v=self.run_case(); self.assertEqual(r.returncode,0); self.assertIn('RESULT=success',r.stdout); self.assertIn('echo new',c); self.assertEqual(v,'v1.2.3')
 def test_health_failure_restores_backup_binary(self):
  r,c,v=self.run_case(health='fail'); self.assertNotEqual(r.returncode,0); self.assertIn('RESULT=rollback-success',r.stdout); self.assertIn('echo old',c); self.assertEqual(v,'v1.2.2')
 def test_export_failure_is_partial_success(self):
  r,c,v=self.run_case(export='fail'); self.assertEqual(r.returncode,0); self.assertIn('RESULT=partial-success',r.stdout); self.assertIn('echo new',c); self.assertEqual(v,'v1.2.3')

 def test_update_rejects_metadata_for_another_resource_before_changes(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t); active=p/'active'; backup=p/'backup'; candidate=p/'candidate'; active_metadata=p/'active.metadata'; candidate_metadata=p/'candidate.metadata'; backup_metadata=p/'backup.metadata'
   active.write_text('old'); backup.write_text('old'); candidate.write_text('#!/usr/bin/env bash\necho v1.2.3\n'); candidate.chmod(0o700)
   base='version=v1.2.3\nstability=stable\nrelease_date=2026-01-01\nplatform=linux-amd64\nsource=https://example.test/server\nsha256='+'a'*64+'\n'
   active_metadata.write_text('binary_id=server\n'+base.replace('v1.2.3','v1.2.2')); backup_metadata.write_text(active_metadata.read_text()); candidate_metadata.write_text('binary_id=other\n'+base)
   body=f'''source "{EXEC}"
ok() {{ return 0; }}
update_execute_binary "{p}/lock" op "{candidate}" "{active}" "{backup}" --version v1.2.3 "{candidate_metadata}" "{active_metadata}" "{backup_metadata}" ok ok ok ok
'''
   result=subprocess.run(['bash','-c',body],text=True,capture_output=True,check=False); content=active.read_text()
  self.assertNotEqual(result.returncode,0); self.assertEqual(content,'old')
if __name__=='__main__': unittest.main()
