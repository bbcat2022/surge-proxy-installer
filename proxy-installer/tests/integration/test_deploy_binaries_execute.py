import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
EXEC=ROOT/'lib'/'orchestrators'/'deploy_binaries_execute.sh'

class DeployBinariesExecuteTests(unittest.TestCase):
 def test_failed_second_binary_restores_first_binary_and_mode(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); descriptor=root/'binaries'; rows=[]; first_active=None
   for protocol,script in [('snell','#!/usr/bin/env bash\necho v1.2.3\nexit 0\n'),('anytls','#!/usr/bin/env bash\necho v1.2.3\nexit 1\n')]:
    work=root/protocol; work.mkdir(); candidate=work/'candidate'; candidate.write_text(script); candidate.chmod(0o700)
    binary_id='snell-server' if protocol=='snell' else 'sing-box'
    (work/'metadata').write_text(f'binary_id={binary_id}\nversion=v1.2.3\nstability=stable\nrelease_date=2026-01-01\nplatform=linux-amd64\nsource=https://example.test/{protocol}\nsha256='+'a'*64+'\n')
    active=root/f'{protocol}-active'; active.write_text(f'old-{protocol}'); active.chmod(0o700)
    active_metadata=root/f'{protocol}-metadata'; active_metadata.write_text(f'old-metadata-{protocol}')
    rows.append(f'{protocol}|{work}|{active}|{root}/backup-{protocol}|{active_metadata}|{root}/backup-metadata-{protocol}')
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
   self.assertEqual((root/'snell-metadata').read_text(),'old-metadata-snell')

if __name__=='__main__': unittest.main()
