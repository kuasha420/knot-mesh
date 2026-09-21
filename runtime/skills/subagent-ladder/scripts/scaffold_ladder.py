#!/usr/bin/env python3
"""
Knot Mesh Subagent Ladder - Subagent Invocation Scaffolder
Loads canonical prompt templates and generates subagent specifications for Executioner, Hammer, and Auditor.
"""

import argparse
import json
import sys
from pathlib import Path


def get_template_dir() -> Path:
    script_dir = Path(__file__).resolve().parent
    template_dir = script_dir.parent / "templates"
    if not template_dir.is_dir():
        raise FileNotFoundError(f"Template directory not found: {template_dir}")
    return template_dir


def load_template(filename: str, phase: int, plan_path: str) -> str:
    template_file = get_template_dir() / filename
    if not template_file.is_file():
        raise FileNotFoundError(f"Template file not found: {template_file}")
    content = template_file.read_text(encoding="utf-8")
    return content.replace("{PHASE_NUMBER}", str(phase)).replace("{PLAN_PATH}", plan_path).strip()


def generate_executioner_spec(phase: int, plan_path: str, model: str = "flash") -> dict:
    prompt = load_template("executioner_prompt.md", phase, plan_path)
    return {
        "TypeName": "self",
        "Role": f"subagent-{phase}-executioner",
        "Model": model,
        "Prompt": prompt
    }


def generate_hammer_spec(phase: int, plan_path: str, model: str = "flash") -> dict:
    prompt = load_template("hammer_prompt.md", phase, plan_path)
    return {
        "TypeName": "research",
        "Role": f"subagent-{phase}-hammer",
        "Model": model,
        "Prompt": prompt
    }


def generate_auditor_spec(phase: int, plan_path: str, model: str = "flash") -> dict:
    prompt = load_template("auditor_prompt.md", phase, plan_path)
    return {
        "TypeName": "self",
        "Role": f"subagent-{phase}-auditor",
        "Model": model,
        "Prompt": prompt
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Knot Mesh Subagent Ladder Scaffolder")
    parser.add_argument("--phase", type=int, required=True, help="Phase number (e.g. 1, 2, 3...)")
    parser.add_argument("--role", choices=["executioner", "hammer", "auditor", "all"], required=True, help="Subagent role")
    parser.add_argument("--plan", default=None, help="Relative or bridged artifact path to the phase plan")
    parser.add_argument("--model", default="flash", choices=["flash", "pro", "inherit"], help="Model tier")

    args = parser.parse_args()
    plan_path = args.plan or f".agents/artifacts/phase_{args.phase}_plan.md"

    try:
        if args.role == "executioner":
            spec = generate_executioner_spec(args.phase, plan_path, args.model)
            print(json.dumps(spec, indent=2))
        elif args.role == "hammer":
            spec = generate_hammer_spec(args.phase, plan_path, args.model)
            print(json.dumps(spec, indent=2))
        elif args.role == "auditor":
            spec = generate_auditor_spec(args.phase, plan_path, args.model)
            print(json.dumps(spec, indent=2))
        elif args.role == "all":
            bundle = {
                "phase": args.phase,
                "subagents": [
                    generate_executioner_spec(args.phase, plan_path, args.model),
                    generate_hammer_spec(args.phase, plan_path, args.model),
                    generate_auditor_spec(args.phase, plan_path, args.model),
                ]
            }
            print(json.dumps(bundle, indent=2))
    except Exception as e:
        print(f"Error scaffolding ladder: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
