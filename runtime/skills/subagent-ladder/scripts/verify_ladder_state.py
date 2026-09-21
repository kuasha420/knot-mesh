#!/usr/bin/env python3
"""
Knot Mesh Subagent Ladder - State Machine & Protocol Compliance Verifier
Audits Antigravity transcripts to verify strict adherence to:
1. The Hammer Anti-Bypass Rule (No Executioner remedy jumping straight to Auditor).
2. The Zero Coordinator Remediation Invariant (Coordinator never modifies code directly).
3. Metric summaries (step count, tool counts, duration).
"""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path


def audit_transcript(log_path: Path) -> dict:
    if not log_path.is_file():
        raise FileNotFoundError(f"Transcript file not found: {log_path}")

    with log_path.open("r", encoding="utf-8", errors="replace") as f:
        lines = [line.strip() for line in f if line.strip()]

    coordinator_edits = []
    invocations = []
    tool_counts = {}
    first_dt = None
    last_dt = None

    for idx, raw in enumerate(lines):
        try:
            entry = json.loads(raw)
        except Exception:
            continue

        ts = entry.get("created_at")
        if ts:
            dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
            if first_dt is None:
                first_dt = dt
            last_dt = dt

        tool_calls = entry.get("tool_calls") or []
        for tc in tool_calls:
            name = tc.get("name")
            tool_counts[name] = tool_counts.get(name, 0) + 1
            args = tc.get("args") or {}
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except Exception:
                    args = {}

            # Check for direct coordinator file modifications
            if name in ("write_to_file", "replace_file_content"):
                target = args.get("TargetFile", "")
                # Ignore brain/artifact edits or scratch files
                if target and not ("/brain/" in target or "/scratch/" in target or target.endswith(".md")):
                    coordinator_edits.append({
                        "step": entry.get("step_index", idx),
                        "tool": name,
                        "file": target
                    })

            # Track subagent invocations
            if name == "invoke_subagent":
                subagents = args.get("Subagents", [])
                for sa in subagents:
                    if isinstance(sa, dict):
                        invocations.append({
                            "step": entry.get("step_index", idx),
                            "role": sa.get("Role", "unknown"),
                            "model": sa.get("Model", "unknown"),
                            "prompt_preview": sa.get("Prompt", "")[:120].replace("\n", " ")
                        })

    # State Machine Sequence Analysis
    # Sequence should ideally progress: executioner -> hammer -> auditor
    # If executioner runs again (remedy), next must be hammer, NOT auditor.
    state_machine_violations = []
    for i in range(len(invocations) - 1):
        curr_role = invocations[i]["role"].lower()
        next_role = invocations[i + 1]["role"].lower()
        
        # If an executioner ran, and the next subagent was an auditor (skipping hammer)
        if "executioner" in curr_role and "auditor" in next_role:
            state_machine_violations.append({
                "from_step": invocations[i]["step"],
                "from_role": invocations[i]["role"],
                "to_step": invocations[i + 1]["step"],
                "to_role": invocations[i + 1]["role"],
                "violation": "Executioner output routed directly to Auditor, bypassing Hammer code review!"
            })

    duration_sec = (last_dt - first_dt).total_seconds() if (last_dt and first_dt) else 0

    return {
        "log_path": str(log_path),
        "total_steps": len(lines),
        "total_tool_calls": sum(tool_counts.values()),
        "duration_sec": duration_sec,
        "tool_breakdown": tool_counts,
        "total_subagents_invoked": len(invocations),
        "subagent_invocations": invocations,
        "coordinator_code_edits": coordinator_edits,
        "state_machine_violations": state_machine_violations,
        "compliant": (len(coordinator_edits) == 0 and len(state_machine_violations) == 0)
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Knot Mesh Subagent Ladder Transcripts Compliance Verifier")
    parser.add_argument("--log", required=True, help="Path to transcript.jsonl")
    parser.add_argument("--json", action="store_true", help="Output raw JSON results")

    args = parser.parse_args()
    log_path = Path(args.log).resolve()

    try:
        report = audit_transcript(log_path)
    except Exception as e:
        print(f"Error parsing transcript: {e}", file=sys.stderr)
        sys.exit(1)

    if args.json:
        print(json.dumps(report, indent=2))
        sys.exit(0 if report["compliant"] else 1)

    print("=== Subagent Ladder Transcripts Audit Report ===")
    print(f"Transcript: {report['log_path']}")
    print(f"Total Steps: {report['total_steps']} | Tool Calls: {report['total_tool_calls']} | Duration: {report['duration_sec']:.1f}s")
    print(f"Subagents Spawned: {report['total_subagents_invoked']}")
    
    print("\n--- Invariant Checks ---")
    if not report["coordinator_code_edits"]:
        print("  [✓] Zero Coordinator Code Modifications: PASSED")
    else:
        print(f"  [✗] Coordinator Code Modifications: FAILED ({len(report['coordinator_code_edits'])} unauthorized edits)")
        for edit in report["coordinator_code_edits"]:
            print(f"      • Step {edit['step']}: {edit['tool']} on {edit['file']}")

    if not report["state_machine_violations"]:
        print("  [✓] Hammer Anti-Bypass State Machine: PASSED")
    else:
        print(f"  [!] State Machine Bypass Warnings: {len(report['state_machine_violations'])}")
        for v in report["state_machine_violations"]:
            print(f"      • Step {v['from_step']} ({v['from_role']}) -> Step {v['to_step']} ({v['to_role']}): {v['violation']}")

    if report["compliant"]:
        print("\n[✓] OVERALL VERDICT: COMPLIANT WITH PSL SUBAGENT LADDER PROTOCOL")
        sys.exit(0)
    else:
        print("\n[✗] OVERALL VERDICT: NON-COMPLIANT")
        sys.exit(1)


if __name__ == "__main__":
    main()
