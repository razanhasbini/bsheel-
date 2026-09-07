#!/bin/bash
# ============================================================
# SCHEMA DRIFT DETECTION
# Checks that SQL migrations, supabase_contracts (Dart), and
# app_models (Dart) are all in sync. Any dev's AI can edit the
# schema, but this script catches drift before it causes bugs.
#
# Usage: bash scripts/check_schema_drift.sh
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

error() { echo -e "${RED}DRIFT: $1${NC}"; ERRORS=$((ERRORS + 1)); }
warn()  { echo -e "${YELLOW}WARNING: $1${NC}"; WARNINGS=$((WARNINGS + 1)); }
ok()    { echo -e "${GREEN}OK: $1${NC}"; }
info()  { echo -e "${CYAN}$1${NC}"; }

MIGRATIONS_DIR="supabase/migrations"
CONTRACTS_DIR="packages/supabase_contracts/lib"
MODELS_DIR="packages/app_models/lib"

echo "============================================"
echo "  Schema Drift Detection"
echo "============================================"
echo ""

# -----------------------------------------------
# CHECK 1: Every SQL table has a Tables.* constant
# -----------------------------------------------
info "--- Check 1: SQL tables vs Dart Tables constants ---"

# Extract table names from CREATE TABLE statements
SQL_TABLES=$(grep -hri "create table.*public\.\([a-z_]*\)" $MIGRATIONS_DIR/*.sql $MIGRATIONS_DIR/applied/*.sql 2>/dev/null \
  | sed -E "s/.*public\.([a-z_]+).*/\1/" | sort -u)

# Extract table names from Tables class
DART_TABLES=$(grep "static const String .* = '" "$CONTRACTS_DIR/tables.dart" 2>/dev/null \
  | sed -E "s/.*= '([^']+)'.*/\1/" | sort -u)

for table in $SQL_TABLES; do
  if ! echo "$DART_TABLES" | grep -qx "$table"; then
    error "Table '$table' exists in SQL but missing from packages/supabase_contracts/lib/tables.dart"
  fi
done

for table in $DART_TABLES; do
  if ! echo "$SQL_TABLES" | grep -qx "$table"; then
    error "Table '$table' in supabase_contracts but no CREATE TABLE in migrations"
  fi
done

if [ $ERRORS -eq 0 ]; then
  ok "All SQL tables match Dart Tables constants"
fi
PREV_ERRORS=$ERRORS

# -----------------------------------------------
# CHECK 2: Every SQL column has a *Columns.* constant
# -----------------------------------------------
echo ""
info "--- Check 2: SQL columns vs Dart column constants ---"

# For each table, extract columns from SQL and compare with Dart
for table in $SQL_TABLES; do
  # Get Dart class name: profiles -> ProfileColumns, user_quests -> UserQuestColumns
  dart_class=$(echo "$table" | sed -E 's/(^|_)([a-z])/\U\2/g; s/s$//' | sed 's/$/Columns/')
  # Handle plurals properly
  case "$table" in
    profiles) dart_class="ProfileColumns" ;;
    quests) dart_class="QuestColumns" ;;
    user_quests) dart_class="UserQuestColumns" ;;
    submissions) dart_class="SubmissionColumns" ;;
    reactions) dart_class="ReactionColumns" ;;
    notifications) dart_class="NotificationColumns" ;;
    admins) dart_class="AdminColumns" ;;
    *) dart_class="" ;;
  esac

  if [ -z "$dart_class" ]; then
    continue
  fi

  # Extract SQL columns for this table (from CREATE TABLE block)
  # Get everything between "create table...public.TABLE (" and ");"
  sql_cols=$(awk -v t="public\\.$table" '
    tolower($0) ~ "create table.*" t {found=1; next}
    found && /\);/ {found=0}
    found && /^  [a-z]/ {print $1}
  ' $MIGRATIONS_DIR/*.sql $MIGRATIONS_DIR/applied/*.sql 2>/dev/null | sed 's/,$//' | sort -u)

  # Extract Dart columns for this class (mawk-compatible: no 3-arg match)
  dart_cols=$(awk -v c="class $dart_class" '
    $0 ~ c {found=1; next}
    found && /^\}/ {found=0}
    found && /static const String/ {
      line = $0
      gsub(/.*= '"'"'/, "", line)
      gsub(/'"'"'.*/, "", line)
      print line
    }
  ' "$CONTRACTS_DIR/columns.dart" 2>/dev/null | sort -u)

  if [ -z "$sql_cols" ]; then
    continue
  fi

  for col in $sql_cols; do
    # Skip constraint-only lines
    if echo "$col" | grep -qE "^(constraint|check|unique|primary|foreign|create|on|references)"; then
      continue
    fi
    if ! echo "$dart_cols" | grep -qx "$col"; then
      error "Column '$table.$col' in SQL but missing from $dart_class in columns.dart"
    fi
  done

  for col in $dart_cols; do
    if ! echo "$sql_cols" | grep -qx "$col"; then
      warn "Column '$col' in $dart_class but not found in SQL for table '$table' (may be in a different migration)"
    fi
  done
done

if [ $ERRORS -eq $PREV_ERRORS ]; then
  ok "SQL columns match Dart column constants"
fi
PREV_ERRORS=$ERRORS

# -----------------------------------------------
# CHECK 3: SQL CHECK constraints match Dart statuses
# -----------------------------------------------
echo ""
info "--- Check 3: SQL CHECK values vs Dart status constants ---"

# Extract CHECK constraint values from SQL
SQL_STATUSES=$(grep -hro "check.*in ('[^)]*')" $MIGRATIONS_DIR/*.sql $MIGRATIONS_DIR/applied/*.sql 2>/dev/null \
  | grep -oE "'[a-z_]+'" | tr -d "'" | sort -u)

# Extract all status values from statuses.dart
DART_STATUSES=$(grep "static const String .* = '" "$CONTRACTS_DIR/statuses.dart" 2>/dev/null \
  | sed -E "s/.*= '([^']+)'.*/\1/" | sort -u)

for status in $SQL_STATUSES; do
  if ! echo "$DART_STATUSES" | grep -qx "$status"; then
    error "Status '$status' in SQL CHECK constraint but missing from statuses.dart"
  fi
done

for status in $DART_STATUSES; do
  if ! echo "$SQL_STATUSES" | grep -qx "$status"; then
    warn "Status '$status' in statuses.dart but not found in any SQL CHECK constraint"
  fi
done

if [ $ERRORS -eq $PREV_ERRORS ]; then
  ok "SQL CHECK values match Dart status constants"
fi
PREV_ERRORS=$ERRORS

# -----------------------------------------------
# CHECK 4: SQL RPC functions match Dart RpcNames
# -----------------------------------------------
echo ""
info "--- Check 4: SQL functions vs Dart RpcNames ---"

# Extract function names from CREATE FUNCTION statements
SQL_FUNCS=$(grep -hri "create.*function public\.\([a-z_]*\)" $MIGRATIONS_DIR/*.sql $MIGRATIONS_DIR/applied/*.sql 2>/dev/null \
  | sed -E "s/.*public\.([a-z_]+)\(.*/\1/" | sort -u)

# Extract RPC names from Dart
DART_RPCS=$(grep "static const String .* = '" "$CONTRACTS_DIR/rpc_names.dart" 2>/dev/null \
  | sed -E "s/.*= '([^']+)'.*/\1/" | sort -u)

for rpc in $DART_RPCS; do
  if ! echo "$SQL_FUNCS" | grep -qx "$rpc"; then
    error "RPC '$rpc' in rpc_names.dart but no matching SQL function in migrations"
  fi
done

# Don't error on SQL functions not in Dart — some are internal triggers
for func in $SQL_FUNCS; do
  if echo "$DART_RPCS" | grep -qx "$func"; then
    continue
  fi
  # Only warn if it looks like a public API function (not handle_* triggers)
  if ! echo "$func" | grep -qE "^handle_"; then
    warn "SQL function '$func' exists but not in rpc_names.dart (OK if it's trigger-only)"
  fi
done

if [ $ERRORS -eq $PREV_ERRORS ]; then
  ok "RPC functions match Dart constants"
fi
PREV_ERRORS=$ERRORS

# -----------------------------------------------
# CHECK 5: Storage buckets match Dart constants
# -----------------------------------------------
echo ""
info "--- Check 5: SQL storage buckets vs Dart StorageBuckets ---"

SQL_BUCKETS=$(grep -hro "'[a-z_]*', '[a-z_]*'" $MIGRATIONS_DIR/*storage*.sql $MIGRATIONS_DIR/applied/*storage*.sql 2>/dev/null \
  | head -20 | sed -E "s/'([^']+)', '([^']+)'/\2/" | sort -u)

# Fallback: try to find bucket inserts
if [ -z "$SQL_BUCKETS" ]; then
  SQL_BUCKETS=$(grep -hro "('[a-z_]*', '[a-z_]*'" $MIGRATIONS_DIR/*.sql $MIGRATIONS_DIR/applied/*.sql 2>/dev/null \
    | grep -i bucket | sed -E "s/.*'([a-z_]+)'.*/\1/" | sort -u)
fi

DART_BUCKETS=$(grep "static const String .* = '" "$CONTRACTS_DIR/storage_paths.dart" 2>/dev/null \
  | grep -v "//\|Path\|static String" | sed -E "s/.*= '([^']+)'.*/\1/" | sort -u)

for bucket in $DART_BUCKETS; do
  found=false
  # Check if bucket name appears anywhere in storage migration
  if grep -qr "'$bucket'" $MIGRATIONS_DIR/*storage*.sql $MIGRATIONS_DIR/applied/*storage*.sql 2>/dev/null || \
     grep -qr "'$bucket'" $MIGRATIONS_DIR/*.sql $MIGRATIONS_DIR/applied/*.sql 2>/dev/null; then
    found=true
  fi
  if [ "$found" = false ]; then
    warn "Bucket '$bucket' in StorageBuckets but not found in storage migration SQL"
  fi
done

ok "Storage bucket check complete"

# -----------------------------------------------
# CHECK 6: Dart models have fields for all columns
# -----------------------------------------------
echo ""
info "--- Check 6: Dart model fields vs contract columns ---"

# Portable mapping (no associative arrays — macOS /bin/bash is 3.2)
while IFS=: read -r dart_class model_file; do
  [ -z "$dart_class" ] && continue
  model_path="$MODELS_DIR/$model_file"

  if [ ! -f "$model_path" ]; then
    warn "Model file $model_file not found"
    continue
  fi

  # Get column names from contracts (mawk-compatible: no 3-arg match)
  dart_cols=$(awk -v c="class $dart_class" '
    $0 ~ c {found=1; next}
    found && /^\}/ {found=0}
    found && /static const String/ {
      line = $0
      gsub(/.*= '"'"'/, "", line)
      gsub(/'"'"'.*/, "", line)
      print line
    }
  ' "$CONTRACTS_DIR/columns.dart" 2>/dev/null)

  for col in $dart_cols; do
    # Convert snake_case to camelCase for Dart field lookup
    camel=$(echo "$col" | sed -E 's/_([a-z])/\U\1/g')

    if ! grep -q "$camel\|$col" "$model_path" 2>/dev/null; then
      warn "Column '$col' ($camel) in $dart_class but no matching field in $model_file"
    fi
  done
done <<'MODEL_MAP_EOF'
ProfileColumns:profile_model.dart
QuestColumns:quest_model.dart
SubmissionColumns:submission_model.dart
ReactionColumns:reaction_model.dart
NotificationColumns:notification_model.dart
UserQuestColumns:user_quest_model.dart
MODEL_MAP_EOF

ok "Model field check complete"

# -----------------------------------------------
# SUMMARY
# -----------------------------------------------
echo ""
echo "============================================"
echo "  Schema Drift Summary"
echo "============================================"
echo -e "  Errors:   ${RED}${ERRORS}${NC}"
echo -e "  Warnings: ${YELLOW}${WARNINGS}${NC}"
echo ""

if [ $ERRORS -gt 0 ]; then
  echo -e "${RED}SCHEMA DRIFT DETECTED: Fix ${ERRORS} error(s) before committing.${NC}"
  echo ""
  echo "Required actions:"
  echo "  1. If you added a SQL column → add it to supabase_contracts/columns.dart"
  echo "  2. If you added a SQL table  → add it to supabase_contracts/tables.dart"
  echo "  3. If you added a CHECK value → add it to supabase_contracts/statuses.dart"
  echo "  4. If you added a SQL function → add it to supabase_contracts/rpc_names.dart"
  echo "  5. If you added a column → add matching field to the model in app_models/"
  echo "  6. Describe the schema change in your commit message"
  exit 1
else
  echo -e "${GREEN}No schema drift detected. SQL, contracts, and models are in sync.${NC}"
  exit 0
fi
