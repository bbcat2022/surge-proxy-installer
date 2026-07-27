import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEPLOY = ROOT / "lib" / "orchestrators" / "deploy.sh"

class DeployPlanTests(unittest.TestCase):
 def run_plan(self, expression): return subprocess.run(["bash","-c",f'source "{DEPLOY}"; {expression}'],text=True,capture_output=True,check=False)
 def test_snell_only_skips_certificate(self):
  r=self.run_plan('deploy_build_plan snell 443 8443 8444 ""')
  self.assertEqual(r.returncode,0); self.assertIn('certificate=not-required',r.stdout); self.assertIn('network=tcp:443',r.stdout)
 def test_tls_combination_uses_shared_certificate_and_udp_range(self):
  r=self.run_plan('deploy_build_plan anytls,hysteria2 443 8443 8444 20000-50000')
  self.assertEqual(r.returncode,0); self.assertIn('certificate=shared-main-domain',r.stdout); self.assertIn('network=tcp:8443',r.stdout); self.assertIn('network=udp:8444',r.stdout); self.assertIn('network=udp-range:20000-50000',r.stdout)
 def test_conflicting_tcp_port_and_invalid_hy2_range_rejected(self):
  self.assertNotEqual(self.run_plan('deploy_build_plan snell,anytls 443 443 8444 ""').returncode,0)
  self.assertNotEqual(self.run_plan('deploy_build_plan hysteria2 443 8443 20001 20000-50000').returncode,0)
if __name__=='__main__': unittest.main()
