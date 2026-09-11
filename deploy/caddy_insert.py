#!/usr/bin/env python3
"""Insert the Bsheel handles into a Caddyfile.

Two groups, each added only if missing, so a server that already has the
first can pick up the second on a later run:

  - /api/v1/* and /socket.io/*          — the API and the realtime gateway
  - the root-level paths                — /phone-signin-callback and the two
                                          /.well-known app-association files,
                                          which the OS and the browser fetch
                                          from the domain root and which the
                                          catch-all otherwise answers with the
                                          literal string "Bsheel API"

Called by caddy-apply.sh. Kept separate so it can be unit-tested against
sample Caddyfiles without touching a live server.

Design rule: refuse rather than guess. This edits a config that serves a live
production app, so any shape it does not fully understand is an error, not an
opportunity to be clever.

Exit codes:
    0  inserted, or already present (idempotent)
    1  refused — the message says why, and nothing was written
"""

import os
import re
import sys


def find_site_block(src, host="api.bsheel.app"):
    """Return (open_brace_index, close_brace_index) for the host's site block.

    Walks the file tracking brace depth rather than matching a regex against
    the whole address list. Caddy separates site addresses with commas AND/OR
    whitespace (`api.bsheel.app, www.api.bsheel.app {`), and a regex built
    around whitespace silently missed the comma form — which would have made
    this refuse to edit a perfectly ordinary Caddyfile.
    """
    depth = 0
    offset = 0
    for line in src.splitlines(keepends=True):
        stripped = line.strip()
        if depth == 0 and "{" in line and not stripped.startswith("#"):
            raw = re.split(r"[,\s]+", line.split("{", 1)[0].strip())
            # Site addresses may carry a scheme and/or a port
            # (`https://api.bsheel.app:443`). Normalise both away before
            # comparing, or a valid config gets refused for no reason.
            addresses = [
                re.sub(r":\d+$", "", a.split("://", 1)[-1]) for a in raw if a
            ]
            if host in addresses:
                open_idx = offset + line.index("{")
                inner = 0
                for i in range(open_idx, len(src)):
                    if src[i] == "{":
                        inner += 1
                    elif src[i] == "}":
                        inner -= 1
                        if inner == 0:
                            return open_idx, i
                return None, None
        if not stripped.startswith("#"):
            depth += line.count("{") - line.count("}")
        offset += len(line)
    return None, None


def bare_terminal_directive(body):
    """Find a top-level reverse_proxy/respond/file_server in the block body.

    Such a directive matches every path, so handles added beside it would
    never be reached. Rewriting a live config to fix that is a human's call.
    """
    depth = 0
    for line in body.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if depth == 0 and re.match(r"^(reverse_proxy|respond|file_server)\b", stripped):
            return stripped.split()[0]
        depth += stripped.count("{") - stripped.count("}")
    return None


ROOT_PATHS = (
    "/phone-signin-callback",
    "/.well-known/apple-app-site-association",
    "/.well-known/assetlinks.json",
)
ROOT_MATCHER = "@bsheel_root"


def build_root_block(upstream, indent="\t"):
    """The root-level paths the API serves outside /api/v1.

    Number Verification lands the browser on /phone-signin-callback, and
    iOS/Android fetch the app-association files from the domain root without
    following redirects. None of the three can live under /api/v1, so without
    this route the site's catch-all answers them — and the app never learns
    it owns the link. A named matcher rather than three handles, so there is
    one thing to grep for.
    """
    return (
        f"\n{indent}# --- Bsheel root paths (added by deploy/caddy-apply.sh) ---\n"
        f"{indent}# Number Verification's landing page and the iOS/Android app-\n"
        f"{indent}# association files. Fetched from the domain root, so they\n"
        f"{indent}# cannot live under /api/v1; without this the catch-all below\n"
        f"{indent}# answers them with the literal string \"Bsheel API\".\n"
        f"{indent}{ROOT_MATCHER} path {' '.join(ROOT_PATHS)}\n"
        f"{indent}handle {ROOT_MATCHER} {{\n"
        f"{indent}\treverse_proxy {upstream}\n"
        f"{indent}}}\n"
        f"{indent}# --- end Bsheel root paths ---\n"
    )


def build_block(upstream, indent="\t"):
    return (
        f"\n{indent}# --- Bsheel API (added by deploy/caddy-apply.sh) ---\n"
        f"{indent}handle /api/v1/* {{\n"
        f"{indent}\treverse_proxy {upstream}\n"
        f"{indent}}}\n"
        f"{indent}# Socket.IO wire path. The gateway's /realtime namespace is\n"
        f"{indent}# negotiated inside the connection, so it never appears in the\n"
        f"{indent}# URL and cannot collide with Supabase's /realtime/v1.\n"
        f"{indent}# Caddy upgrades WebSockets automatically.\n"
        f"{indent}handle /socket.io/* {{\n"
        f"{indent}\treverse_proxy {upstream}\n"
        f"{indent}}}\n"
        f"{indent}# --- end Bsheel API ---\n"
    )


def insert(src, upstream):
    """Return the edited config, None if nothing is missing, or raise ValueError."""
    need_api = not ("/api/v1/*" in src and "/socket.io/*" in src)
    need_root = ROOT_MATCHER not in src
    if not need_api and not need_root:
        return None  # already present

    open_idx, close_idx = find_site_block(src)
    if open_idx is None:
        raise ValueError("no api.bsheel.app site block found in this Caddyfile")

    body = src[open_idx + 1 : close_idx]

    bare = bare_terminal_directive(body)
    if bare:
        raise ValueError(
            f"the api.bsheel.app block has a bare top-level '{bare}'.\n"
            "       It matches every path, so the handles below would never be\n"
            "       reached. Wrap the existing directive in `handle { ... }`\n"
            "       first, then re-run. Refusing to rewrite a live config."
        )

    lines = [ln for ln in body.splitlines() if ln.strip()]
    indent = re.match(r"[ \t]*", lines[0]).group(0) if lines else "\t"
    # Both go at the top of the block. `handle` blocks with matchers are
    # tried before a matcher-less catch-all whatever the order, but the
    # imported Supabase handle is a named matcher too, so position is what
    # keeps ours ahead of anything a future snippet might claim.
    added = ""
    if need_api:
        added += build_block(upstream, indent or "\t")
    if need_root:
        added += build_root_block(upstream, indent or "\t")
    return src[: open_idx + 1] + added + src[open_idx + 1 :]


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: caddy_insert.py <path-to-Caddyfile>")
    path = sys.argv[1]
    # The upstream is a container alias, not loopback: Caddy runs inside a
    # container here, so 127.0.0.1 there is its own loopback, not the host's.
    upstream = os.environ.get("API_UPSTREAM", "bsheel-api:3000")

    with open(path) as handle:
        src = handle.read()

    try:
        result = insert(src, upstream)
    except ValueError as error:
        print(f"  REFUSED: {error}")
        return 1

    if result is None:
        print("  routes already present — nothing to do (idempotent)")
        return 0

    with open(path, "w") as handle:
        handle.write(result)
    added = []
    if "/api/v1/*" not in src:
        added.append("/api/v1 + /socket.io handles")
    if ROOT_MATCHER not in src:
        added.append(f"{ROOT_MATCHER} handle ({', '.join(ROOT_PATHS)})")
    print(f"  inserted {' and '.join(added)} -> {upstream}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
