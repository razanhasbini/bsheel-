#!/usr/bin/env bash
# Copies the object-storage credentials that are already on this host into
# deploy/.env.prod, in place, without ever printing a secret value.
#
# Run ON THE SERVER. Reports which keys it found and where from; the values
# move from one root-owned file to another and are never echoed, logged, or
# passed as arguments.
#
#   sudo ./import-r2-credentials.sh
set -uo pipefail
cd "$(dirname "$0")"

TARGET=".env.prod"
[ -f "$TARGET" ] || { echo "error: $TARGET not found — run ./gen-secrets.sh first" >&2; exit 1; }

# Candidate sources, most specific first.
SOURCES=(
  /root/bsheel/bsheel-db.env
  /root/bsheel/.env
  /root/supabase-docker/.env
  /root/hood/.env
)

# Reads one key from the first source that defines it non-empty.
#
# Sets the globals KEY_VALUE and FOUND_IN rather than printing, because a
# command substitution would run this in a subshell and lose FOUND_IN. Prints
# nothing either way — the value must not reach a log or a terminal.
KEY_VALUE=""
FOUND_IN=""
read_key() {
  local key="$1" src val
  KEY_VALUE=""; FOUND_IN=""
  for src in "${SOURCES[@]}"; do
    [ -r "$src" ] || continue
    val=$(sed -nE "s/^[[:space:]]*(export[[:space:]]+)?${key}=[\"']?(.*[^\"'])[\"']?[[:space:]]*$/\2/p" "$src" | tail -1)
    if [ -n "${val:-}" ]; then
      KEY_VALUE="$val"
      FOUND_IN="$src"
      return 0
    fi
  done
  return 1
}

# Replace (or append) a key in .env.prod without printing the value.
set_key() {
  local key="$1" value="$2"
  python3 - "$TARGET" "$key" "$value" <<'PY'
import sys, pathlib, re
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(path)
lines = p.read_text().splitlines(keepends=True)
pattern = re.compile(rf'^\s*{re.escape(key)}=')
out, replaced = [], False
for line in lines:
    if pattern.match(line):
        if not replaced:
            out.append(f'{key}={value}\n')
            replaced = True
        # drop any duplicate definitions
    else:
        out.append(line)
if not replaced:
    if out and not out[-1].endswith('\n'):
        out.append('\n')
    out.append(f'{key}={value}\n')
p.write_text(''.join(out))
PY
}

echo "Importing object-storage credentials into $TARGET"
echo

# This repo's variable  <- candidate names used by the stacks on this host.
declare -A MAP=(
  [R2_ACCESS_KEY_ID]="R2_ACCESS_KEY_ID AWS_ACCESS_KEY_ID S3_ACCESS_KEY GLOBAL_S3_ACCESS_KEY STORAGE_S3_ACCESS_KEY_ID MINIO_ROOT_USER"
  [R2_SECRET_ACCESS_KEY]="R2_SECRET_ACCESS_KEY AWS_SECRET_ACCESS_KEY S3_SECRET_KEY GLOBAL_S3_SECRET_KEY STORAGE_S3_SECRET_ACCESS_KEY MINIO_ROOT_PASSWORD"
  [R2_BUCKET]="R2_BUCKET GLOBAL_S3_BUCKET STORAGE_S3_BUCKET S3_BUCKET"
  [R2_ENDPOINT]="R2_ENDPOINT S3_ENDPOINT GLOBAL_S3_ENDPOINT STORAGE_S3_ENDPOINT AWS_ENDPOINT_URL"
  [R2_REGION]="R2_REGION S3_REGION GLOBAL_S3_REGION STORAGE_S3_REGION AWS_REGION AWS_DEFAULT_REGION"
  [R2_PUBLIC_BASE_URL]="R2_PUBLIC_BASE_URL STORAGE_S3_PUBLIC_URL"
)

MISSING=()
for target in R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET R2_ENDPOINT R2_REGION R2_PUBLIC_BASE_URL; do
  got=""
  for candidate in ${MAP[$target]}; do
    if read_key "$candidate"; then
      set_key "$target" "$KEY_VALUE"
      # Endpoint, bucket and region are not secrets; showing them is how you
      # confirm the right storage was picked up. Keys are only counted.
      case "$target" in
        R2_ENDPOINT|R2_PUBLIC_BASE_URL|R2_BUCKET|R2_REGION)
          printf '  %-24s <- %-26s %s   (%s)\n' "$target" "$candidate" "$KEY_VALUE" "$FOUND_IN" ;;
        *)
          printf '  %-24s <- %-26s [%d chars]   (%s)\n' "$target" "$candidate" "${#KEY_VALUE}" "$FOUND_IN" ;;
      esac
      got=1
      break
    fi
  done
  [ -n "$got" ] || MISSING+=("$target")
done

echo
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "Not found on this host: ${MISSING[*]}"
  echo "Fill those in by hand — media upload will fail without them."
  exit 2
fi
echo "All object-storage values imported. No secret was printed."
