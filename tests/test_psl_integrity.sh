#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh - Universal PSL Gold Standard Integrity Test Suite
# Validates Rule 1 (Zero Error Swallowing), Shell Hygiene, Syntax, Python Integrity, and Permissions

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
TOTAL_ERRORS=0

echo -e "\033[1;34m============================================================\033[0m"
echo -e "\033[1;34m  KNOT MESH: UNIVERSAL PSL INTEGRITY SUITE                  \033[0m"
echo -e "\033[1;34m============================================================\033[0m"

# -------------------------------------------------------------
# Section 1: Zero Error Swallowing Code Audit
# -------------------------------------------------------------
echo -e "\n\033[1m[Audit 1/5] Scanning for Forbidden Error-Swallowing Patterns...\033[0m"
FORBIDDEN_PATTERN='(2>/dev/null|&>/dev/null|> */dev/null *2>&1|\|\| *true|\|\| *:)'
AUDIT_TARGETS=(
  "$KNOT_ROOT/bin"
  "$KNOT_ROOT/core"
  "$KNOT_ROOT/runtime"
  "$KNOT_ROOT/install.sh"
  "$KNOT_ROOT/PKGBUILD"
)

audit1_failures=0

# Scan production code (bin/, core/, runtime/, install.sh, PKGBUILD)
for target in "${AUDIT_TARGETS[@]}"; do
  [ -e "$target" ] || continue

  while IFS= read -r f; do
    [ -f "$f" ] || continue
    # Skip binary files, git, images, docs/markdown
    case "$f" in
      *.md|*.png|*.jpg|*.jpeg|*.svg|*.ico|*.pdf|*.json|*.toml|*.yaml|*.yml|*.txt|*.service|*.desktop) continue ;;
      */__pycache__/*) continue ;;
    esac

    # Search for forbidden pattern on non-comment lines
    matches=""
    if ! matches=$(grep -n -E "$FORBIDDEN_PATTERN" "$f" 2>&1 | grep -v "^[0-9]*:[[:space:]]*#"); then
      matches=""
    fi
    if [ -n "$matches" ]; then
      echo -e "  \033[1;31mFAIL: Forbidden pattern found in $f:\033[0m"
      while IFS= read -r m; do
        echo "    $m"
      done <<< "$matches"
      audit1_failures=$((audit1_failures + 1))
    fi
  done < <(find "$target" -type f)
done

# Scan test scripts in tests/ (excluding assertion checks that inspect for forbidden patterns)
while IFS= read -r tf; do
  [ -f "$tf" ] || continue
  case "$tf" in
    *.sh|*.py)
      matches=""
      if ! matches=$(grep -n -E "$FORBIDDEN_PATTERN" "$tf" 2>&1 | grep -v "^[0-9]*:[[:space:]]*#" | grep -v "grep " | grep -v "echo " | grep -v "FORBIDDEN_PATTERN=" | grep -v "PSL Rule 1"); then
        matches=""
      fi
      if [ -n "$matches" ]; then
        echo -e "  \033[1;31mFAIL: Forbidden pattern found in test script $tf:\033[0m"
        while IFS= read -r m; do
          echo "    $m"
        done <<< "$matches"
        audit1_failures=$((audit1_failures + 1))
      fi
      ;;
  esac
done < <(find "$KNOT_ROOT/tests" -type f)

if [ $audit1_failures -eq 0 ]; then
  echo -e "  \033[1;32m✓ PSL Rule 1 Verified: Zero error swallowing across all production code and test suites.\033[0m"
else
  echo -e "  \033[1;31m✗ Audit 1 Failed: $audit1_failures files violate PSL Rule 1.\033[0m"
  TOTAL_ERRORS=$((TOTAL_ERRORS + audit1_failures))
fi

# -------------------------------------------------------------
# Section 2: Shell Hygiene (set -euo pipefail)
# -------------------------------------------------------------
echo -e "\n\033[1m[Audit 2/5] Verifying Shell Hygiene (set -euo pipefail)...\033[0m"
audit2_failures=0

check_hygiene() {
  local file="$1"
  [ -f "$file" ] || return 0
  local head_line=""
  if [ -r "$file" ]; then
    head_line="$(head -n1 "$file")"
  fi
  if [[ "$head_line" =~ bash|sh ]] || [[ "$file" == *.sh ]]; then
    if ! grep -qE '^set -[a-z]*e[a-z]*' "$file" || ! grep -qE 'pipefail' "$file"; then
      echo -e "  \033[1;31mFAIL: Missing 'set -euo pipefail' in $file\033[0m"
      audit2_failures=$((audit2_failures + 1))
    fi
  fi
}

for sf in "$KNOT_ROOT/install.sh" "$KNOT_ROOT/bin"/*; do
  check_hygiene "$sf"
done

while IFS= read -r sf; do
  check_hygiene "$sf"
done < <(find "$KNOT_ROOT/core" "$KNOT_ROOT/runtime" "$KNOT_ROOT/tests" -type f -name "*.sh")

if [ $audit2_failures -eq 0 ]; then
  echo -e "  \033[1;32m✓ Shell Hygiene Verified: All shell scripts enforce strict 'set -euo pipefail'.\033[0m"
else
  echo -e "  \033[1;31m✗ Audit 2 Failed: $audit2_failures scripts lack proper shell hygiene.\033[0m"
  TOTAL_ERRORS=$((TOTAL_ERRORS + audit2_failures))
fi

# -------------------------------------------------------------
# Section 3: Shell Syntax (bash -n)
# -------------------------------------------------------------
echo -e "\n\033[1m[Audit 3/5] Auditing Shell Script Syntax (bash -n)...\033[0m"
audit3_failures=0

check_syntax() {
  local file="$1"
  [ -f "$file" ] || return 0
  local head_line=""
  if [ -r "$file" ]; then
    head_line="$(head -n1 "$file")"
  fi
  if [[ "$head_line" =~ bash|sh ]] || [[ "$file" == *.sh ]]; then
    local err_out="" rc=0
    err_out="$(bash -n "$file" 2>&1)" || rc=$?
    if [ $rc -ne 0 ]; then
      echo -e "  \033[1;31mFAIL: Syntax error in $file (exit $rc):\033[0m"
      echo "    $err_out"
      audit3_failures=$((audit3_failures + 1))
    fi
  fi
}

for sf in "$KNOT_ROOT/install.sh" "$KNOT_ROOT/bin"/*; do
  check_syntax "$sf"
done

while IFS= read -r sf; do
  check_syntax "$sf"
done < <(find "$KNOT_ROOT/core" "$KNOT_ROOT/runtime" "$KNOT_ROOT/tests" -type f -name "*.sh")

if [ $audit3_failures -eq 0 ]; then
  echo -e "  \033[1;32m✓ Shell Syntax Verified: 100% of shell scripts passed syntax inspection.\033[0m"
else
  echo -e "  \033[1;31m✗ Audit 3 Failed: $audit3_failures scripts contain syntax errors.\033[0m"
  TOTAL_ERRORS=$((TOTAL_ERRORS + audit3_failures))
fi

# -------------------------------------------------------------
# Section 4: Python Integrity & Syntax (py_compile & exception hygiene)
# -------------------------------------------------------------
echo -e "\n\033[1m[Audit 4/5] Auditing Python Syntax & Exception Hygiene...\033[0m"
audit4_failures=0

python_audit_out=""
python_audit_out="$(python3 - << 'PYEOF'
import os, sys, py_compile, ast

failures = 0
knot_root = os.path.abspath(os.path.join(os.path.dirname(sys.argv[0]) if sys.argv[0] else ".", "."))

for root_dir in [os.path.join(knot_root, d) for d in ["bin", "core", "runtime", "tests"]]:
    if not os.path.exists(root_dir):
        continue
    for dirpath, _, filenames in os.walk(root_dir):
        if "__pycache__" in dirpath or ".git" in dirpath:
            continue
        for fname in filenames:
            fpath = os.path.join(dirpath, fname)
            is_python = fname.endswith(".py")
            if not is_python and os.access(fpath, os.X_OK) and os.path.isfile(fpath):
                try:
                    with open(fpath, "rb") as f:
                        hdr = f.read(64)
                        if b"python" in hdr:
                            is_python = True
                except (IOError, OSError):
                    is_python = False

            if is_python:
                # 1. Compilation check
                try:
                    py_compile.compile(fpath, doraise=True)
                except py_compile.PyCompileError as e:
                    sys.stderr.write(f"FAIL_SYNTAX: {fpath}: {e}\n")
                    failures += 1

                # 2. AST Exception hygiene check (detects bare except and multi-line PEP 8 swallowed exceptions)
                try:
                    with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                        content = f.read()
                    tree = ast.parse(content, filename=fpath)
                    for node in ast.walk(tree):
                        if isinstance(node, ast.Try):
                            for h in node.handlers:
                                if h.type is None:
                                    sys.stderr.write(f"FAIL_EXCEPTION: Bare except at {fpath}:{h.lineno}\n")
                                    failures += 1
                                if len(h.body) == 1 and isinstance(h.body[0], ast.Pass):
                                    sys.stderr.write(f"FAIL_EXCEPTION: Swallowed exception at {fpath}:{h.lineno}\n")
                                    failures += 1
                                elif len(h.body) == 1 and isinstance(h.body[0], ast.Expr) and isinstance(h.body[0].value, ast.Constant) and h.body[0].value.value is ...:
                                    sys.stderr.write(f"FAIL_EXCEPTION: Swallowed exception (ellipsis) at {fpath}:{h.lineno}\n")
                                    failures += 1
                except SyntaxError:
                    pass
                except (IOError, OSError) as e:
                    sys.stderr.write(f"FAIL_READ: {fpath}: {e}\n")
                    failures += 1

sys.exit(failures)
PYEOF
2>&1)" || audit4_failures=$?

if [ $audit4_failures -eq 0 ]; then
  echo -e "  \033[1;32m✓ Python Integrity Verified: All python modules compile and enforce strict exception hygiene.\033[0m"
else
  echo -e "  \033[1;31m✗ Audit 4 Failed ($audit4_failures issues):\033[0m"
  echo "$python_audit_out"
  TOTAL_ERRORS=$((TOTAL_ERRORS + audit4_failures))
fi

# -------------------------------------------------------------
# Section 5: Executable Permissions (+x on bin/* and tests/*.sh)
# -------------------------------------------------------------
echo -e "\n\033[1m[Audit 5/5] Validating Executable Permissions...\033[0m"
audit5_failures=0

for b in "$KNOT_ROOT/bin"/*; do
  [ -f "$b" ] || continue
  if [ ! -x "$b" ]; then
    echo -e "  \033[1;31mFAIL: $b is not executable (+x missing)\033[0m"
    audit5_failures=$((audit5_failures + 1))
  fi
done

for ts in "$KNOT_ROOT/tests"/*.sh; do
  [ -f "$ts" ] || continue
  if [ ! -x "$ts" ]; then
    echo -e "  \033[1;31mFAIL: $ts is not executable (+x missing)\033[0m"
    audit5_failures=$((audit5_failures + 1))
  fi
done

if [ $audit5_failures -eq 0 ]; then
  echo -e "  \033[1;32m✓ Permissions Verified: All bin/* binaries and tests/*.sh test scripts have +x.\033[0m"
else
  echo -e "  \033[1;31m✗ Audit 5 Failed: $audit5_failures files missing +x permission.\033[0m"
  TOTAL_ERRORS=$((TOTAL_ERRORS + audit5_failures))
fi

# -------------------------------------------------------------
# Summary & Exit
# -------------------------------------------------------------
echo -e "\n\033[1;34m============================================================\033[0m"
if [ $TOTAL_ERRORS -eq 0 ]; then
  echo -e "\033[1;32m✔ UNIVERSAL PSL INTEGRITY AUDIT PASSED (0 defects found)\033[0m"
  echo -e "\033[1;34m============================================================\033[0m"
  exit 0
else
  echo -e "\033[1;31m✖ UNIVERSAL PSL INTEGRITY AUDIT FAILED ($TOTAL_ERRORS defects detected)\033[0m"
  echo -e "\033[1;34m============================================================\033[0m"
  exit 1
fi
