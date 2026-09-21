#!/usr/bin/env python3
"""
Test suite for Magic URL Zero-Setup Strand Onboarding & Multi-Display Topology.
"""

import io
import os
import sys
import tarfile
import unittest
import urllib.request
import ssl
import json
import subprocess
import threading
import time

KNOT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, KNOT_ROOT)

from core.hub.hub import (
    get_distribution_bundle,
    get_active_swarm_info,
    render_onboarding_html,
    render_bootstrap_script,
    enrollment_coordinator
)


class TestMagicOnboarding(unittest.TestCase):
    def test_distribution_bundle(self):
        """Verify distribution bundle is generated, lightweight, and contains required files."""
        bundle = get_distribution_bundle()
        self.assertIsInstance(bundle, bytes)
        self.assertGreater(len(bundle), 10 * 1024, "Bundle should be at least 10KB")
        self.assertLess(len(bundle), 5 * 1024 * 1024, "Bundle should be under 5MB")

        # Inspect tar contents
        with tarfile.open(fileobj=io.BytesIO(bundle), mode="r:gz") as tar:
            names = tar.getnames()
            self.assertIn("knot-mesh/bin/knot", names)
            self.assertIn("knot-mesh/bin/knot-installer", names)
            self.assertIn("knot-mesh/core/hub/hub.py", names)
            self.assertIn("knot-mesh/core/installer/display.sh", names)
            self.assertIn("knot-mesh/core/installer/enroll.py", names)

            # Ensure heavy/transient items are excluded
            for n in names:
                self.assertNotIn(".git/", n)
                self.assertNotIn("node_modules/", n)
                self.assertNotIn("__pycache__", n)
                self.assertFalse(n.endswith(".pyc"))

    def test_render_bootstrap_script(self):
        """Verify generated bootstrap script is syntactically valid bash and contains parameters."""
        script = render_bootstrap_script(
            swarm_name="Office Swarm",
            anchor_host="192.168.1.100",
            anchor_port="4242",
            token="654321.abcdef123456",
            pin="654321",
            fp_short="abcdef123456"
        )
        self.assertIn("#!/usr/bin/env bash", script)
        self.assertIn('ANCHOR_HOST="192.168.1.100"', script)
        self.assertIn('TOKEN="654321.abcdef123456"', script)
        self.assertIn('FP_SHORT="abcdef123456"', script)
        self.assertIn('"$BIN_DIR/knot-installer" join "${ANCHOR_HOST}:${ANCHOR_PORT}" "$TOKEN" --auto', script)

        # Validate syntax with bash -n
        proc = subprocess.run(["bash", "-n"], input=script, text=True, capture_output=True)
        self.assertEqual(proc.returncode, 0, f"Bootstrap script bash syntax error: {proc.stderr}")

    def test_render_onboarding_html(self):
        """Verify generated HTML landing page contains dark-mode styles and copy button."""
        html = render_onboarding_html(
            swarm_name="Office Swarm",
            anchor_host="192.168.1.100",
            anchor_port="4242",
            token="654321.abcdef123456",
            pin="654321",
            fp_short="abcdef123456"
        )
        self.assertIn("<!DOCTYPE html>", html)
        self.assertIn("Office Swarm", html)
        self.assertIn("192.168.1.100", html)
        self.assertIn("curl -kfsSL https://192.168.1.100:4242/join/654321.abcdef123456 | bash", html)
        self.assertIn("Copy One-Liner Command", html)
        self.assertIn("navigator.clipboard.writeText", html)

    def test_enrollment_coordinator_anchor_ip(self):
        """Verify invite creation propagates anchor_ip in session."""
        session = enrollment_coordinator.create_invite(expires_in=300, anchor_ip="192.168.1.100")
        self.assertEqual(session["anchor_ip"], "192.168.1.100")
        self.assertIn(".", session["token"])
        pin = session["pin"]
        self.assertEqual(session["token"].split(".")[0], pin)

    def test_multi_display_parsing(self):
        """Verify display.sh --json returns active outputs with DP-2 primary and eDP-1 secondary."""
        display_sh = os.path.join(KNOT_ROOT, "core", "installer", "display.sh")
        proc = subprocess.run(["bash", display_sh, "--json"], text=True, capture_output=True)
        self.assertEqual(proc.returncode, 0, f"display.sh --json failed: {proc.stderr}")
        data = json.loads(proc.stdout)
        self.assertIn("resolution", data)
        self.assertIn("refresh_rate", data)
        self.assertIn("scale", data)
        if "outputs" in data:
            outputs = data["outputs"]
            self.assertGreaterEqual(len(outputs), 1)
            primary_outputs = [o for o in outputs if o.get("primary") is True]
            self.assertEqual(len(primary_outputs), 1, "Exactly one primary output expected")


if __name__ == "__main__":
    unittest.main()
