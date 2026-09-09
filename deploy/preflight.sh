#!/usr/bin/env bash
# Read-only preflight. Run ON THE SERVER before deploying anything.
#
# This box serves the live quest-app backend. This script MODIFIES NOTHING;
# it reports what is there and fails loudly on anything that would put the
# live stack at risk.
#
#   ./preflight.sh          # report + checks
#
# Exit 0 = safe to deploy. Non-zero = stop and read the output.
set -uo pipefail
cd "$(dirname "$0")"

PASS=0; FAIL=0; WARN=0
ok()   { printf "  \033[32mPASS\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
bad()  { printf "  \033[31mFAIL\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); }
warn() { printf "  \033[33mWARN\033[0m %s\n" "$1"; WARN=$((WARN+1)); }
hdr()  { printf "\n\033[1m== %s\033[0m\n" "$1"; }

hdr "Host"
echo "  $(uname -srm)"
echo "  $( (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") || echo 'unknown distro')"
CPUS=$(nproc 2>/dev/null || echo 0)
MEM_TOTAL_MB=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
MEM_AVAIL_MB=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
DISK_AVAIL_GB=$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0)
echo "  cpus=$CPUS  mem_total=${MEM_TOTAL_MB}MB  mem_available=${MEM_AVAIL_MB}MB  disk_avail=${DISK_AVAIL_GB}GB"

hdr "Headroom for Bsheel (postgres+redis+api+worker ~= 2.7GB capped)"
# The caps in .env.prod.example total ~2.7GB. Require real availability
# above that, not total RAM — the Supabase stack is already using some.
if [ "$MEM_AVAIL_MB" -ge 3200 ]; then ok "available memory ${MEM_AVAIL_MB}MB >= 3200MB"
elif [ "$MEM_AVAIL_MB" -ge 2200 ]; then warn "available memory ${MEM_AVAIL_MB}MB is tight — lower the *_MEM_LIMIT values in .env.prod"
else bad "available memory ${MEM_AVAIL_MB}MB is not enough; deploying risks OOM-killing the LIVE Supabase stack"; fi
[ "$DISK_AVAIL_GB" -ge 20 ] && ok "disk ${DISK_AVAIL_GB}GB free" || bad "only ${DISK_AVAIL_GB}GB free; Postgres + images + MinIO need 20GB+"
[ "$CPUS" -ge 2 ] && ok "$CPUS cpus" || warn "only $CPUS cpu — the API takes ~52s to boot as it is"

hdr "Tooling"
command -v docker >/dev/null && ok "docker $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ,)" || bad "docker not installed"
docker compose version >/dev/null 2>&1 && ok "docker compose $(docker compose version --short 2>/dev/null)" || bad "docker compose v2 plugin not installed"
command -v caddy >/dev/null && ok "caddy $(caddy version 2>/dev/null | head -1)" \
  || { docker ps --format '{{.Image}}' 2>/dev/null | grep -qi caddy && warn "caddy runs in a container — the API must be reachable from it (see README)" || warn "caddy binary not found; check how :443 is served"; }

hdr "What is already listening (do not disturb)"
ss -tlnp 2>/dev/null | awk 'NR==1 || /LISTEN/' | head -25 || netstat -tlnp 2>/dev/null | head -25

hdr "Port Bsheel wants"
BIND_PORT=$(grep -E '^API_BIND_PORT=' .env.prod 2>/dev/null | cut -d= -f2 || echo 3010)
BIND_PORT=${BIND_PORT:-3010}
if ss -tln 2>/dev/null | grep -qE "127\.0\.0\.1:${BIND_PORT}\b|:::${BIND_PORT}\b|0\.0\.0\.0:${BIND_PORT}\b"; then
  bad "port ${BIND_PORT} is already in use — pick another API_BIND_PORT"
else ok "port ${BIND_PORT} is free"; fi

hdr "Live Supabase stack — baseline (must still pass AFTER deploy)"
for path in /auth/v1/health /rest/v1/ /storage/v1/version /functions/v1/; do
  code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "https://api.bsheel.app${path}" 2>/dev/null || echo 000)
  case "$code" in
    401|400|200) ok "api.bsheel.app${path} -> $code (alive)" ;;
    000)         bad "api.bsheel.app${path} unreachable — investigate BEFORE deploying" ;;
    *)           warn "api.bsheel.app${path} -> $code (unexpected; record it as the baseline)" ;;
  esac
done

hdr "THE important check: Bsheel must not touch the Supabase database"
if [ ! -f .env.prod ]; then
  bad ".env.prod missing — run ./gen-secrets.sh first"
else
  DB_URL=$(grep -E '^DATABASE_URL=' .env.prod | cut -d= -f2-)
  DB_HOST=$(printf '%s' "$DB_URL" | sed -E 's#^[a-z]+://[^@]*@([^:/]+).*#\1#')
  case "$DB_HOST" in
    postgres)
      ok "DATABASE_URL host is the compose service 'postgres' (isolated)" ;;
    localhost|127.0.0.1|::1|"")
      bad "DATABASE_URL host is '$DB_HOST' — that is THIS HOST, where the LIVE Supabase database runs.
       Bsheel's migrations are forward-only and would run against production data.
       Set it to the compose service name: postgresql://bsheel:...@postgres:5432/bsheel_prod" ;;
    *)
      warn "DATABASE_URL host is '$DB_HOST' — not the compose service; confirm this is deliberate" ;;
  esac

  # Placeholders the schema will reject at boot — catch them here instead of
  # after a 3-minute image build.
  if grep -qE "REPLACE_ME|__[A-Z_]+__" .env.prod; then
    bad "unfilled placeholders remain in .env.prod:"; grep -nE "REPLACE_ME|__[A-Z_]+__" .env.prod | sed 's/^/       /'
  else ok "no unfilled placeholders in .env.prod"; fi

  grep -qE '^NODE_ENV=production$' .env.prod && ok "NODE_ENV=production" || bad "NODE_ENV must be production"
  grep -qE '^SWAGGER_ENABLED=false$' .env.prod && ok "SWAGGER_ENABLED=false" || warn "SWAGGER_ENABLED is not false — /docs would be public"
fi

hdr "Name collisions with existing docker objects"
for n in bsheel_postgres_data bsheel_redis_data bsheel_minio_data; do
  docker volume inspect "$n" >/dev/null 2>&1 && warn "volume $n already exists (data will be REUSED, not recreated)" || ok "volume $n is new"
done
docker network inspect bsheel_internal >/dev/null 2>&1 && warn "network bsheel_internal already exists" || ok "network bsheel_internal is new"

printf "\n\033[1m== Result ==\033[0m\n  %d passed, %d warnings, %d failed\n" "$PASS" "$WARN" "$FAIL"
[ "$FAIL" -eq 0 ] || { printf "\n\033[31mDo not deploy. Fix the failures above.\033[0m\n"; exit 1; }
printf "\n\033[32mSafe to deploy.\033[0m Next: docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build\n"
