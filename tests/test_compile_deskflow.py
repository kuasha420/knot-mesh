#!/usr/bin/env python3
"""
Unit tests for Knot Dynamic Deskflow Configuration Compiler (core/modules/compile_deskflow.py)
Validates:
1. Section generation: screens, aliases, links, options.
2. Fractional boundary mapping (e.g. (65,100) or (45,85)).
3. Direction normalization (above -> up, below -> down).
4. Automatic reciprocal link generation.
5. Headless node exclusion from screens and links.
6. Locked mode cursor confinement (omits outbound links from Anchor).
7. CLI argument handling (--topology, --nodes-dir, --output, --locked, --mode).
"""

import os
import sys
import json
import tempfile
import subprocess
import unittest
from pathlib import Path

# Add core/modules to path
MODULES_DIR = Path(__file__).resolve().parent.parent / "core" / "modules"
sys.path.insert(0, str(MODULES_DIR))

import compile_deskflow

class TestCompileDeskflow(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.temp_dir.name)
        self.nodes_dir = self.tmp_path / "nodes"
        self.nodes_dir.mkdir(parents=True, exist_ok=True)

        # Setup sample node manifests
        manifests = {
            "desktop.json": {
                "id": "desktop",
                "hostname": "arch-desktop",
                "role": "anchor",
                "display": {"resolution": "2560x1440"}
            },
            "laptop.json": {
                "id": "laptop",
                "hostname": "arch-laptop",
                "role": "strand",
                "display": {"resolution": "1920x1080"}
            },
            "steamdeck.json": {
                "id": "steamdeck",
                "hostname": "deck-eos",
                "role": "strand",
                "display": {"resolution": "1280x800"}
            },
            "server.json": {
                "id": "server",
                "hostname": "headless-box",
                "role": "headless",
                "display": None
            }
        }
        for fname, data in manifests.items():
            with open(self.nodes_dir / fname, "w") as f:
                json.dump(data, f, indent=2)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_basic_compilation_with_layout(self):
        topo = {
            "anchor": "desktop",
            "screens": ["desktop", "laptop", "steamdeck"],
            "layout": {
                "desktop": {
                    "left": {
                        "node": "laptop",
                        "span": [65, 100]
                    },
                    "down": {
                        "node": "steamdeck",
                        "span": [45, 85]
                    }
                },
                "laptop": {
                    "right": {
                        "node": "desktop",
                        "span": [65, 100]
                    }
                },
                "steamdeck": {
                    "up": {
                        "node": "desktop",
                        "span": [45, 85]
                    }
                }
            }
        }
        topo_path = self.tmp_path / "topology.json"
        with open(topo_path, "w") as f:
            json.dump(topo, f, indent=2)

        conf = compile_deskflow.compile_deskflow(str(topo_path), str(self.nodes_dir), mode="unlocked")

        self.assertIn("section: screens", conf)
        self.assertIn("arch-desktop:", conf)
        self.assertIn("arch-laptop:", conf)
        self.assertIn("deck-eos:", conf)
        self.assertIn("section: aliases", conf)
        self.assertIn("desktop", conf)
        self.assertIn("laptop", conf)
        self.assertIn("steamdeck", conf)
        self.assertIn("section: links", conf)
        self.assertIn("left(65,100) = arch-laptop(65,100)", conf)
        self.assertIn("down(45,85) = deck-eos(45,85)", conf)
        self.assertIn("section: options", conf)
        self.assertIn("keystroke(ScrollLock) = lockCursorToScreen(toggle)", conf)

    def test_automatic_reciprocal_links(self):
        # Only define desktop -> laptop (left), expect laptop -> desktop (right) to be auto-generated
        topo = {
            "anchor": "desktop",
            "screens": ["desktop", "laptop"],
            "layout": {
                "desktop": {
                    "left": {
                        "node": "laptop",
                        "span": [20, 80]
                    }
                }
            }
        }
        topo_path = self.tmp_path / "topology_unidir.json"
        with open(topo_path, "w") as f:
            json.dump(topo, f, indent=2)

        conf = compile_deskflow.compile_deskflow(str(topo_path), str(self.nodes_dir), mode="unlocked")
        # Check that reciprocal link exists on arch-laptop pointing right to arch-desktop
        self.assertIn("arch-laptop:", conf)
        self.assertIn("right(0,100) = arch-desktop(20,80)", conf)

    def test_direction_normalization(self):
        # Test above -> up, below -> down
        topo = {
            "anchor": "desktop",
            "screens": ["desktop", "laptop", "steamdeck"],
            "layout": {
                "desktop": {
                    "above": {
                        "node": "laptop",
                        "span": [0, 100]
                    },
                    "below": {
                        "node": "steamdeck",
                        "span": [0, 100]
                    }
                }
            }
        }
        topo_path = self.tmp_path / "topology_norm.json"
        with open(topo_path, "w") as f:
            json.dump(topo, f, indent=2)

        conf = compile_deskflow.compile_deskflow(str(topo_path), str(self.nodes_dir), mode="unlocked")
        self.assertIn("up(0,100) = arch-laptop(0,100)", conf)
        self.assertIn("down(0,100) = deck-eos(0,100)", conf)
        # Reciprocal links should use down and up
        self.assertIn("down(0,100) = arch-desktop(0,100)", conf)
        self.assertIn("up(0,100) = arch-desktop(0,100)", conf)

    def test_headless_node_exclusion(self):
        # topology lists desktop, laptop, and headless server
        topo = {
            "anchor": "desktop",
            "screens": ["desktop", "laptop", "server"],
            "nodes": {
                "desktop": {"screens": ["desktop"]},
                "laptop": {"screens": ["laptop"]},
                "server": {"headless": True}
            },
            "layout": {
                "desktop": {
                    "left": {"node": "laptop", "span": [0, 100]},
                    "right": {"node": "server", "span": [0, 100]}
                }
            }
        }
        topo_path = self.tmp_path / "topology_headless.json"
        with open(topo_path, "w") as f:
            json.dump(topo, f, indent=2)

        conf = compile_deskflow.compile_deskflow(str(topo_path), str(self.nodes_dir), mode="unlocked")
        # headless-box must not appear in screens
        screens_section = conf.split("section: screens")[1].split("end")[0]
        self.assertNotIn("headless-box", screens_section)
        # No link to headless-box
        self.assertNotIn("headless-box", conf)

    def test_locked_mode_cursor_confinement(self):
        topo = {
            "anchor": "desktop",
            "screens": ["desktop", "laptop"],
            "layout": {
                "desktop": {
                    "left": {"node": "laptop", "span": [0, 100]}
                },
                "laptop": {
                    "right": {"node": "desktop", "span": [0, 100]}
                }
            }
        }
        topo_path = self.tmp_path / "topology_locked.json"
        with open(topo_path, "w") as f:
            json.dump(topo, f, indent=2)

        conf = compile_deskflow.compile_deskflow(str(topo_path), str(self.nodes_dir), mode="locked")
        # In locked mode, desktop should not have outbound links
        # Check lines under arch-desktop: in section: links
        links_section = conf.split("section: links")[1].split("end")[0]
        lines = [line.strip() for line in links_section.splitlines() if line.strip()]
        
        desktop_has_links = False
        in_desktop = False
        for line in lines:
            if line == "arch-desktop:":
                in_desktop = True
                continue
            elif line.endswith(":"):
                in_desktop = False
            elif in_desktop and ("=" in line):
                desktop_has_links = True

        self.assertFalse(desktop_has_links, "Anchor desktop must not have outbound links in locked mode")

    def test_cli_execution(self):
        topo = {
            "anchor": "desktop",
            "screens": ["desktop", "laptop"],
            "layout": {
                "desktop": {
                    "left": {"node": "laptop", "span": [0, 100]}
                }
            }
        }
        topo_path = self.tmp_path / "topology_cli.json"
        out_path = self.tmp_path / "deskflow-server.conf"
        with open(topo_path, "w") as f:
            json.dump(topo, f, indent=2)

        cmd = [
            sys.executable,
            str(MODULES_DIR / "compile_deskflow.py"),
            "--topology", str(topo_path),
            "--nodes-dir", str(self.nodes_dir),
            "--locked", "true",
            "--output", str(out_path)
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"CLI execution failed: {res.stderr}")
        self.assertTrue(out_path.exists())
        content = out_path.read_text()
        self.assertIn("section: screens", content)
        self.assertIn("arch-desktop:", content)

    def test_links_list_format(self):
        topo = {
            "anchor": "desktop",
            "nodes": {
                "desktop": {"screens": ["desktop"]},
                "laptop": {"screens": ["laptop"]}
            },
            "links": [
                {
                    "from": "desktop",
                    "direction": "left",
                    "to": "laptop",
                    "span": [10, 90],
                    "target_span": [20, 80]
                }
            ]
        }
        topo_path = self.tmp_path / "topology_list.json"
        with open(topo_path, "w") as f:
            json.dump(topo, f, indent=2)

        conf = compile_deskflow.compile_deskflow(str(topo_path), str(self.nodes_dir), mode="unlocked")
        self.assertIn("left(10,90) = arch-laptop(20,80)", conf)
        self.assertIn("right(20,80) = arch-desktop(10,90)", conf)

if __name__ == "__main__":
    unittest.main()
