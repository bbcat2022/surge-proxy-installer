import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "lib" / "registry" / "protocols.sh"


class ProtocolRegistryTests(unittest.TestCase):
    def run_registry(self, expression: str):
        return subprocess.run(["bash", "-c", f'source "{REGISTRY}"; {expression}'], text=True, capture_output=True, check=False)

    def test_registry_has_all_required_v1_protocol_fields(self):
        result = self.run_registry("protocol_registry_validate")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_network_and_tls_rules_are_protocol_specific(self):
        self.assertEqual(self.run_registry("protocol_registry_get snell network").stdout.strip(), "tcp")
        self.assertEqual(self.run_registry("protocol_registry_get anytls tls").stdout.strip(), "shared-main-domain")
        self.assertEqual(self.run_registry("protocol_registry_get hysteria2 network").stdout.strip(), "udp,udp-range")

    def test_sensitive_parameters_are_declared(self):
        snell = self.run_registry("protocol_registry_parameters snell").stdout
        anytls = self.run_registry("protocol_registry_parameters anytls").stdout
        hysteria = self.run_registry("protocol_registry_parameters hysteria2").stdout
        self.assertIn("psk:string:required:true", snell)
        self.assertIn("password:string:required:true", anytls)
        self.assertIn("gecko:string:optional:true", hysteria)

    def test_unregistered_protocol_is_rejected(self):
        result = self.run_registry("protocol_registry_get unknown network")
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
