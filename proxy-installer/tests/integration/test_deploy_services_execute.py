import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
EXEC=ROOT/'lib'/'orchestrators'/'deploy_services_execute.sh'

class DeployServicesExecuteTests(unittest.TestCase):
 def run_case(self, healthy=True, existing=True):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); mock=root/'systemctl'; mock.write_text('#!/usr/bin/env bash\nexit 0\n'); mock.chmod(0o700)
   descriptor=root/'services'; units=root/'units'; units.mkdir(); entries=[]; rows=[]; runtimes=[]
   for protocol in ('snell','anytls'):
    runtime_new=root/f'{protocol}.new'; runtime_old=root/f'{protocol}.old'; target=root/f'{protocol}.runtime'
    unit_new=root/f'{protocol}.unit.new'; unit_old=root/f'{protocol}.unit.old'; unit_name=f'{protocol}.service'; entry=root/f'{protocol}.surge'
    runtime_new.write_text(f'new-{protocol}'); runtime_old.write_text(f'backup-{protocol}')
    unit_new.write_text(f'new-{protocol}'); unit_old.write_text(f'backup-{protocol}')
    if existing: target.write_text(f'old-{protocol}'); (units/unit_name).write_text(f'old-{protocol}')
    entry.write_text(f'{protocol} = snell, node.example.com, 443, psk=test, version=6\n')
    rows.append('|'.join(map(str,[protocol,runtime_new,target,runtime_old,units,unit_name,unit_new,unit_old]))); entries.append(entry); runtimes.append((target,units/unit_name,protocol))
   descriptor.write_text('\n'.join(rows)+'\n'); lock=root/'lock'; exported=root/'export'/'surge.conf'
   entry_args=' '.join(f'"{entry}"' for entry in entries)
   body=f'''source "{EXEC}"
snapshot() {{ return 0; }}
health() {{ {"return 0" if healthy else "return 1"}; }}
commit() {{ return 0; }}
history() {{ return 0; }}
deploy_services_execute "{lock}" deploy "{descriptor}" "{exported}" {entry_args} -- snapshot health commit history
code=$?; printf 'RESULT=%s' "$TX_RESULT"; exit "$code"
'''
   result=subprocess.run(['bash','-c',body],text=True,capture_output=True,env=dict(os.environ,SYSTEMCTL_BIN=str(mock)),check=False)
   values=[(runtime.read_text() if runtime.exists() else None,unit.read_text() if unit.exists() else None,protocol) for runtime,unit,protocol in runtimes]
   return result,values,exported.exists()
 def test_applies_all_services_and_exports_once(self):
  result,values,exported=self.run_case(True)
  self.assertEqual(result.returncode,0,result.stderr); self.assertIn('RESULT=success',result.stdout); self.assertEqual(values,[('new-snell','new-snell','snell'),('new-anytls','new-anytls','anytls')]); self.assertTrue(exported)
 def test_health_failure_restores_all_services(self):
  result,values,exported=self.run_case(False)
  self.assertNotEqual(result.returncode,0); self.assertIn('RESULT=rollback-success',result.stdout); self.assertEqual(values,[('old-snell','old-snell','snell'),('old-anytls','old-anytls','anytls')]); self.assertFalse(exported)
 def test_health_failure_removes_initial_service_materials(self):
  result,values,exported=self.run_case(False,existing=False)
  self.assertNotEqual(result.returncode,0); self.assertIn('RESULT=rollback-success',result.stdout); self.assertEqual(values,[(None,None,'snell'),(None,None,'anytls')]); self.assertFalse(exported)

if __name__=='__main__': unittest.main()
