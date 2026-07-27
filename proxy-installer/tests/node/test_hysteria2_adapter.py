import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADAPTER = ROOT / "lib" / "adapters" / "hysteria2.sh"
PASSWORD = "hy2Pass_123456"; GECKO = "geckoPass_123456"
class Hysteria2AdapterTests(unittest.TestCase):
 def run_adapter(self, exp): return subprocess.run(["bash","-c",f'source "{ADAPTER}"; {exp}'],text=True,capture_output=True,check=False)
 def test_runtime_gecko_fixed_parameters(self):
  r=self.run_adapter(f'hy2_build_runtime 443 {PASSWORD} node.example.com /cert /key 20000-50000 30 true {GECKO}')
  self.assertEqual(r.returncode,0); self.assertIn('minPacketSize: 512',r.stdout); self.assertIn('maxPacketSize: 1200',r.stdout); self.assertIn('type: gecko',r.stdout)
 def test_surge_and_resources_use_udp_range(self):
  s=self.run_adapter(f'hy2_build_surge_entry HY2 443 {PASSWORD} node.example.com 20000-50000 30 true {GECKO} 100')
  q=self.run_adapter('hy2_resource_requirements 443 20000-50000')
  self.assertIn('port-hopping=20000-50000',s.stdout); self.assertIn('gecko-password=',s.stdout); self.assertIn('network=udp:443',q.stdout); self.assertIn('network=udp-range:20000-50000',q.stdout)
 def test_main_port_inside_range_and_missing_gecko_secret_rejected(self):
  self.assertNotEqual(self.run_adapter(f'hy2_build_runtime 20001 {PASSWORD} node.example.com /cert /key 20000-50000 30 true {GECKO}').returncode,0)
  self.assertNotEqual(self.run_adapter(f'hy2_build_runtime 443 {PASSWORD} node.example.com /cert /key '' 30 true short').returncode,0)
 def test_config_patch_preserves_gecko_switch(self):
  r=self.run_adapter(f'hy2_build_config_patch 443 {PASSWORD} node.example.com 20000-50000 30 true {GECKO} 100')
  self.assertEqual(r.returncode,0,r.stderr); self.assertIn('"gecko":true',r.stdout)
if __name__=='__main__': unittest.main()
