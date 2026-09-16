#!/usr/bin/env python3
"""
Knot Swarm Quota & Account Matrix View
Renders 5-hour and weekly Google AI Pro/Ultra model limits with account identity,
subscription tier, token refresh status, progress bars, and reset countdowns.
"""

import sys
import json
import re
import urllib.request
from datetime import datetime, timezone


def render_bar(fraction: float | None, is_offline: bool = False, width: int = 10) -> str:
    if is_offline and (fraction is None or fraction >= 0.99):
        return "\033[90m[OFFLINE   ]   -%     \033[0m"
    if fraction is None:
        return "\033[90m[NO DATA   ]   ?%     \033[0m"
    pct = max(0, min(100, int(round(fraction * 100))))
    filled = max(0, min(width, int(round(fraction * width))))
    bar = "█" * filled + "░" * (width - filled)

    if pct < 15:
        c = "\033[1;31m"  # Bold Red
        tag = "CRIT"
    elif pct < 40:
        c = "\033[1;33m"  # Bold Yellow
        tag = "LOW "
    else:
        c = "\033[1;32m"  # Bold Green
        tag = "OK  "
    reset = "\033[0m"
    return f"{c}[{bar}] {pct:3d}% ({tag}){reset}"


def fmt_reset(reset_iso: str) -> str:
    if not reset_iso:
        return "-"
    try:
        clean_iso = re.sub(r"(\.\d{6})\d+", r"\1", str(reset_iso))
        dt = datetime.fromisoformat(clean_iso.replace("Z", "+00:00"))
        now = datetime.now(timezone.utc)
        diff = dt - now
        secs = int(diff.total_seconds())
        if secs <= 0:
            return "Ready"
        hrs = secs // 3600
        mins = (secs % 3600) // 60
        days = hrs // 24
        if days > 0:
            rem_hrs = hrs % 24
            return f"in {days}d {rem_hrs}h"
        return f"in {hrs}h {mins}m"
    except Exception:
        return str(reset_iso)[:10]


def fmt_token_expiry(expiry_iso: str) -> str:
    if not expiry_iso:
        return "-"
    try:
        clean_iso = re.sub(r"(\.\d{6})\d+", r"\1", str(expiry_iso))
        dt = datetime.fromisoformat(clean_iso.replace("Z", "+00:00"))
        now = datetime.now(timezone.utc)
        diff = dt - now
        secs = int(diff.total_seconds())
        time_part = dt.astimezone().strftime("%H:%M:%S")
        if secs <= 0:
            return f"Expired ({time_part})"
        mins = secs // 60
        if mins < 60:
            return f"in {mins}m ({time_part})"
        hrs = mins // 60
        rem_mins = mins % 60
        return f"in {hrs}h {rem_mins}m ({time_part})"
    except Exception:
        return str(expiry_iso)[:19]


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "all"
    hub_url = sys.argv[2] if len(sys.argv) > 2 else "http://127.0.0.1:4242"

    try:
        req = urllib.request.Request(f"{hub_url}/nodes", headers={"Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=3.0) as resp:
            nodes = json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        print(f"\033[31m[!] Failed to connect to Knot Hub at {hub_url}: {e}\033[0m", file=sys.stderr)
        sys.exit(1)

    if target not in ("all", "--all"):
        nodes = [n for n in nodes if n.get("id") == target or n.get("hostname") == target]
        if not nodes:
            print(f"\033[31m[!] Node '{target}' not found on Hub.\033[0m", file=sys.stderr)
            sys.exit(1)

    bold = "\033[1m"
    reset = "\033[0m"
    cyan = "\033[1;36m"
    green = "\033[1;32m"
    yellow = "\033[1;33m"
    purple = "\033[1;35m"
    dim = "\033[90m"

    print(f"\n{bold}--- Knot Antigravity Swarm Quota & Account Matrix ---{reset}\n")

    for n in nodes:
        nid = n.get("id", "unknown")
        status = n.get("status", "ONLINE")
        is_offline = (status == "OFFLINE")
        qdata = n.get("quota_data") or {}
        if isinstance(qdata, str):
            try:
                qdata = json.loads(qdata)
            except Exception:
                qdata = {}

        account = n.get("account") or qdata.get("account") or {}
        email = account.get("email") or "unlinked"
        user_name = account.get("name") or ""
        sub_name = account.get("subscription") or "Google AI Pro"
        token_exp = account.get("token_expiry") or ""
        token_exp_str = fmt_token_expiry(token_exp) if token_exp else "-"

        # Status badge
        st_color = green if not is_offline else "\033[1;31m"
        st_badge = f"{st_color}[{status}]{reset}"

        # Account display string
        if user_name and email != "unlinked":
            user_display = f"{bold}{user_name}{reset} {dim}<{email}>{reset}"
        elif email != "unlinked":
            user_display = f"{dim}<{email}>{reset}"
        else:
            user_display = f"{yellow}No Google Account Linked{reset}"

        # Header line for node
        print(f"{cyan}● {nid}{reset} {st_badge}  •  {user_display}")
        print(f"  {purple}Plan:{reset} {bold}{sub_name}{reset}  {dim}│{reset}  {dim}Token Refresh:{reset} {token_exp_str}")

        # Quota table for this node
        header_fmt = "  %-18s %-32s %-32s %-18s %-18s\n"
        sys.stdout.write(dim)
        sys.stdout.write(header_fmt % ("MODEL GROUP", "5-HOUR LIMIT", "WEEKLY LIMIT", "NEXT 5H REFRESH", "NEXT WEEKLY REFRESH"))
        sys.stdout.write(header_fmt % ("-----------", "------------", "------------", "---------------", "-------------------"))
        sys.stdout.write(reset)

        # Gemini row
        g_5h = n.get("quota_5h_gemini") if qdata else None
        g_wk = n.get("quota_weekly_gemini") if qdata else None
        g_5h_reset = qdata.get("gemini_5h_reset", "")
        g_wk_reset = qdata.get("gemini_weekly_reset", "")

        bar_5h = render_bar(g_5h, is_offline=is_offline)
        bar_wk = render_bar(g_wk, is_offline=is_offline)
        rst_5h = fmt_reset(g_5h_reset)
        rst_wk = fmt_reset(g_wk_reset)
        print(f"  {'Gemini (Flash/Pro)':<18} {bar_5h}  {bar_wk}  {rst_5h:<18} {rst_wk:<18}")

        # Claude & 3P row
        p_5h = n.get("quota_5h_3p", 1.0) if qdata else None
        p_wk = n.get("quota_weekly_3p", 1.0) if qdata else None
        p_5h_reset = qdata.get("third_party_5h_reset", "")
        p_wk_reset = qdata.get("third_party_weekly_reset", "")

        bar_p5h = render_bar(p_5h, is_offline=is_offline)
        bar_pwk = render_bar(p_wk, is_offline=is_offline)
        rst_p5h = fmt_reset(p_5h_reset)
        rst_pwk = fmt_reset(p_wk_reset)
        print(f"  {'Claude & GPT':<18} {bar_p5h}  {bar_pwk}  {rst_p5h:<18} {rst_pwk:<18}")
        print("")


if __name__ == "__main__":
    main()
