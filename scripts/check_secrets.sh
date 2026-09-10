#!/usr/bin/env bash
# ============================================================
# Committed-secret guard.
#
# Why this exists: on 2026-08-04 a live `service_role` JWT — valid until
# 2036, bypassing every RLS policy including the 0143 lockdown — was found
# committed in docs/api/bsheel-selfhosted-api.postman_collection.json,
# present on origin/main since commit 6520808.
#
# Nothing caught it:
#   * `grep service_role` finds NOTHING — the role is inside the base64
#     JWT payload, not the file text.
#   * GitHub secret scanning is unavailable on this repo (private repo
#     without Advanced Security), and most off-the-shelf rules only match
#     provider-branded key formats, not self-signed Supabase JWTs.
#
# So we decode every JWT-shaped string in tracked files and fail on any
# privileged role. Cheap, and targets the exact hole we fell into.
#
# Usage:  bash scripts/check_secrets.sh
# Exit:   0 clean, 1 secret found
# ============================================================
set -uo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'
FAIL=0

# Roles that must NEVER appear in a committed JWT.
# `anon` is intentionally allowed: it is embedded in every shipped app
# binary via --dart-define and is public by design. RLS is the boundary.
FORBIDDEN_ROLES="service_role|supabase_admin|postgres"

b64url_decode() {
  local p="${1//-/+}"; p="${p//_//}"
  local pad=$(( (4 - ${#p} % 4) % 4 ))
  for ((i=0; i<pad; i++)); do p="${p}="; done
  printf '%s' "$p" | base64 -d 2>/dev/null
}

echo "Scanning tracked files for privileged JWTs..."

while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$f" in *.jks|*.png|*.jpg|*.ico|*.ttf|*.otf|*.zip) continue ;; esac

  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    payload="$(b64url_decode "$(printf '%s' "$tok" | cut -d. -f2)")"
    [ -z "$payload" ] && continue
    if printf '%s' "$payload" | grep -qE "\"role\"[[:space:]]*:[[:space:]]*\"($FORBIDDEN_ROLES)\""; then
      role=$(printf '%s' "$payload" | grep -oE "\"role\"[[:space:]]*:[[:space:]]*\"[a-z_]+\"" | cut -d'"' -f4)
      echo "${RED}LEAKED SECRET${NC}  $f"
      echo "    JWT with role='${role}' (prefix ${tok:0:12}...)"
      FAIL=1
    fi
  done < <(grep -ohE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' "$f" 2>/dev/null | sort -u)
done < <(git ls-files)

# Postgres connection strings with an inline password.
#
# Two classes of host are EXEMPT, because neither grants anything remotely
# and a guard that cries wolf gets ignored — which is how the real leak
# survived in the first place:
#
#   * loopback (127.0.0.1 / localhost / ::1) — a local dev database
#   * single-label hostnames with no dot (postgres, redis, db) — these are
#     docker-compose service names, resolvable only inside the compose
#     network, carrying the well-known dev credentials from .env.example
#
# A dotted hostname or a non-loopback IP is still flagged: that is a real
# remote database with a password in the tree.
while IFS= read -r hit; do
  file="${hit%%:*}"
  uri=$(printf '%s' "$hit" | grep -ohE 'postgres(ql)?://[^[:space:]"'"'"']+' | head -1)
  credentials="${uri#*://}"; credentials="${credentials%%@*}"
  password="${credentials#*:}"
  # Documentation may use an unmistakable, non-credential placeholder.
  # Keep real inline passwords detectable while avoiding a permanent false
  # positive in the legacy-import access template.
  case "$password" in
    PASSWORD|'<'*'>'|__*__|REPLACE_ME*) continue ;;
  esac
  host=$(printf '%s' "$uri" | sed -E 's#^postgres(ql)?://[^@]*@##; s#[:/].*$##')
  case "$host" in
    127.0.0.1|localhost|::1|'[::1]'|'') continue ;;
  esac
  # docker-compose service name: no dot, and not an IP literal
  case "$host" in
    *.*|*:*) ;;
    *) continue ;;
  esac
  echo "${RED}LEAKED SECRET${NC}  $file"
  echo "    postgres:// URI with inline password, host=${host}"
  FAIL=1
done < <(git grep -nE 'postgres(ql)?://[^:@/[:space:]]+:[^@[:space:]]+@' -- ':!scripts/check_secrets.sh' 2>/dev/null)

if [ "$FAIL" -eq 0 ]; then
  echo "${GREEN}OK${NC} — no privileged JWT or inline DB password in tracked files."
else
  echo ""
  echo "${YELLOW}A secret is committed.${NC} Removing it from the working tree is NOT enough —"
  echo "it stays in git history on every existing clone. Treat it as compromised"
  echo "and rotate. See docs/security/SECRET_ROTATION_RUNBOOK.md."
fi
exit "$FAIL"
