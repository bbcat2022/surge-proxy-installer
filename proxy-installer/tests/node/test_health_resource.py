import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
HEALTH=ROOT/'lib'/'resources'/'health.sh'
class HealthResourceTests(unittest.TestCase):
 def run_health(self,body,env): return subprocess.run(['bash','-c',f'source "{HEALTH}"; {body}'],text=True,capture_output=True,env=env,check=False)
 def test_active_version_and_correct_transport_listener_required(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t)
   for name,body in {'systemctl':'#!/usr/bin/env bash\nexit 0\n','binary':'#!/usr/bin/env bash\nexit 0\n','ss':'#!/usr/bin/env bash\n[ "$1" = "-ltn" ] && printf "x x x 0.0.0.0:443\\n" || printf "x x x 0.0.0.0:8443\\n"\n'}.items():
    f=p/name; f.write_text(body); f.chmod(0o700)
   env=dict(os.environ,SYSTEMCTL_BIN=str(p/'systemctl'),SS_BIN=str(p/'ss'))
   tcp=self.run_health(f'health_verify demo.service tcp 443 "{p}/binary" --version',env)
   udp=self.run_health(f'health_verify demo.service udp 443 "{p}/binary" --version',env)
   self.assertEqual(tcp.returncode,0); self.assertNotEqual(udp.returncode,0)
 def test_optional_recent_logs_are_part_of_health_gate(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t)
   for name,body in {'systemctl':'#!/usr/bin/env bash\nexit 0\n','binary':'#!/usr/bin/env bash\nexit 0\n','ss':'#!/usr/bin/env bash\nprintf "x x x 0.0.0.0:443\\n"\n','journal':'#!/usr/bin/env bash\nexit 1\n'}.items():
    f=p/name; f.write_text(body); f.chmod(0o700)
   env=dict(os.environ,SYSTEMCTL_BIN=str(p/'systemctl'),SS_BIN=str(p/'ss'),JOURNALCTL_BIN=str(p/'journal'))
   result=self.run_health(f'health_verify demo.service tcp 443 "{p}/binary" --version 20',env)
  self.assertNotEqual(result.returncode,0)
if __name__=='__main__': unittest.main()
