#!/usr/bin/env bash
# Imports quest-app's live data into this backend's schema, so the 637 objects
# already in the R2 bucket have rows pointing at them and appear in the app and
# the admin panel.
#
# Run ON THE SERVER:
#   sudo ./import-legacy-data.sh            # stage + report, writes nothing
#   sudo ./import-legacy-data.sh --apply    # stage + load, in one transaction
#
# Source: the supabase-db container (quest-app's production database). READ
# ONLY — nothing here writes to it.
# Target: this stack's Postgres.
#
# Why this is a direct mapping rather than a rewrite: this repo descends from
# quest-app, so the table and column names are largely identical and every
# legacy text value is already a legal member of the corresponding enum here.
# The real work is three transforms:
#
#   1. media_url and avatar_url hold FULL public R2 URLs; this schema stores
#      bare object keys. A plain string replace handles both the 280 bare URLs
#      and the 49 JSON arrays of URLs, because it operates on the text either
#      way.
#   2. submissions.xp_awarded_amount, .version, .net_score and
#      .moderation_removed_at do not exist upstream and are derived.
#   3. users are assembled from auth.users (email, password) joined to
#      profiles (account_status).
set -uo pipefail
cd "$(dirname "$0")"

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

LEGACY_CONTAINER="${LEGACY_CONTAINER:-supabase-db}"
LEGACY_USER="${LEGACY_USER:-postgres}"
LEGACY_DB="${LEGACY_DB:-postgres}"
R2_PUBLIC_PREFIX="${R2_PUBLIC_PREFIX:-https://pub-c5cc3a25116846169de23bc92a5ea697.r2.dev/}"

set -a; . ./.env.prod; set +a
COMPOSE=(docker compose --env-file .env.prod -f docker-compose.prod.yml)

step() { printf "\n\033[1m==> %s\033[0m\n" "$1"; }
fail() { printf "\033[31merror: %s\033[0m\n" "$1" >&2; exit 1; }

src() { docker exec -i "$LEGACY_CONTAINER" psql -U "$LEGACY_USER" -d "$LEGACY_DB" "$@"; }
dst() { "${COMPOSE[@]}" exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$@"; }

docker inspect "$LEGACY_CONTAINER" >/dev/null 2>&1 || fail "no $LEGACY_CONTAINER container"
dst -tAc 'SELECT 1' >/dev/null 2>&1 || fail "target database unreachable"

# ---------------------------------------------------------------------------
# 1. Stage. Every column lands as text so nothing can fail on a cast during
#    transfer; the casts happen in the load step where they can be reasoned
#    about and rolled back.
# ---------------------------------------------------------------------------
step "Stage legacy rows into the legacy_stage schema"

declare -A COLUMNS=(
  [auth_users]="id, email, encrypted_password, email_confirmed_at, last_sign_in_at, created_at, banned_until, deleted_at"
  [profiles]="id, username, display_name, avatar_url, bio, xp, level, quests_completed, created_at, updated_at, account_status, accepted_terms_at, profile_completed, age_verified, analytics_consent_at"
  [quests]="id, title, description, category, difficulty, xp_reward, is_active, created_by, created_at, updated_at, duration_hours"
  [user_quests]="id, user_id, quest_id, status, assigned_at, completed_at, expires_at"
  [submissions]="id, user_quest_id, user_id, media_url, media_type, caption, status, reviewed_by, review_note, submitted_at, reviewed_at, appeal_note, appealed, show_in_feed, visibility, deleted_at, xp_awarded, telegram_message_id"
  [reactions]="id, submission_id, user_id, type, created_at"
  [comments]="id, submission_id, user_id, body, created_at, parent_id"
  [saved_posts]="id, user_id, submission_id, created_at"
  [follows]="id, follower_id, following_id, created_at"
  [blocked_users]="id, blocker_id, blocked_id, created_at"
  [collab_groups]="id, quest_id, creator_id, code, mode, status, max_members, expires_at, created_at"
  [collab_group_members]="id, group_id, user_id, user_quest_id, joined_at, submission_time_seconds"
  [collab_votes]="id, group_id, voter_id, submission_id, created_at"
  [admins]="id, user_id, role, created_at"
  [quest_of_the_day]="id, display_date, quest_id, ticket_no, bonus_xp, note, created_by, created_at, updated_at"
  [notifications]="id, user_id, title, body, type, reference_id, is_read, created_at, actor_id"
  [reports]="id, reporter_id, reported_type, reported_id, reason, status, admin_note, created_at, reviewed_at, reviewed_by"
  [quest_reroll_log]="id, user_id, rerolled_at"
)

ORDER=(auth_users profiles quests user_quests submissions reactions comments
       saved_posts follows blocked_users collab_groups collab_group_members
       collab_votes admins quest_of_the_day notifications reports quest_reroll_log)

dst -q -c "DROP SCHEMA IF EXISTS legacy_stage CASCADE; CREATE SCHEMA legacy_stage;" \
  || fail "could not create the staging schema"

for table in "${ORDER[@]}"; do
  cols="${COLUMNS[$table]}"
  source_table="public.$table"
  [ "$table" = "auth_users" ] && source_table="auth.users"

  # Staging table: one text column per source column.
  ddl=$(printf '%s' "$cols" | tr ',' '\n' | sed 's/^ *//;s/$/ text/' | paste -sd, -)
  dst -q -c "CREATE TABLE legacy_stage.$table ($ddl);" || fail "ddl failed for $table"

  src -q -c "\\copy (SELECT $cols FROM $source_table) TO STDOUT WITH (FORMAT csv)" \
    | dst -q -c "\\copy legacy_stage.$table FROM STDIN WITH (FORMAT csv)" \
    || fail "transfer failed for $table"

  printf '  %-24s %s rows\n' "$table" "$(dst -tAc "SELECT count(*) FROM legacy_stage.$table;")"
done

# ---------------------------------------------------------------------------
# 2. Report what would land, and what would be skipped and why.
# ---------------------------------------------------------------------------
step "Pre-flight on the staged data"
dst -tA -F' | ' <<SQL | sed 's/^/  /'
SELECT 'users importable', count(*) FROM legacy_stage.auth_users WHERE email IS NOT NULL
UNION ALL SELECT 'profiles with no auth user (skipped)', count(*)
  FROM legacy_stage.profiles p
  WHERE NOT EXISTS (SELECT 1 FROM legacy_stage.auth_users u WHERE u.id = p.id)
UNION ALL SELECT 'username collisions with existing rows', count(*)
  FROM legacy_stage.profiles p
  WHERE EXISTS (SELECT 1 FROM public.profiles e WHERE lower(e.username::text) = lower(p.username))
UNION ALL SELECT 'email collisions with existing rows', count(*)
  FROM legacy_stage.auth_users u
  WHERE EXISTS (SELECT 1 FROM public.users e WHERE lower(e.email::text) = lower(u.email))
UNION ALL SELECT 'submissions whose media still has the R2 prefix', count(*)
  FROM legacy_stage.submissions WHERE media_url LIKE '%r2.dev%'
UNION ALL SELECT 'bcrypt password hashes (cannot verify under argon2)', count(*)
  FROM legacy_stage.auth_users WHERE encrypted_password LIKE '\$2%';
SQL

if [ "$APPLY" -eq 0 ]; then
  step "Dry run — nothing was written to the live tables"
  echo "  The legacy_stage schema is populated so you can inspect it."
  echo "  Re-run with --apply to load it."
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Load. One transaction: it all lands or none of it does. Every insert is
#    ON CONFLICT DO NOTHING so a re-run is safe and adds only what is missing.
# ---------------------------------------------------------------------------
step "Load into the live schema (single transaction)"
dst -v ON_ERROR_STOP=1 -q <<SQL || fail "load failed and was rolled back"
BEGIN;

-- Accounts. status comes from the profile; a live ban overrides it.
INSERT INTO public.users (id, email, password_hash, email_verified_at, status,
                          token_version, last_login_at, created_at, updated_at, deleted_at)
SELECT u.id::uuid, u.email::citext, u.encrypted_password,
       u.email_confirmed_at::timestamptz,
       CASE WHEN u.banned_until IS NOT NULL AND u.banned_until::timestamptz > now() THEN 'banned'
            ELSE coalesce(p.account_status, 'active') END::account_status,
       0, u.last_sign_in_at::timestamptz,
       coalesce(u.created_at::timestamptz, now()), now(), u.deleted_at::timestamptz
FROM legacy_stage.auth_users u
LEFT JOIN legacy_stage.profiles p ON p.id = u.id
WHERE u.email IS NOT NULL
ON CONFLICT DO NOTHING;

-- Profiles. avatar_url becomes a bare object key.
INSERT INTO public.profiles (id, username, display_name, avatar_url, bio, xp, level,
                             quests_completed, profile_completed, age_verified,
                             analytics_consent_at, accepted_terms_at, created_at, updated_at)
SELECT p.id::uuid, p.username::citext, p.display_name,
       nullif(replace(coalesce(p.avatar_url, ''), '${R2_PUBLIC_PREFIX}', ''), ''),
       p.bio, coalesce(p.xp::int, 0), coalesce(p.level::int, 1),
       coalesce(p.quests_completed::int, 0),
       coalesce(p.profile_completed::boolean, false),
       coalesce(p.age_verified::boolean, false),
       p.analytics_consent_at::timestamptz, p.accepted_terms_at::timestamptz,
       coalesce(p.created_at::timestamptz, now()), now()
FROM legacy_stage.profiles p
WHERE EXISTS (SELECT 1 FROM public.users pu WHERE pu.id = p.id::uuid)
ON CONFLICT DO NOTHING;

INSERT INTO public.quests (id, title, description, category, difficulty, xp_reward,
                           duration_hours, is_active, created_by, created_at, updated_at)
SELECT q.id::uuid, q.title, q.description, q.category, q.difficulty,
       coalesce(q.xp_reward::int, 0), coalesce(q.duration_hours::int, 24),
       coalesce(q.is_active::boolean, true),
       (SELECT id FROM public.users WHERE id = q.created_by::uuid),
       coalesce(q.created_at::timestamptz, now()), now()
FROM legacy_stage.quests q
ON CONFLICT DO NOTHING;

INSERT INTO public.user_quests (id, user_id, quest_id, status, assigned_at,
                                completed_at, expires_at, version)
SELECT uq.id::uuid, uq.user_id::uuid, uq.quest_id::uuid,
       uq.status::user_quest_status,
       coalesce(uq.assigned_at::timestamptz, now()), uq.completed_at::timestamptz,
       coalesce(uq.expires_at::timestamptz, coalesce(uq.assigned_at::timestamptz, now()) + interval '24 hours'),
       0
FROM legacy_stage.user_quests uq
WHERE EXISTS (SELECT 1 FROM public.users u WHERE u.id = uq.user_id::uuid)
  AND EXISTS (SELECT 1 FROM public.quests q WHERE q.id = uq.quest_id::uuid)
ON CONFLICT DO NOTHING;

-- Submissions. The prefix strip is a plain replace so it works on a bare URL
-- and on a JSON array of URLs alike. xp_awarded_amount is reconstructed from
-- the quest's reward, which is the only ledger available upstream.
INSERT INTO public.submissions (id, user_quest_id, user_id, media_url, media_type,
                                caption, status, reviewed_by, review_note, submitted_at,
                                reviewed_at, appeal_note, appealed, show_in_feed,
                                visibility, deleted_at, xp_awarded, xp_awarded_amount,
                                telegram_message_id, version, net_score)
SELECT s.id::uuid, s.user_quest_id::uuid, s.user_id::uuid,
       replace(s.media_url, '${R2_PUBLIC_PREFIX}', ''),
       coalesce(s.media_type, 'image')::media_type,
       s.caption, coalesce(s.status, 'pending')::submission_status,
       (SELECT id FROM public.users WHERE id = s.reviewed_by::uuid),
       s.review_note, coalesce(s.submitted_at::timestamptz, now()),
       s.reviewed_at::timestamptz, s.appeal_note,
       coalesce(s.appealed::boolean, false),
       coalesce(s.show_in_feed::boolean, true),
       coalesce(s.visibility, 'visible')::submission_visibility,
       s.deleted_at::timestamptz,
       coalesce(s.xp_awarded::boolean, false),
       CASE WHEN coalesce(s.xp_awarded::boolean, false)
            THEN coalesce((SELECT q.xp_reward FROM public.user_quests uq
                           JOIN public.quests q ON q.id = uq.quest_id
                           WHERE uq.id = s.user_quest_id::uuid), 0)
            ELSE 0 END,
       s.telegram_message_id::bigint, 0, 0
FROM legacy_stage.submissions s
WHERE s.media_url IS NOT NULL
  AND EXISTS (SELECT 1 FROM public.user_quests uq WHERE uq.id = s.user_quest_id::uuid)
  AND EXISTS (SELECT 1 FROM public.users u WHERE u.id = s.user_id::uuid)
ON CONFLICT DO NOTHING;

INSERT INTO public.reactions (id, submission_id, user_id, type, created_at)
SELECT r.id::uuid, r.submission_id::uuid, r.user_id::uuid, r.type::reaction_type,
       coalesce(r.created_at::timestamptz, now())
FROM legacy_stage.reactions r
WHERE EXISTS (SELECT 1 FROM public.submissions s WHERE s.id = r.submission_id::uuid)
  AND EXISTS (SELECT 1 FROM public.users u WHERE u.id = r.user_id::uuid)
ON CONFLICT DO NOTHING;

-- Parents before children, so a reply never precedes the comment it answers.
INSERT INTO public.comments (id, submission_id, user_id, body, parent_id, created_at, updated_at)
SELECT c.id::uuid, c.submission_id::uuid, c.user_id::uuid, c.body, NULL,
       coalesce(c.created_at::timestamptz, now()), coalesce(c.created_at::timestamptz, now())
FROM legacy_stage.comments c
WHERE c.parent_id IS NULL
  AND EXISTS (SELECT 1 FROM public.submissions s WHERE s.id = c.submission_id::uuid)
  AND EXISTS (SELECT 1 FROM public.users u WHERE u.id = c.user_id::uuid)
ON CONFLICT DO NOTHING;

INSERT INTO public.comments (id, submission_id, user_id, body, parent_id, created_at, updated_at)
SELECT c.id::uuid, c.submission_id::uuid, c.user_id::uuid, c.body, c.parent_id::uuid,
       coalesce(c.created_at::timestamptz, now()), coalesce(c.created_at::timestamptz, now())
FROM legacy_stage.comments c
WHERE c.parent_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM public.submissions s WHERE s.id = c.submission_id::uuid)
  AND EXISTS (SELECT 1 FROM public.users u WHERE u.id = c.user_id::uuid)
  AND EXISTS (SELECT 1 FROM public.comments p WHERE p.id = c.parent_id::uuid)
ON CONFLICT DO NOTHING;

INSERT INTO public.saved_posts (id, user_id, submission_id, created_at)
SELECT sp.id::uuid, sp.user_id::uuid, sp.submission_id::uuid, coalesce(sp.created_at::timestamptz, now())
FROM legacy_stage.saved_posts sp
WHERE EXISTS (SELECT 1 FROM public.users u WHERE u.id = sp.user_id::uuid)
  AND EXISTS (SELECT 1 FROM public.submissions s WHERE s.id = sp.submission_id::uuid)
ON CONFLICT DO NOTHING;

INSERT INTO public.follows (id, follower_id, following_id, created_at)
SELECT f.id::uuid, f.follower_id::uuid, f.following_id::uuid, coalesce(f.created_at::timestamptz, now())
FROM legacy_stage.follows f
WHERE EXISTS (SELECT 1 FROM public.users a WHERE a.id = f.follower_id::uuid)
  AND EXISTS (SELECT 1 FROM public.users b WHERE b.id = f.following_id::uuid)
ON CONFLICT DO NOTHING;

INSERT INTO public.blocked_users (id, blocker_id, blocked_id, created_at)
SELECT b.id::uuid, b.blocker_id::uuid, b.blocked_id::uuid, coalesce(b.created_at::timestamptz, now())
FROM legacy_stage.blocked_users b
WHERE EXISTS (SELECT 1 FROM public.users a WHERE a.id = b.blocker_id::uuid)
  AND EXISTS (SELECT 1 FROM public.users c WHERE c.id = b.blocked_id::uuid)
ON CONFLICT DO NOTHING;

INSERT INTO public.collab_groups (id, quest_id, creator_id, code, mode, status,
                                  max_members, expires_at, created_at)
SELECT g.id::uuid, g.quest_id::uuid, g.creator_id::uuid, upper(g.code),
       coalesce(g.mode, 'with')::collab_mode, coalesce(g.status, 'open')::collab_status,
       coalesce(g.max_members::int, 5),
       coalesce(g.expires_at::timestamptz, coalesce(g.created_at::timestamptz, now()) + interval '24 hours'),
       coalesce(g.created_at::timestamptz, now())
FROM legacy_stage.collab_groups g
WHERE EXISTS (SELECT 1 FROM public.quests q WHERE q.id = g.quest_id::uuid)
  AND EXISTS (SELECT 1 FROM public.users u WHERE u.id = g.creator_id::uuid)
ON CONFLICT DO NOTHING;

INSERT INTO public.collab_group_members (id, group_id, user_id, user_quest_id,
                                         joined_at, submission_time_seconds)
SELECT m.id::uuid, m.group_id::uuid, m.user_id::uuid, m.user_quest_id::uuid,
       coalesce(m.joined_at::timestamptz, now()), m.submission_time_seconds::int
FROM legacy_stage.collab_group_members m
WHERE EXISTS (SELECT 1 FROM public.collab_groups g WHERE g.id = m.group_id::uuid)
  AND EXISTS (SELECT 1 FROM public.users u WHERE u.id = m.user_id::uuid)
  AND EXISTS (SELECT 1 FROM public.user_quests uq WHERE uq.id = m.user_quest_id::uuid)
ON CONFLICT DO NOTHING;

INSERT INTO public.collab_votes (id, group_id, voter_id, submission_id, created_at)
SELECT v.id::uuid, v.group_id::uuid, v.voter_id::uuid, v.submission_id::uuid,
       coalesce(v.created_at::timestamptz, now())
FROM legacy_stage.collab_votes v
WHERE EXISTS (SELECT 1 FROM public.collab_groups g WHERE g.id = v.group_id::uuid)
  AND EXISTS (SELECT 1 FROM public.users u WHERE u.id = v.voter_id::uuid)
  AND EXISTS (SELECT 1 FROM public.submissions s WHERE s.id = v.submission_id::uuid)
ON CONFLICT DO NOTHING;

INSERT INTO public.admins (id, user_id, role, created_at)
SELECT a.id::uuid, a.user_id::uuid, a.role::admin_role, coalesce(a.created_at::timestamptz, now())
FROM legacy_stage.admins a
WHERE EXISTS (SELECT 1 FROM public.users u WHERE u.id = a.user_id::uuid)
ON CONFLICT DO NOTHING;

INSERT INTO public.quest_of_the_day (id, quest_id, display_date, ticket_no, bonus_xp,
                                     note, created_by, created_at, updated_at)
SELECT d.id::uuid, d.quest_id::uuid, d.display_date::date, d.ticket_no,
       coalesce(d.bonus_xp::int, 0), d.note,
       (SELECT id FROM public.users WHERE id = d.created_by::uuid),
       coalesce(d.created_at::timestamptz, now()), now()
FROM legacy_stage.quest_of_the_day d
WHERE EXISTS (SELECT 1 FROM public.quests q WHERE q.id = d.quest_id::uuid)
ON CONFLICT DO NOTHING;

-- reference_id is uuid here and text upstream; every non-null upstream value
-- is uuid-shaped, but the guard keeps a future stray value from failing the
-- whole transaction.
INSERT INTO public.notifications (id, user_id, actor_id, title, body, type,
                                  reference_id, is_read, created_at)
SELECT n.id::uuid, n.user_id::uuid,
       (SELECT id FROM public.users WHERE id = n.actor_id::uuid),
       n.title, n.body, n.type,
       CASE WHEN n.reference_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
            THEN n.reference_id::uuid END,
       coalesce(n.is_read::boolean, false), coalesce(n.created_at::timestamptz, now())
FROM legacy_stage.notifications n
WHERE EXISTS (SELECT 1 FROM public.users u WHERE u.id = n.user_id::uuid)
ON CONFLICT DO NOTHING;

INSERT INTO public.reports (id, reporter_id, reported_type, reported_id, reason,
                            admin_note, status, reviewed_by, reviewed_at, created_at)
SELECT r.id::uuid, r.reporter_id::uuid, r.reported_type, r.reported_id, r.reason,
       r.admin_note, coalesce(r.status, 'pending'),
       (SELECT id FROM public.users WHERE id = r.reviewed_by::uuid),
       r.reviewed_at::timestamptz, coalesce(r.created_at::timestamptz, now())
FROM legacy_stage.reports r
WHERE EXISTS (SELECT 1 FROM public.users u WHERE u.id = r.reporter_id::uuid)
ON CONFLICT DO NOTHING;

-- id is bigint upstream and uuid here, so new ids are minted. Keyed on
-- (user_id, rerolled_at) to stay idempotent across runs.
INSERT INTO public.quest_reroll_log (user_id, rerolled_at)
SELECT l.user_id::uuid, coalesce(l.rerolled_at::timestamptz, now())
FROM legacy_stage.quest_reroll_log l
WHERE EXISTS (SELECT 1 FROM public.users u WHERE u.id = l.user_id::uuid)
  AND NOT EXISTS (SELECT 1 FROM public.quest_reroll_log e
                  WHERE e.user_id = l.user_id::uuid
                    AND e.rerolled_at = coalesce(l.rerolled_at::timestamptz, now()));

-- net_score is denormalised from reactions; recompute rather than trust a
-- default of zero, or the feed's top/bottom sorts rank everything equally.
UPDATE public.submissions s SET net_score = agg.score
FROM (SELECT submission_id,
             count(*) FILTER (WHERE type = 'upvote')
           - count(*) FILTER (WHERE type = 'downvote') AS score
      FROM public.reactions GROUP BY submission_id) agg
WHERE agg.submission_id = s.id AND s.net_score <> agg.score;

COMMIT;
SQL

step "Verify"
dst -tA -F' | ' <<'SQL' | sed 's/^/  /'
SELECT 'users', count(*) FROM public.users
UNION ALL SELECT 'profiles', count(*) FROM public.profiles
UNION ALL SELECT 'quests', count(*) FROM public.quests
UNION ALL SELECT 'user_quests', count(*) FROM public.user_quests
UNION ALL SELECT 'submissions', count(*) FROM public.submissions
UNION ALL SELECT 'reactions', count(*) FROM public.reactions
UNION ALL SELECT 'comments', count(*) FROM public.comments
UNION ALL SELECT 'follows', count(*) FROM public.follows
UNION ALL SELECT 'saved_posts', count(*) FROM public.saved_posts
UNION ALL SELECT 'collab_groups', count(*) FROM public.collab_groups
UNION ALL SELECT 'admins', count(*) FROM public.admins
UNION ALL SELECT 'notifications', count(*) FROM public.notifications
UNION ALL SELECT 'reports', count(*) FROM public.reports
UNION ALL SELECT '--- media keys still holding a URL prefix (must be 0)', count(*)
  FROM public.submissions WHERE media_url LIKE '%r2.dev%'
UNION ALL SELECT '--- avatars still holding a URL prefix (must be 0)', count(*)
  FROM public.profiles WHERE avatar_url LIKE '%r2.dev%'
UNION ALL SELECT '--- approved+visible submissions (these show in the feed)', count(*)
  FROM public.submissions
  WHERE status = 'approved' AND visibility = 'visible' AND deleted_at IS NULL
UNION ALL SELECT '--- pending submissions (these show in the review queue)', count(*)
  FROM public.submissions WHERE status = 'pending'
UNION ALL SELECT '--- sum(profiles.xp)', coalesce(sum(xp), 0) FROM public.profiles
UNION ALL SELECT '--- sum(xp_awarded_amount) [the XP audit compares these]', coalesce(sum(xp_awarded_amount), 0)
  FROM public.submissions WHERE xp_awarded;
SQL

step "Done"
echo "  legacy_stage is left in place for inspection; drop it with:"
echo "    DROP SCHEMA legacy_stage CASCADE;"
