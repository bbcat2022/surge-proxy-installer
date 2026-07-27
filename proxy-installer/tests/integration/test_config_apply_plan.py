import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLANNER = ROOT / "lib" / "orchestrators" / "config_apply.sh"

class ConfigApplyPlanTests(unittest.TestCase):
 def run_plan(self, expression): return subprocess.run(["bash","-c",f'source "{PLANNER}"; {expression}'],text=True,capture_output=True,check=False)
 def test_client_only_anytls_field_does_not_restart_service(self):
  r=self.run_plan('config_apply_plan anytls tfo')
  self.assertEqual(r.returncode,0); self.assertIn('service-restart=false',r.stdout); self.assertIn('surge-export=true',r.stdout)
 def test_hysteria_network_change_requires_runtime_service_and_firewall(self):
  r=self.run_plan('config_apply_plan hysteria2 port_hopping_range')
  self.assertEqual(r.returncode,0); self.assertIn('runtime=true',r.stdout); self.assertIn('firewall=true',r.stdout)
 def test_domain_change_requires_candidate_certificate(self):
  r=self.run_plan('config_apply_plan global main_domain')
  self.assertEqual(r.returncode,0); self.assertIn('certificate=candidate-required',r.stdout)
 def test_unknown_field_is_rejected(self): self.assertNotEqual(self.run_plan('config_apply_plan snell unknown').returncode,0)
if __name__=='__main__': unittest.main()
