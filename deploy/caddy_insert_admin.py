#!/usr/bin/env python3
"""Insert the Bsheel admin dashboard route into the admin.bsheel.app block.

Reuses caddy_insert's block finder and its refusal rules. The bundle is served
from a /v2/ subpath because the legacy quest-app admin already owns `/` on that
host behind basic auth, and taking `/` would remove the tool its moderators
use today.

Exit codes:
    0  inserted, or already present (idempotent)
    1  refused — nothing written
"""
import os
import re
import sys

from caddy_insert import bare_terminal_directive, find_site_block

HOST = "admin.bsheel.app"
DOC_ROOT = os.environ.get("ADMIN_DOC_ROOT", "/srv/admin")
SUBPATH = os.environ.get("ADMIN_SUBPATH", "/v2")


def build_block(indent="\t"):
    return (
        f"\n{indent}# --- Bsheel admin dashboard (added by deploy) ---\n"
        f"{indent}# Served from {SUBPATH}/ because the legacy admin owns / on\n"
        f"{indent}# this host. The bundle is built with --base-href={SUBPATH}/.\n"
        f"{indent}#\n"
        f"{indent}# try_files is required, not optional: admin_web calls\n"
        f"{indent}# usePathUrlStrategy(), so {SUBPATH}/moderation is a real URL the\n"
        f"{indent}# browser requests on reload. Without the fallback it 404s\n"
        f"{indent}# instead of booting the app.\n"
        f"{indent}handle {SUBPATH}/* {{\n"
        f"{indent}\troot * {DOC_ROOT}\n"
        f"{indent}\ttry_files {{path}} {SUBPATH}/index.html\n"
        f"{indent}\tfile_server\n"
        f"{indent}}}\n"
        f"{indent}# --- end Bsheel admin dashboard ---\n"
    )


def insert(src):
    if f"handle {SUBPATH}/*" in src:
        return None

    open_idx, close_idx = find_site_block(src, HOST)
    if open_idx is None:
        raise ValueError(f"no {HOST} site block found in this Caddyfile")

    body = src[open_idx + 1 : close_idx]
    bare = bare_terminal_directive(body)
    if bare:
        raise ValueError(
            f"the {HOST} block has a bare top-level '{bare}'.\n"
            "       It matches every path, so the handle below would never be\n"
            "       reached. Wrap it in `handle { ... }` first, then re-run."
        )

    lines = [ln for ln in body.splitlines() if ln.strip()]
    indent = re.match(r"[ \t]*", lines[0]).group(0) if lines else "\t"
    return src[: open_idx + 1] + build_block(indent or "\t") + src[open_idx + 1 :]


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: caddy_insert_admin.py <path-to-Caddyfile>")
    path = sys.argv[1]
    with open(path) as handle:
        src = handle.read()
    try:
        result = insert(src)
    except ValueError as error:
        print(f"  REFUSED: {error}")
        return 1
    if result is None:
        print(f"  {SUBPATH} route already present — nothing to do (idempotent)")
        return 0
    with open(path, "w") as handle:
        handle.write(result)
    print(f"  inserted {SUBPATH}/* -> file_server from {DOC_ROOT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
