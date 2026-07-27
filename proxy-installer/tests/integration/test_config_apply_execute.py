import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
EXEC=ROOT/'lib'/'orchestrators'/'config_apply_execute.sh'

class ConfigApplyExecuteTests(unittest.TestCase):
 def run_case(self, runtime_changed=True, health=True, firewall=False):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t); mock=p/'systemctl'; mock.write_text('#!/usr/bin/env bash\nexit 0\n'); mock.chmod(0o700)
   for name,text in {'runtime-new':'new','runtime-old':'old','unit-new':'new unit','unit-old':'old unit','entry':'Node = snell, x, 443, psk=test, version=6\n'}.items(): (p/name).write_text(text)
   runtime=p/'runtime'; runtime.write_text('old'); units=p/'units'; units.mkdir(); (units/'demo.service').write_text('old unit')
   firewall_functions=''
   firewall_env=''
   if firewall:
    calls=p/'firewall-calls'
    firewall_functions=f'''firewall_apply() {{ printf apply >> "{calls}"; }}
firewall_rollback() {{ printf rollback >> "{calls}"; }}
'''
    firewall_env='CONFIG_FIREWALL_APPLY=firewall_apply CONFIG_FIREWALL_ROLLBACK=firewall_rollback '
   body=f'''source "{EXEC}"
snapshot() {{ return 0; }}
health() {{ return {0 if health else 1}; }}
commit() {{ return 0; }}
{firewall_functions}
{firewall_env}config_apply_execute "{p/'lock'}" config-op {str(runtime_changed).lower()} "{p/'runtime-new'}" "{runtime}" "{p/'runtime-old'}" "{units}" demo.service "{p/'unit-new'}" "{p/'unit-old'}" "{p/'export'/'surge.conf'}" "{p/'entry'}" unused unused snapshot health commit
code=$?
printf 'RESULT=%s' "$TX_RESULT"
exit "$code"'''
   r=subprocess.run(['bash','-c',body],text=True,capture_output=True,env=dict(os.environ,SYSTEMCTL_BIN=str(mock)))
   calls_content=(p/'firewall-calls').read_text() if firewall and (p/'firewall-calls').exists() else ''
   return r,runtime.read_text(),(units/'demo.service').read_text(),(p/'export'/'surge.conf').exists(),calls_content
 def test_server_change_updates_runtime_unit_and_export(self):
  r,runtime,unit,exported,_=self.run_case()
  self.assertEqual(r.returncode,0,r.stderr); self.assertIn('RESULT=success',r.stdout); self.assertEqual(runtime,'new'); self.assertEqual(unit,'new unit'); self.assertTrue(exported)
 def test_health_failure_restores_server_material(self):
  r,runtime,unit,_,_=self.run_case(health=False)
  self.assertNotEqual(r.returncode,0); self.assertIn('RESULT=rollback-success',r.stdout); self.assertEqual(runtime,'old'); self.assertEqual(unit,'old unit')
 def test_client_only_change_exports_without_touching_server_material(self):
  r,runtime,unit,exported,_=self.run_case(runtime_changed=False)
  self.assertEqual(r.returncode,0,r.stderr); self.assertEqual(runtime,'old'); self.assertEqual(unit,'old unit'); self.assertTrue(exported)
 def test_network_change_rolls_back_firewall_callback(self):
  r,_,_,_,calls=self.run_case(health=False,firewall=True)
  self.assertNotEqual(r.returncode,0); self.assertEqual(calls,'applyrollback')

if __name__=='__main__': unittest.main()
