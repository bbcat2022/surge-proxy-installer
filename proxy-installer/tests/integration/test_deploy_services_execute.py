import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
EXEC=ROOT/'lib'/'orchestrators'/'deploy_services_execute.sh'

class DeployServicesExecuteTests(unittest.TestCase):
 def run_case(self, healthy=True, existing=True, active='active', enabled='enabled', fail_action='', firewall_mode=''):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); calls=root/'calls'; mock=root/'systemctl'
   mock.write_text(
    '#!/usr/bin/env bash\n'
    'printf "%s\\n" "$*" >> "$MOCK_CALLS"\n'
    '[ -n "${MOCK_FAIL_ACTION:-}" ] && [ "$1" = "$MOCK_FAIL_ACTION" ] && exit 1\n'
    '[ "$1" = is-active ] && { printf "%s" "$MOCK_ACTIVE"; [ "$MOCK_ACTIVE" = active ]; exit $?; }\n'
    '[ "$1" = is-enabled ] && { printf "%s" "$MOCK_ENABLED"; [ "$MOCK_ENABLED" = enabled ]; exit $?; }\n'
    'exit 0\n'
   ); mock.chmod(0o700)
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
   firewall_context=root/'firewall.context'; firewall_calls=root/'firewall-calls'; firewall_env={}
   if firewall_mode:
    firewall_descriptor=root/'firewall.descriptor'; firewall_descriptor.write_text('schema=1\nrule=tcp:443\n')
    ufw=root/'ufw'; ufw.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$FIREWALL_CALLS"\n'); ufw.chmod(0o700)
    firewall_env=dict(DEPLOY_FIREWALL_DESCRIPTOR=str(firewall_descriptor),DEPLOY_FIREWALL_CONTEXT=str(firewall_context),DEPLOY_FIREWALL_MODE=firewall_mode,DEPLOY_FIREWALL_TOOL='ufw',UFW_BIN=str(ufw),FIREWALL_CALLS=str(firewall_calls))
   entry_args=' '.join(f'"{entry}"' for entry in entries)
   body=f'''source "{EXEC}"
snapshot() {{ return 0; }}
health() {{ {"return 0" if healthy else "return 1"}; }}
commit() {{ return 0; }}
history() {{ return 0; }}
deploy_services_execute "{lock}" deploy "{descriptor}" "{exported}" {entry_args} -- snapshot health commit history
code=$?; printf 'RESULT=%s' "$TX_RESULT"; exit "$code"
'''
   result=subprocess.run(
    ['bash','-c',body],text=True,capture_output=True,
    env=dict(os.environ,SYSTEMCTL_BIN=str(mock),MOCK_CALLS=str(calls),MOCK_ACTIVE=active,MOCK_ENABLED=enabled,MOCK_FAIL_ACTION=fail_action,**firewall_env),
    check=False
   )
   values=[(runtime.read_text() if runtime.exists() else None,unit.read_text() if unit.exists() else None,protocol) for runtime,unit,protocol in runtimes]
   firewall_result=(firewall_context.read_text() if firewall_context.exists() else '',firewall_calls.read_text().splitlines() if firewall_calls.exists() else [])
   return result,values,exported.exists(),calls.read_text().splitlines() if calls.exists() else [],firewall_result
 def test_applies_all_services_and_exports_once(self):
  result,values,exported,_,_=self.run_case(True)
  self.assertEqual(result.returncode,0,result.stderr); self.assertIn('RESULT=success',result.stdout); self.assertEqual(values,[('new-snell','new-snell','snell'),('new-anytls','new-anytls','anytls')]); self.assertTrue(exported)
 def test_health_failure_restores_all_services(self):
  result,values,exported,_,_=self.run_case(False)
  self.assertNotEqual(result.returncode,0); self.assertIn('RESULT=rollback-success',result.stdout); self.assertEqual(values,[('old-snell','old-snell','snell'),('old-anytls','old-anytls','anytls')]); self.assertFalse(exported)
 def test_health_failure_removes_initial_service_materials(self):
  result,values,exported,calls,_=self.run_case(False,existing=False,active='inactive',enabled='not-found')
  self.assertNotEqual(result.returncode,0); self.assertIn('RESULT=rollback-success',result.stdout); self.assertEqual(values,[(None,None,'snell'),(None,None,'anytls')]); self.assertFalse(exported)
  rollback_reload=max(index for index,call in enumerate(calls) if call == 'daemon-reload')
  self.assertLess(calls.index('stop snell.service'),rollback_reload)
  self.assertLess(calls.index('disable anytls.service'),rollback_reload)
 def test_rollback_restores_inactive_disabled_state(self):
  result,values,exported,calls,_=self.run_case(False,active='inactive',enabled='disabled')
  self.assertNotEqual(result.returncode,0); self.assertIn('RESULT=rollback-success',result.stdout)
  self.assertEqual(values,[('old-snell','old-snell','snell'),('old-anytls','old-anytls','anytls')]); self.assertFalse(exported)
  self.assertGreaterEqual(calls.count('disable snell.service'),1); self.assertGreaterEqual(calls.count('stop snell.service'),1)
  self.assertGreaterEqual(calls.count('disable anytls.service'),1); self.assertGreaterEqual(calls.count('stop anytls.service'),1)
 def test_rollback_attempts_every_service_and_marks_restore_failure_dirty(self):
  result,values,exported,calls,_=self.run_case(False,active='inactive',enabled='disabled',fail_action='disable')
  self.assertNotEqual(result.returncode,0); self.assertIn('RESULT=dirty',result.stdout); self.assertFalse(exported)
  self.assertIn('disable snell.service',calls); self.assertIn('disable anytls.service',calls)
  self.assertIn('stop snell.service',calls); self.assertIn('stop anytls.service',calls)
 def test_auto_firewall_is_part_of_service_transaction_and_dirty_if_later_health_fails(self):
  result,values,exported,_,firewall=self.run_case(False,firewall_mode='auto')
  context,calls=firewall
  self.assertNotEqual(result.returncode,0); self.assertIn('RESULT=dirty',result.stdout); self.assertFalse(exported)
  self.assertEqual(values,[('old-snell','old-snell','snell'),('old-anytls','old-anytls','anytls')])
  self.assertEqual(calls,['allow 443/tcp']); self.assertIn('processed_rule=tcp:443',context)
  self.assertIn('manual-firewall-review=tcp:443',result.stderr)

if __name__=='__main__': unittest.main()
