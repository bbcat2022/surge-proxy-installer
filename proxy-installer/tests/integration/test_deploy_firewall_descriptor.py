import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DESCRIPTOR = ROOT / "lib" / "orchestrators" / "deploy_firewall_descriptor.sh"


class DeployFirewallDescriptorTests(unittest.TestCase):
    def run_case(self, assignments: str):
        with tempfile.TemporaryDirectory() as temp_text:
            target = Path(temp_text) / "firewall.descriptor"
            body = f'''
source "{DESCRIPTOR}"
{assignments}
deploy_firewall_descriptor_build "{target}" &&
deploy_firewall_descriptor_load "{target}" &&
printf 'RULES=%s\\n' "$(IFS=,; echo "${{DEPLOY_FIREWALL_RULES[*]}}")"
'''
            result = subprocess.run(["bash", "-c", body], text=True, capture_output=True, check=False)
            content = target.read_text(encoding="utf-8") if target.exists() else ""
        return result, content

    def test_builds_exact_transport_rules_for_all_protocols(self):
        result, content = self.run_case(
            'DEPLOY_SELECTED_PROTOCOLS=snell,anytls,hysteria2; '
            'SNELL_PORT=443; ANYTLS_PORT=8443; HYSTERIA2_PORT=9000; '
            'HYSTERIA2_PORT_HOPPING_RANGE=20000-20100'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            content,
            "schema=1\nrule=tcp:443\nrule=tcp:8443\nrule=udp:9000\nrule=udp-range:20000-20100\n",
        )
        self.assertIn("RULES=tcp:443,tcp:8443,udp:9000,udp-range:20000-20100", result.stdout)

    def test_rejects_tcp_conflict_and_main_port_inside_hop_range(self):
        conflict, _ = self.run_case(
            'DEPLOY_SELECTED_PROTOCOLS=snell,anytls; SNELL_PORT=443; ANYTLS_PORT=443'
        )
        overlap, _ = self.run_case(
            'DEPLOY_SELECTED_PROTOCOLS=hysteria2; HYSTERIA2_PORT=20001; '
            'HYSTERIA2_PORT_HOPPING_RANGE=20000-20100'
        )
        self.assertNotEqual(conflict.returncode, 0)
        self.assertNotEqual(overlap.returncode, 0)

    def test_loader_rejects_duplicate_or_unknown_lines(self):
        with tempfile.TemporaryDirectory() as temp_text:
            target = Path(temp_text) / "bad.descriptor"
            target.write_text("schema=1\nrule=tcp:443\nrule=tcp:443\n", encoding="utf-8")
            duplicate = subprocess.run(
                ["bash", "-c", f'source "{DESCRIPTOR}"; deploy_firewall_descriptor_load "{target}"'],
                text=True, capture_output=True, check=False,
            )
            target.write_text("schema=1\ncommand=allow-all\n", encoding="utf-8")
            unknown = subprocess.run(
                ["bash", "-c", f'source "{DESCRIPTOR}"; deploy_firewall_descriptor_load "{target}"'],
                text=True, capture_output=True, check=False,
            )
        self.assertNotEqual(duplicate.returncode, 0)
        self.assertNotEqual(unknown.returncode, 0)


if __name__ == "__main__":
    unittest.main()
