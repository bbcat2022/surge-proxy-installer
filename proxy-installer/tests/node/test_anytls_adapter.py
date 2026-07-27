import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADAPTER = ROOT / "lib" / "adapters" / "anytls.sh"
PASSWORD = "anytlsPass_123"

class AnyTLSAdapterTests(unittest.TestCase):
    def run_adapter(self, expression):
        return subprocess.run(["bash", "-c", f'source "{ADAPTER}"; {expression}'], text=True, capture_output=True, check=False)

    def test_runtime_uses_shared_certificate_and_tcp_inbound(self):
        result = self.run_adapter(f'anytls_build_runtime 443 {PASSWORD} node.example.com /cert.pem /key.pem')
        self.assertEqual(result.returncode, 0)
        self.assertIn('"type":"anytls"', result.stdout)
        self.assertIn('"certificate_path":"/cert.pem"', result.stdout)
        self.assertIn('"listen_port":443', result.stdout)

    def test_surge_unit_and_resource_output(self):
        surge = self.run_adapter(f'anytls_build_surge_entry AnyTLS 443 {PASSWORD} node.example.com true false')
        unit = self.run_adapter('anytls_build_unit /usr/local/bin/sing-box /etc/proxy-installer/runtime/anytls.json')
        resources = self.run_adapter('anytls_resource_requirements 443')
        self.assertEqual(surge.stdout, f'AnyTLS = anytls, node.example.com, 443, password={PASSWORD}, tfo=true, reuse=false\n')
        self.assertIn('run -c', unit.stdout)
        self.assertIn('network=tcp:443', resources.stdout)
        self.assertIn('certificate=shared-main-domain', resources.stdout)

    def test_invalid_input_is_rejected(self):
        self.assertNotEqual(self.run_adapter(f'anytls_build_runtime 0 {PASSWORD} node.example.com /cert /key').returncode, 0)
        self.assertNotEqual(self.run_adapter(f'anytls_build_surge_entry AnyTLS 443 short node.example.com true false').returncode, 0)
        self.assertNotEqual(self.run_adapter(f'anytls_build_surge_entry AnyTLS 443 {PASSWORD} node.example.com yes false').returncode, 0)

    def test_config_patch_is_valid_for_safe_inputs(self):
        result = self.run_adapter(f'anytls_build_config_patch 443 {PASSWORD} node.example.com true false')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('"password":"anytlsPass_123"', result.stdout)

if __name__ == '__main__':
    unittest.main()
