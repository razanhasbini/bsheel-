#!/bin/bash
# ============================================================
# CONTRACT VALIDATION SCRIPT
# Run before every commit to catch contract violations.
# Usage: bash scripts/validate_contract.sh [dev_number]
# Example: bash scripts/validate_contract.sh 2
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No color

ERRORS=0
WARNINGS=0

error() {
  echo -e "${RED}ERROR: $1${NC}"
  ERRORS=$((ERRORS + 1))
}

warn() {
  echo -e "${YELLOW}WARNING: $1${NC}"
  WARNINGS=$((WARNINGS + 1))
}

ok() {
  echo -e "${GREEN}OK: $1${NC}"
}

echo "============================================"
echo "  Quest App Contract Validation"
echo "============================================"
echo ""

# -----------------------------------------------
# CHECK 1: Hardcoded table names in Dart files
# -----------------------------------------------
echo "--- Check 1: Hardcoded table names ---"

# Known table names that should come from supabase_contracts
TABLES=("profiles" "quests" "user_quests" "submissions" "reactions" "notifications" "admins")

for table in "${TABLES[@]}"; do
  # Search for .from('table_name') patterns in Dart files, excluding supabase_contracts itself
  HITS=$(grep -rn "\.from(['\"]${table}['\"])" --include="*.dart" apps/ packages/app_repositories/ packages/app_models/ 2>/dev/null || true)
  if [ -n "$HITS" ]; then
    error "Hardcoded table name '${table}' found. Use Tables.${table} from supabase_contracts instead:"
    echo "$HITS"
    echo ""
  fi
done

# Also check for raw table name strings in select/insert/update/delete calls
HITS=$(grep -rn "\.from(['\"][a-z_]*['\"])" --include="*.dart" apps/ 2>/dev/null || true)
if [ -n "$HITS" ]; then
  error "Hardcoded table name in .from() call. Use Tables.* from supabase_contracts:"
  echo "$HITS"
  echo ""
else
  ok "No hardcoded table names found in app code"
fi

# -----------------------------------------------
# CHECK 2: Hardcoded status values in Dart files
# -----------------------------------------------
echo ""
echo "--- Check 2: Hardcoded status values ---"

STATUSES=("pending" "approved" "rejected" "assigned" "submitted" "expired" "fire" "clap" "heart" "wow" "quest_assigned" "submission_approved" "submission_rejected" "reaction_received" "level_up" "super_admin" "moderator")

for status in "${STATUSES[@]}"; do
  # Look for status used in comparison or assignment, excluding supabase_contracts, tests, and comments
  HITS=$(grep -rn "== ['\"]${status}['\"]" --include="*.dart" apps/ packages/app_repositories/ packages/app_models/ 2>/dev/null || true)
  if [ -n "$HITS" ]; then
    warn "Possible hardcoded status '${status}' in comparison. Use constants from supabase_contracts/statuses.dart:"
    echo "$HITS"
    echo ""
  fi
done

ok "Status value check complete"

# -----------------------------------------------
# CHECK 3: Cross-feature presentation imports
# -----------------------------------------------
echo ""
echo "--- Check 3: Cross-feature presentation imports ---"

# Find imports that cross feature boundaries through presentation layer
HITS=$(grep -rn "import.*features/[a-z_]*/presentation" --include="*.dart" apps/mobile_app/lib/features/ 2>/dev/null | grep -v "import.*features/\([a-z_]*\)/presentation.*" || true)

# More precise: for each feature, check if it imports another feature's presentation
FEATURES=("auth" "profile" "quests" "submissions" "feed" "reactions" "leaderboard" "notifications")

for feature in "${FEATURES[@]}"; do
  for other in "${FEATURES[@]}"; do
    if [ "$feature" != "$other" ]; then
      HITS=$(grep -rn "import.*features/${other}/presentation" --include="*.dart" "apps/mobile_app/lib/features/${feature}/" 2>/dev/null || true)
      if [ -n "$HITS" ]; then
        error "Cross-feature import: '${feature}' imports from '${other}/presentation'. Use shared packages instead:"
        echo "$HITS"
        echo ""
      fi
    fi
  done
done

ok "Cross-feature import check complete"

# -----------------------------------------------
# CHECK 4: supabase_contracts imported where needed
# -----------------------------------------------
echo ""
echo "--- Check 4: supabase_contracts usage ---"

# Files that call Supabase should import supabase_contracts
SUPABASE_CALLERS=$(grep -rln "\.from\|\.rpc\|\.storage" --include="*.dart" apps/ packages/app_repositories/ 2>/dev/null || true)

for file in $SUPABASE_CALLERS; do
  HAS_CONTRACT=$(grep -c "supabase_contracts" "$file" 2>/dev/null || true)
  if [ "$HAS_CONTRACT" -eq 0 ]; then
    warn "File makes Supabase calls but doesn't import supabase_contracts: $file"
  fi
done

ok "supabase_contracts usage check complete"

# -----------------------------------------------
# CHECK 5: Ownership validation (if dev number given)
# -----------------------------------------------
echo ""
echo "--- Check 5: Ownership validation ---"

DEV_NUM=$1

if [ -n "$DEV_NUM" ]; then
  echo "Validating ownership for Dev ${DEV_NUM}..."

  # Get staged files
  CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null || git diff --name-only HEAD 2>/dev/null || echo "")

  if [ -z "$CHANGED_FILES" ]; then
    echo "No changed files to validate."
  else
    case $DEV_NUM in
      1)
        ALLOWED_PATHS="apps/mobile_app/lib/features/auth apps/mobile_app/lib/features/profile apps/mobile_app/lib/core/router apps/mobile_app/lib/core/theme apps/mobile_app/lib/core/providers/auth_session_provider.dart apps/mobile_app/lib/shared packages/shared_ui packages/app_core/lib/theme"
        ;;
      2)
        ALLOWED_PATHS="apps/mobile_app/lib/features/quests apps/mobile_app/lib/features/submissions"
        ;;
      3)
        ALLOWED_PATHS="apps/mobile_app/lib/features/feed apps/mobile_app/lib/features/reactions apps/mobile_app/lib/features/leaderboard"
        ;;
      4)
        ALLOWED_PATHS="apps/admin_web supabase packages/supabase_contracts packages/app_models packages/app_repositories packages/app_core/lib/constants apps/mobile_app/lib/features/notifications"
        ;;
      *)
        warn "Unknown dev number: $DEV_NUM. Skipping ownership check."
        ALLOWED_PATHS=""
        ;;
    esac

    if [ -n "$ALLOWED_PATHS" ]; then
      for file in $CHANGED_FILES; do
        ALLOWED=false
        for path in $ALLOWED_PATHS; do
          if echo "$file" | grep -q "^${path}"; then
            ALLOWED=true
            break
          fi
        done

        # Some files are globally editable
        if echo "$file" | grep -qE "^(\.gitignore|README\.md|CLAUDE\.md|AI_CONTRACT\.md|docs/|scripts/|\.github/)"; then
          ALLOWED=true
        fi

        if [ "$ALLOWED" = false ]; then
          error "Dev ${DEV_NUM} modified file outside ownership scope: $file"
        fi
      done
    fi
  fi
else
  echo "Skipping ownership check (no dev number provided)."
  echo "Usage: bash scripts/validate_contract.sh [1|2|3|4]"
fi

# -----------------------------------------------
# CHECK 6: No duplicate model classes in features
# -----------------------------------------------
echo ""
echo "--- Check 6: Duplicate model classes ---"

# Check if any feature has a class that shadows an app_models class
MODEL_NAMES=("ProfileModel" "QuestModel" "UserQuestModel" "SubmissionModel" "ReactionModel" "NotificationModel" "LeaderboardUserModel" "ModerationDecisionModel")

for model in "${MODEL_NAMES[@]}"; do
  HITS=$(grep -rn "class ${model}" --include="*.dart" apps/ 2>/dev/null || true)
  if [ -n "$HITS" ]; then
    error "Duplicate model class '${model}' found in apps/. Use the one from packages/app_models/ instead:"
    echo "$HITS"
    echo ""
  fi
done

ok "Duplicate model check complete"

# -----------------------------------------------
# SUMMARY
# -----------------------------------------------
echo ""
echo "============================================"
echo "  Validation Summary"
echo "============================================"
echo -e "  Errors:   ${RED}${ERRORS}${NC}"
echo -e "  Warnings: ${YELLOW}${WARNINGS}${NC}"
echo ""

if [ $ERRORS -gt 0 ]; then
  echo -e "${RED}CONTRACT VIOLATION: Fix ${ERRORS} error(s) before committing.${NC}"
  exit 1
else
  echo -e "${GREEN}All contract checks passed.${NC}"
  exit 0
fi
