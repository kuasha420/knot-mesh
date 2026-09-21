#!/usr/bin/env python3
"""
Standardized Swarm Council Cryptographic Challenge Tool
Provides deterministic challenge generation, ultra-fast verification,
and local solving for tournament volleys across the Knot mesh.
"""
import sys
import time
import hashlib
import argparse


def compute_sha256(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def verify_challenge(candidate: str, difficulty: int, keyword: str = "") -> tuple[bool, str, str]:
    """
    Verifies if candidate string satisfies:
    1. SHA-256 starts with `difficulty` leading zeros.
    2. Candidate string contains `keyword` (if provided).
    Returns (is_valid, digest, reason)
    """
    if not candidate:
        return False, "", "Candidate string is empty"
    
    if keyword and keyword.lower() not in candidate.lower():
        return False, "", f"Candidate does not contain required keyword '{keyword}'"
    
    digest = compute_sha256(candidate)
    target_prefix = "0" * difficulty
    if not digest.startswith(target_prefix):
        return False, digest, f"Hash {digest} does not start with {difficulty} leading zeros ('{target_prefix}')"
    
    return True, digest, "OK"


def solve_challenge(prefix: str, difficulty: int, keyword: str, max_iterations: int = 10_000_000) -> tuple[str, str, float]:
    """
    Brute-forces a nonce satisfying difficulty and keyword.
    Returns (solution_string, hash_digest, elapsed_ms)
    """
    target = "0" * difficulty
    base = f"{prefix}-{keyword}-" if keyword not in prefix else f"{prefix}-"
    start_time = time.perf_counter()
    
    for nonce in range(max_iterations):
        candidate = f"{base}{nonce}"
        digest = hashlib.sha256(candidate.encode("utf-8")).hexdigest()
        if digest.startswith(target):
            elapsed_ms = (time.perf_counter() - start_time) * 1000.0
            return candidate, digest, elapsed_ms
            
    raise RuntimeError(f"Failed to find solution within {max_iterations} iterations for difficulty {difficulty}")


def main():
    parser = argparse.ArgumentParser(description="Knot Swarm Council Challenge Tool")
    subparsers = parser.add_subparsers(dest="action", required=True)

    # Generate
    gen_p = subparsers.add_parser("generate", help="Generate a standardized puzzle description")
    gen_p.add_argument("--difficulty", type=int, default=4, help="Required leading zeros (default: 4)")
    gen_p.add_argument("--keyword", type=str, default="KNOT", help="Required keyword in candidate")
    gen_p.add_argument("--prefix", type=str, default="KNOT-CHALLENGE", help="Prefix for candidate string")

    # Verify
    ver_p = subparsers.add_parser("verify", help="Verify a solution candidate string")
    ver_p.add_argument("--string", type=str, required=True, help="Candidate solution string to verify")
    ver_p.add_argument("--difficulty", type=int, default=4, help="Target leading zeros count")
    ver_p.add_argument("--keyword", type=str, default="", help="Expected keyword (optional)")

    # Solve
    sol_p = subparsers.add_parser("solve", help="Solve a challenge using local compute")
    sol_p.add_argument("--difficulty", type=int, default=4, help="Required leading zeros count")
    sol_p.add_argument("--keyword", type=str, default="KNOT", help="Required keyword")
    sol_p.add_argument("--prefix", type=str, default="KNOT-SET", help="Candidate prefix")

    args = parser.parse_args()

    if args.action == "generate":
        print(f"Target: Find a string starting with '{args.prefix}-' such that SHA256(string) has at least {args.difficulty} leading zeros ('{'0'*args.difficulty}') and contains '{args.keyword}'.")
        sys.exit(0)

    elif args.action == "verify":
        valid, digest, reason = verify_challenge(args.string, args.difficulty, args.keyword)
        if valid:
            print(f"[✓] VALID: String='{args.string}' | SHA256={digest} | Leading Zeros={args.difficulty}")
            sys.exit(0)
        else:
            print(f"[✗] INVALID: {reason} (Candidate: '{args.string}', Hash: '{digest}')", file=sys.stderr)
            sys.exit(1)

    elif args.action == "solve":
        candidate, digest, ms = solve_challenge(args.prefix, args.difficulty, args.keyword)
        print(f"[✓] SOLVED in {ms:.2f}ms | String='{candidate}' | SHA256={digest}")
        sys.exit(0)


if __name__ == "__main__":
    main()
