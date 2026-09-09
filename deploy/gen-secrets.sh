#!/usr/bin/env bash
# Generate deploy/.env.prod with real, independent secrets.
#
# Run this ONCE on the server (or locally and copy it up). It refuses to
# overwrite an existing file, because regenerating JWT secrets logs every
# user out and regenerating DEVICE_TOKEN_ENCRYPTION_KEY makes every stored
# push token undecryptable.
set -euo pipefail
cd "$(dirname "$0")"

OUT=".env.prod"
[ -e "$OUT" ] && { echo "error: $OUT already exists — refusing to overwrite" >&2; exit 1; }
[ -f ".env.prod.example" ] || { echo "error: .env.prod.example missing" >&2; exit 1; }

# hex, so no shell- or dotenv-special characters can appear in a value.
# 64 chars each, comfortably over the 32-char minimum the schema enforces.
# Each is generated separately: the schema requires them to be independent,
# because reusing one across two purposes means one leak compromises both.
gen() { openssl rand -hex 32; }

DB_PASSWORD="$(openssl rand -hex 24)"
JWT_ACCESS="$(gen)"
JWT_REFRESH="$(gen)"
DEVICE_KEY="$(gen)"
ACTION_KEY="$(gen)"

cp .env.prod.example "$OUT"
# Use a literal-safe replacement: hex values contain no / or & so sed is safe.
sed -i.bak \
  -e "s/__DB_PASSWORD__/$DB_PASSWORD/g" \
  -e "s/__JWT_ACCESS_SECRET__/$JWT_ACCESS/g" \
  -e "s/__JWT_REFRESH_SECRET__/$JWT_REFRESH/g" \
  -e "s/__DEVICE_TOKEN_ENCRYPTION_KEY__/$DEVICE_KEY/g" \
  -e "s/__AUTH_ACTION_TOKEN_ENCRYPTION_KEY__/$ACTION_KEY/g" \
  "$OUT"
rm -f "$OUT.bak"
chmod 600 "$OUT"

echo "wrote $OUT (chmod 600)"
echo
echo "Four independent secrets generated. Still MANUAL — the file will not"
echo "start the API until these are filled in:"
grep -nE "REPLACE_ME|__[A-Z_]+__" "$OUT" || echo "  (none — everything is set)"
