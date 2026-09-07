#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="${1:-$root/../4hoursonly}"
allowlist="$root/scripts/legacy-migration-allowlist.txt"

if [[ ! -d "$source_root/.git" ]]; then
  echo "Usage: $0 [path-to-original-git-checkout]" >&2
  exit 2
fi

failures=0
while IFS= read -r -d '' path; do
  if [[ -f "$allowlist" ]] && grep -Fqx -- "$path" "$allowlist"; then
    continue
  fi
  if [[ ! -f "$root/$path" ]]; then
    echo "MISSING: $path" >&2
    failures=$((failures + 1))
    continue
  fi
  if ! cmp -s "$source_root/$path" "$root/$path"; then
    echo "CHANGED: $path" >&2
    failures=$((failures + 1))
  fi
done < <(
  git -C "$source_root" ls-files -z -- \
    apps packages supabase cloudflare \
    pubspec.yaml melos.yaml analysis_options.yaml
)

if (( failures > 0 )); then
  echo "$failures legacy file(s) are missing or differ" >&2
  exit 1
fi

echo "All non-allowlisted Flutter, Supabase, and Cloudflare implementation files are present and byte-identical."
