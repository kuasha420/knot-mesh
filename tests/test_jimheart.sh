#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh - Jim Heart Game Integrity and Test Suite
# Validates Rule 1 (Zero Error Swallowing), Shell Hygiene, Python Syntax, and Automated Unit Tests

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

echo -e "\033[1;34m============================================================\033[0m"
echo -e "\033[1;34m  KNOT MESH: JIM HEART GAME AUTOMATED VERIFICATION           \033[0m"
echo -e "\033[1;34m============================================================\033[0m"

echo -e "\n\033[1m[1/3] Validating Python Syntax...\033[0m"
python3 -m py_compile "$KNOT_ROOT/apps/jimheart/sound_synth.py"
python3 -m py_compile "$KNOT_ROOT/apps/jimheart/main.py"
python3 -m py_compile "$KNOT_ROOT/apps/jimheart/test_jimheart.py"
echo "  [OK] Python syntax compiled successfully."

echo -e "\n\033[1m[2/3] Validating Shell Scripts Syntax...\033[0m"
bash -n "$KNOT_ROOT/bin/knot-jimheart"
echo "  [OK] Shell scripts syntax valid."

echo -e "\n\033[1m[3/3] Running Jim Heart Unit Test Suite...\033[0m"
cd "$KNOT_ROOT"
QT_QPA_PLATFORM=offscreen python3 -m unittest apps/jimheart/test_jimheart.py
echo "  [OK] All Jim Heart automated tests passed."

echo -e "\n\033[1;32m============================================================\033[0m"
echo -e "\033[1;32m  ALL JIM HEART CHECKS PASSED (PSL GOLD STANDARD)           \033[0m"
echo -e "\033[1;32m============================================================\033[0m"
