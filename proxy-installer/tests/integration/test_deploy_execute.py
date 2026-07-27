import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
EXEC=ROOT/'lib'/'orchestrators'/'deploy_execute.sh'
class DeployExecuteTests(unittest.TestCase):
 def run_case(self,health='ok',export=True,firewall=False):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t); mock=p/'systemctl'; mock.write_text('#!/usr/bin/env bash\nexit 0\n'); mock.chmod(0o700)
   files={}
   for name,text in {'runtime-new':'new-runtime','runtime-old':'old-runtime','unit-new':'new-unit','unit-old':'old-unit','entry':'Node = snell, x, 443, psk=test, version=6\n'}.items():
    f=p/name; f.write_text(text); files[name]=f
   target=p/'runtime'; target.write_text('old-runtime'); unit_dir=p/'units'; unit_dir.mkdir(); (unit_dir/'demo.service').write_text('old-unit')
   export_target=p/'export'/'surge.conf'; lock=p/'lock'
   entry=files['entry'] if export else p/'missing'
   firewall_functions=''
   firewall_env=''
   if firewall:
    calls=p/'firewall-calls'
    firewall_functions=f'''firewall_apply() {{ printf apply >> "{calls}"; }}
firewall_rollback() {{ printf rollback >> "{calls}"; }}
'''
    firewall_env='DEPLOY_FIREWALL_APPLY=firewall_apply DEPLOY_FIREWALL_ROLLBACK=firewall_rollback '
   body=f'''source "{EXEC}"
snapshot() {{ return 0; }}
health() {{ {('return 0' if health=='ok' else 'return 1')}; }}
commit() {{ return 0; }}
{firewall_functions}
{firewall_env}deploy_execute_materials "{lock}" op "{files['runtime-new']}" "{target}" "{files['runtime-old']}" "{unit_dir}" demo.service "{files['unit-new']}" "{files['unit-old']}" "{export_target}" "{entry}" unused snapshot health commit
code=$?
printf 'RESULT=%s' "$TX_RESULT"
exit "$code"
'''
   env=dict(os.environ,SYSTEMCTL_BIN=str(mock))
   r=subprocess.run(['bash','-c',body],text=True,capture_output=True,env=env,check=False)
   calls_content=(p/'firewall-calls').read_text() if firewall and (p/'firewall-calls').exists() else ''
   return r,target.read_text(),(unit_dir/'demo.service').read_text(),calls_content
 def test_success_applies_materials_and_exports(self):
  r,runtime,unit,_=self.run_case()
  self.assertEqual(r.returncode,0,r.stderr); self.assertIn('RESULT=success',r.stdout); self.assertEqual(runtime,'new-runtime'); self.assertIn('new-unit',unit)
 def test_health_failure_restores_runtime_and_unit(self):
  r,runtime,unit,_=self.run_case(health='fail')
  self.assertNotEqual(r.returncode,0); self.assertIn('RESULT=rollback-success',r.stdout); self.assertEqual(runtime,'old-runtime'); self.assertIn('old-unit',unit)
 def test_export_failure_is_partial_success_without_rollback(self):
  r,runtime,unit,_=self.run_case(export=False)
  self.assertEqual(r.returncode,0); self.assertIn('RESULT=partial-success',r.stdout); self.assertEqual(runtime,'new-runtime')
 def test_firewall_callback_is_rolled_back_with_deployment(self):
  r,_,_,calls=self.run_case(health='fail',firewall=True)
  self.assertNotEqual(r.returncode,0); self.assertEqual(calls,'applyrollback')
if __name__=='__main__': unittest.main()
