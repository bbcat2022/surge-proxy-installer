import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
EXEC=ROOT/'lib'/'orchestrators'/'deploy_binaries_execute.sh'

class DeployBinariesExecuteTests(unittest.TestCase):
 def test_failed_second_binary_restores_first_binary_and_mode(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); descriptor=root/'binaries'; rows=[]; first_active=None
   for protocol,script in [('snell','#!/usr/bin/env bash\nexit 0\n'),('anytls','#!/usr/bin/env bash\nexit 1\n')]:
    work=root/protocol; work.mkdir(); candidate=work/'candidate'; candidate.write_text(script); candidate.chmod(0o700)
    active=root/f'{protocol}-active'; active.write_text(f'old-{protocol}'); active.chmod(0o700)
    rows.append(f'{protocol}|{work}|{active}|{root}/backup-{protocol}')
    if protocol=='snell': first_active=active
   descriptor.write_text('\n'.join(rows)+'\n'); lock=root/'lock'
   body=f'''source "{EXEC}"
snapshot() {{ return 0; }}
health() {{ return 0; }}
commit() {{ return 0; }}
history() {{ return 0; }}
deploy_binaries_execute "{lock}" binaries "{descriptor}" snapshot health commit history
code=$?; printf 'RESULT=%s' "$TX_RESULT"; exit "$code"
'''
   result=subprocess.run(['bash','-c',body],text=True,capture_output=True,env=dict(os.environ),check=False)
   self.assertNotEqual(result.returncode,0); self.assertIn('RESULT=rollback-success',result.stdout); self.assertEqual(first_active.read_text(),'old-snell'); self.assertEqual(first_active.stat().st_mode & 0o777,0o700)

if __name__=='__main__': unittest.main()
