import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADAPTER = ROOT / "lib" / "adapters" / "snell.sh"
PSK = "testPsk_12345678"


class SnellAdapterTests(unittest.TestCase):
    def run_adapter(self, expression: str):
        return subprocess.run(["bash", "-c", f'source "{ADAPTER}"; {expression}'], text=True, capture_output=True, check=False)

    def test_domain_and_ipv4_inputs_are_valid(self):
        self.assertEqual(self.run_adapter(f'snell_validate 443 {PSK} domain node.example.com default').returncode, 0)
        self.assertEqual(self.run_adapter(f'snell_validate 443 {PSK} ip 203.0.113.9 default').returncode, 0)

    def test_invalid_protocol_inputs_are_rejected(self):
        self.assertNotEqual(self.run_adapter(f'snell_validate 0 {PSK} domain node.example.com default').returncode, 0)
        self.assertNotEqual(self.run_adapter('snell_validate 443 short domain node.example.com default').returncode, 0)
        self.assertNotEqual(self.run_adapter(f'snell_validate 443 {PSK} ip 999.0.0.1 default').returncode, 0)
        self.assertNotEqual(self.run_adapter(f'snell_validate 443 {PSK} ip "::1\"bad" default').returncode, 0)
        self.assertNotEqual(self.run_adapter(f'snell_validate 443 {PSK} domain node.example.com quic').returncode, 0)

    def test_runtime_unit_surge_and_resources_are_built_without_side_effects(self):
        runtime = self.run_adapter(f'snell_build_runtime 443 {PSK} domain node.example.com default')
        unit = self.run_adapter('snell_build_unit /usr/local/bin/snell-server /etc/proxy-installer/runtime/snell.conf')
        surge = self.run_adapter(f'snell_build_surge_entry Snell 443 {PSK} domain node.example.com default')
        resources = self.run_adapter('snell_resource_requirements 443')
        self.assertEqual(runtime.returncode, 0)
        self.assertIn('[snell-server]', runtime.stdout)
        self.assertIn('listen = 0.0.0.0:443', runtime.stdout)
        self.assertIn('mode = default', runtime.stdout)
        self.assertIn('dns-ip-preference = default', runtime.stdout)
        self.assertEqual(unit.returncode, 0)
        self.assertIn('ExecStart=/usr/local/bin/snell-server -c /etc/proxy-installer/runtime/snell.conf', unit.stdout)
        self.assertEqual(surge.stdout, f'Snell = snell, node.example.com, 443, psk={PSK}, version=6\n')
        self.assertIn('network=tcp:443', resources.stdout)

    def test_config_patch_preserves_mode_for_desired_state(self):
        result = self.run_adapter(f'snell_build_config_patch 443 {PSK} ip 203.0.113.9 default')
        self.assertEqual(result.returncode, 0)
        self.assertIn('"mode":"default"', result.stdout)
        self.assertIn('"client_address_type":"ip"', result.stdout)


if __name__ == "__main__":
    unittest.main()
