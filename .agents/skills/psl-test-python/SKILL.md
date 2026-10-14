---
name: psl-test-python
description: >-
  Modular Python test runner skill for Agyis Harness. Codifies hermetic
  pytest, unittest discovery, clean-room temporary directory isolation, sub-second benchmark invariants,
  and zero error-swallowing execution standards.
---
<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Arafat Zahan (@kuasha420) -->
<!-- Corporate Stewardship & Infrastructure: Purrfect Software Limited (PSL) -->
<!-- Governed by: ICARO-42/b Ordinance (Company-Supported Personal IP Framework) -->

# PSL Test Skill: Python Test Runner & Hermetic Verification

This skill establishes standardized execution contracts and hermetic benchmarking standards for Python unit and integration testing across Agyis Harness.

---

## 1. Test Runner Invariants

### 1.1 Hermetic Test Invocation
- Always invoke the test suite via the unified CLI or standard hermetic module runners:
  ```bash
  # Primary test suite runner
  agyis test

  # Standard unittest discovery
  python3 -m unittest discover -s tests -p "test_*.py"

  # Pytest runner (when configured in pyproject.toml)
  pytest -q tests/
  ```
- Target hermetic CPython 3.12+ runtimes (`python3` or `uv run python`).

### 1.2 Sub-Second Benchmark Invariant (ADR-015)
- Automated unit test suites must complete execution in strictly **under 1.0 second**.
- Enforce in-memory mocks, deterministic loops, and zero artificial `time.sleep()` delays.
- Eliminate external network requests and unnecessary disk thrashing.

### 1.3 Clean-Room State Isolation
- Test cases must never write to repository directories or alter shared user configuration.
- Always use `tempfile.TemporaryDirectory()` in `setUp()` and clean it up in `tearDown()`:
  ```python
  import tempfile
  from pathlib import Path
  import unittest

  class TestIsolatedComponent(unittest.TestCase):
      def setUp(self) -> None:
          self.temp_dir = tempfile.TemporaryDirectory()
          self.isolated_path = Path(self.temp_dir.name)

      def tearDown(self) -> None:
          self.temp_dir.cleanup()
  ```

---

## 2. Failure Transparency (Ground Rule 1 & Rule 2)

- **Zero bare `except:` blocks**: Never mask assertion failures or exceptions.
- **No Product Homework in Tests (Rule 2)**: Tests verify outcomes through black-box expectations and contract assertions; never duplicate production logic inside test asserts.
- Self-verifying tests must record deterministic status codes and exit non-zero upon any test failure.
