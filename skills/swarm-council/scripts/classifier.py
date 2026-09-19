#!/usr/bin/env python3
"""
Swarm Council: Dual Ensemble Mode Classifier
Combines deterministic rubric feature-scoring with local AI inference,
displaying comparative trade-offs and an interactive 5-second countdown override.
"""

import os
import sys
import json
import time
import select
import argparse
import subprocess

def score_rubric(prompt, dataset):
    prompt_lower = prompt.lower()
    modes = dataset.get("modes", {})
    scores = {m: 0.0 for m in modes}

    # Keyword indicators
    keywords = {
        "visual_ui": ["ui", "css", "html", "glassmorphism", "tailwind", "design", "frontend", "diagram", "chart"],
        "generative_ui": ["generative ui", "interactive widget", "svg canvas", "artifact feedback"],
        "browser_devtools": ["browser", "devtools", "a11y", "accessibility", "dom", "screenshot"],
        "interactive_plan": ["plan approval", "user feedback", "interview", "step by step review"],
        "multi_node": ["all nodes", "fleet", "mesh", "swarm", "desktop", "laptop", "rog-ally", "steamdeck", "cross-node", "parallel"],
        "interactive_monitoring": ["monitor", "watch", "live stream", "supervise", "tui", "cockpit", "observe"],
        "cross_mesh_sync": ["sync", "parity", "audit", "compiler", "handshake", "kvm", "deskflow"],
        "unattended_batch": ["unattended", "headless", "batch", "nightly", "cron", "scheduled", "background", "overnight", "ci/cd"],
        "nightly_ci": ["ci", "regression", "test suite", "pass/fail", "matrix"],
        "hardware_ergonomics": ["battery", "gamepad", "handheld", "power profile", "touch", "thermal", "dock"]
    }

    detected_tags = []
    for tag, terms in keywords.items():
        if any(term in prompt_lower for term in terms):
            detected_tags.append(tag)

    # Score modes based on weights
    for m, mdata in modes.items():
        weights = mdata.get("scoring_weights", {})
        for tag in detected_tags:
            scores[m] += weights.get(tag, 0.0)

    # Base bias: confluence is preferred default for multi-node knot tasks
    scores["confluence"] += 1.0

    # Normalize to percentages
    min_s = min(scores.values())
    shifted = {k: v - min_s + 0.1 for k, v in scores.items()}
    total = sum(shifted.values())
    percentages = {k: round((v / total) * 100, 1) for k, v in shifted.items()}
    top_mode = max(percentages, key=percentages.get)

    return top_mode, percentages, detected_tags

def run_local_ai_inference(prompt, timeout_sec=4):
    """
    Fast, non-blocking local classification via agy -p
    """
    classify_prompt = (
        "Classify the following task prompt into exactly one of: [confluence, headless, tui, gui].\n"
        "- confluence: multi-node distributed audits, live terminal oversight, parallel fleet tasks.\n"
        "- headless: unattended batch, overnight cron, CI regression, background maintenance.\n"
        "- tui: single-device hardware testing, local screen/gamepad ergonomics.\n"
        "- gui: frontend CSS/HTML design, visual browser devtools, interactive artifact review.\n\n"
        f"Task Prompt: \"{prompt[:300]}\"\n\n"
        "Reply with ONLY valid JSON: {\"mode\": \"<confluence|headless|tui|gui>\", \"rationale\": \"<one sentence>\"}"
    )

    try:
        proc = subprocess.run(
            ["agy", "-p", classify_prompt, "--output-format", "json"],
            capture_output=True,
            text=True,
            timeout=timeout_sec
        )
        if proc.returncode == 0:
            out = proc.stdout.strip()
            # Extract json block
            for line in out.splitlines():
                if line.startswith("{") and "mode" in line:
                    data = json.loads(line)
                    res = data.get("response", "")
                    # Find inner json
                    import re
                    match = re.search(r'\{.*"mode":\s*"([^"]+)".*\}', res, re.DOTALL)
                    if match:
                        inner = json.loads(match.group(0))
                        return inner.get("mode"), inner.get("rationale", "")
    except Exception:
        pass
    return None, None

def main():
    parser = argparse.ArgumentParser(description="Swarm Council Dual Ensemble Classifier")
    parser.add_argument("--prompt", default="", help="Task prompt text")
    parser.add_argument("--prompt-file", default="", help="Path to file containing task prompt")
    parser.add_argument("--timeout", type=int, default=5, help="Countdown seconds for interactive override")
    parser.add_argument("--json", action="store_true", help="Output machine-readable JSON")
    parser.add_argument("--non-interactive", action="store_true", help="Auto-accept top suggestion without prompt")

    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.realpath(__file__))
    dataset_file = os.path.join(script_dir, "../templates/dataset_modes.json")

    prompt = ""
    if args.prompt_file and os.path.isfile(args.prompt_file):
        with open(args.prompt_file) as f:
            prompt = f.read().strip()
    elif args.prompt:
        prompt = args.prompt.strip()
    else:
        prompt = "Audit private prototype to public transition across all nodes."

    dataset = {}
    if os.path.exists(dataset_file):
        with open(dataset_file) as df:
            dataset = json.load(df)

    # 1. Deterministic Rubric
    rubric_mode, rubric_percentages, detected_tags = score_rubric(prompt, dataset)

    # 2. Local AI Inference
    ai_mode, ai_rationale = run_local_ai_inference(prompt, timeout_sec=3)

    # 3. Consensus Synthesis
    if ai_mode and ai_mode in rubric_percentages:
        if ai_mode == rubric_mode:
            final_mode = rubric_mode
            confidence = "HIGH (Consensus)"
            rationale = ai_rationale or f"Rubric and AI inference agree on {final_mode} based on: {', '.join(detected_tags)}"
        else:
            # Nuanced divergence: default to rubric, surface trade-off
            final_mode = rubric_mode
            confidence = "BALANCED (Divergent Trade-off)"
            rationale = f"Rubric prefers {rubric_mode} ({rubric_percentages.get(rubric_mode)}%), while AI suggests {ai_mode}: {ai_rationale}"
    else:
        final_mode = rubric_mode
        confidence = "HIGH (Rubric Vector)"
        rationale = f"Deterministic rubric score based on tags: {', '.join(detected_tags)}"

    result = {
        "suggested_mode": final_mode,
        "confidence": confidence,
        "rationale": rationale,
        "rubric_scores": rubric_percentages,
        "detected_tags": detected_tags,
        "ai_inference": {"mode": ai_mode, "rationale": ai_rationale} if ai_mode else None
    }

    if args.json or args.non_interactive:
        if args.json:
            print(json.dumps(result, indent=2))
        else:
            print(final_mode)
        return

    # Interactive UI display with countdown
    C_CYAN = "\033[0;36m"
    C_GREEN = "\033[0;32m"
    C_YELLOW = "\033[0;33m"
    C_BOLD = "\033[1m"
    C_RESET = "\033[0m"

    print(f"\n{C_BOLD}┌────────────────────────────────────────────────────────────────────────┐{C_RESET}")
    print(f"{C_BOLD}│                      SWARM COUNCIL MODE SELECTION                      │{C_RESET}")
    print(f"{C_BOLD}├────────────────────────────────────────────────────────────────────────┤{C_RESET}")
    print(f"│ {C_BOLD}Suggested Mode:{C_RESET} {C_GREEN}{final_mode.upper()}{C_RESET} [{confidence}]")
    print(f"│ {C_BOLD}Rationale:{C_RESET} {rationale}")
    print(f"│ {C_BOLD}Rubric Distribution:{C_RESET} " + " | ".join([f"{k}: {v}%" for k, v in rubric_percentages.items()]))
    print(f"{C_BOLD}├────────────────────────────────────────────────────────────────────────┤{C_RESET}")
    print(f"│ Press {C_CYAN}[Enter]{C_RESET} to accept, or override: {C_YELLOW}[c]onfluence{C_RESET} | {C_YELLOW}[h]eadless{C_RESET} | {C_YELLOW}[t]ui{C_RESET} | {C_YELLOW}[g]ui{C_RESET}")
    print(f"{C_BOLD}└────────────────────────────────────────────────────────────────────────┘{C_RESET}")

    selected_mode = final_mode
    countdown = args.timeout

    print(f"Auto-accepting in {countdown}s (press Enter or key to select): ", end="", flush=True)

    start_time = time.time()
    while time.time() - start_time < countdown:
        remaining = int(countdown - (time.time() - start_time)) + 1
        rlist, _, _ = select.select([sys.stdin], [], [], 0.5)
        if rlist:
            char = sys.stdin.readline().strip().lower()
            if char in ["c", "confluence"]:
                selected_mode = "confluence"
            elif char in ["h", "headless"]:
                selected_mode = "headless"
            elif char in ["t", "tui"]:
                selected_mode = "tui"
            elif char in ["g", "gui"]:
                selected_mode = "gui"
            elif char == "":
                selected_mode = final_mode
            break
        print(f"\rAuto-accepting in {remaining}s (press Enter or key to select): ", end="", flush=True)

    print(f"\nSelected mode: {selected_mode}")
    print(selected_mode)

if __name__ == "__main__":
    main()
