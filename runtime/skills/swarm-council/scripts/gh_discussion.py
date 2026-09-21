#!/usr/bin/env python3
"""
Swarm Council: Stage 2 GitHub Discussions GraphQL & REST Client
Handles token-efficient thread creation, delta comment polling, and structured replies.
"""

import sys
import json
import subprocess
import argparse

def run_gh(args):
    cmd = ["gh"] + args
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"gh command failed ({res.returncode}): {res.stderr.strip()}")
    return res.stdout.strip()

def ensure_discussions(owner, repo):
    check_query = f"""
    query {{
      repository(owner: "{owner}", name: "{repo}") {{
        id
        hasDiscussionsEnabled
        discussionCategories(first: 10) {{
          nodes {{
            id
            name
            slug
          }}
        }}
      }}
    }}
    """
    out = run_gh(["api", "graphql", "-f", f"query={check_query}"])
    data = json.loads(out)["data"]["repository"]
    repo_id = data["id"]
    enabled = data["hasDiscussionsEnabled"]
    categories = data["discussionCategories"]["nodes"]

    if not enabled:
        # Dynamically enable discussions
        run_gh(["api", "-X", "PATCH", f"/repos/{owner}/{repo}", "-f", "has_discussions=true"])
        # Re-fetch categories
        out = run_gh(["api", "graphql", "-f", f"query={check_query}"])
        categories = json.loads(out)["data"]["repository"]["discussionCategories"]["nodes"]

    return repo_id, categories

def create_thread(owner, repo, title, body, category_slug="general"):
    repo_id, categories = ensure_discussions(owner, repo)
    
    cat_id = None
    for c in categories:
        if c["slug"] == category_slug:
            cat_id = c["id"]
            break
    if not cat_id and categories:
        cat_id = categories[0]["id"]
    
    if not cat_id:
        raise RuntimeError("No discussion categories found on repository.")

    # GraphQL createDiscussion mutation
    mutation = """
    mutation($repoId: ID!, $catId: ID!, $title: String!, $body: String!) {
      createDiscussion(input: {repositoryId: $repoId, categoryId: $catId, title: $title, body: $body}) {
        discussion {
          id
          number
          url
          title
        }
      }
    }
    """
    out = run_gh([
        "api", "graphql",
        "-f", f"query={mutation}",
        "-F", f"repoId={repo_id}",
        "-F", f"catId={cat_id}",
        "-F", f"title={title}",
        "-F", f"body={body}"
    ])
    disc = json.loads(out)["data"]["createDiscussion"]["discussion"]
    return disc

def post_reply(discussion_id, body, node_id, run_id, status):
    header = f"<!-- KNOT-NODE: {node_id} | RUN: {run_id} | STATUS: {status} -->\n"
    full_body = header + body

    mutation = """
    mutation($discId: ID!, $body: String!) {
      addDiscussionComment(input: {discussionId: $discId, body: $body}) {
        comment {
          id
          url
          createdAt
        }
      }
    }
    """
    out = run_gh([
        "api", "graphql",
        "-f", f"query={mutation}",
        "-F", f"discId={discussion_id}",
        "-F", f"body={full_body}"
    ])
    comment = json.loads(out)["data"]["addDiscussionComment"]["comment"]
    return comment

def poll_delta(discussion_id, last_count=0):
    query = f"""
    query {{
      node(id: "{discussion_id}") {{
        ... on Discussion {{
          comments(first: 100) {{
            totalCount
            nodes {{
              id
              createdAt
              author {{
                login
              }}
              body
            }}
          }}
        }}
      }}
    }}
    """
    out = run_gh(["api", "graphql", "-f", f"query={query}"])
    disc_node = json.loads(out)["data"]["node"]
    if not disc_node:
        return {"totalCount": 0, "new_comments": []}
    
    total = disc_node["comments"]["totalCount"]
    all_comments = disc_node["comments"]["nodes"]
    
    if total <= last_count:
        return {"totalCount": total, "new_comments": []}
    
    new_comments = all_comments[last_count:]
    return {"totalCount": total, "new_comments": new_comments}

def get_full_thread(discussion_id):
    query = f"""
    query {{
      node(id: "{discussion_id}") {{
        ... on Discussion {{
          id
          number
          title
          url
          body
          createdAt
          comments(first: 100) {{
            totalCount
            nodes {{
              id
              createdAt
              author {{
                login
              }}
              body
            }}
          }}
        }}
      }}
    }}
    """
    out = run_gh(["api", "graphql", "-f", f"query={query}"])
    return json.loads(out)["data"]["node"]

def resolve_repo(owner="", repo=""):
    if owner and repo:
        return owner, repo
    try:
        url = subprocess.check_output(["git", "config", "--get", "remote.origin.url"], text=True, stderr=subprocess.DEVNULL).strip()
        import re
        m = re.search(r"github\.com[:/]([^/]+)/([^/.]+)(?:\.git)?", url)
        if m:
            det_owner, det_repo = m.group(1), m.group(2)
            return owner or det_owner, repo or det_repo
    except Exception:
        pass
    return owner or "kuasha420", repo or "knot-mesh"

def main():
    parser = argparse.ArgumentParser(description="Swarm Council GitHub Discussions Helper")
    subparsers = parser.add_subparsers(dest="cmd")

    create_p = subparsers.add_parser("create")
    create_p.add_argument("--owner", default="")
    create_p.add_argument("--repo", default="")
    create_p.add_argument("--title", required=True)
    create_p.add_argument("--body", required=True)
    create_p.add_argument("--category", default="general")

    reply_p = subparsers.add_parser("reply")
    reply_p.add_argument("--discussion-id", required=True)
    reply_p.add_argument("--body", required=True)
    reply_p.add_argument("--node-id", required=True)
    reply_p.add_argument("--run-id", required=True)
    reply_p.add_argument("--status", default="PROGRESS")

    poll_p = subparsers.add_parser("poll_delta")
    poll_p.add_argument("--discussion-id", required=True)
    poll_p.add_argument("--last-count", type=int, default=0)

    thread_p = subparsers.add_parser("get_thread")
    thread_p.add_argument("--discussion-id", required=True)

    args = parser.parse_args()

    if args.cmd == "create":
        owner, repo = resolve_repo(args.owner, args.repo)
        body = args.body.replace('\\n', '\n')
        res = create_thread(owner, repo, args.title, body, args.category)
        print(json.dumps(res, indent=2))
    elif args.cmd == "reply":
        body = args.body.replace('\\n', '\n')
        res = post_reply(args.discussion_id, body, args.node_id, args.run_id, args.status)
        print(json.dumps(res, indent=2))
    elif args.cmd == "poll_delta":
        res = poll_delta(args.discussion_id, args.last_count)
        print(json.dumps(res, indent=2))
    elif args.cmd == "get_thread":
        res = get_full_thread(args.discussion_id)
        print(json.dumps(res, indent=2))
    else:
        parser.print_help()
        sys.exit(1)

if __name__ == "__main__":
    main()
