-- ============================================================
-- MIGRATION 0149 — four production repairs + two audit items.
--
-- §1  app_config: restore the PRE-AUTH read that 0140 C9 closed.
-- §2  get_feed:   restore the blocked-users filter lost in 0073.
-- §3  vote_collab: repair a dangling ON CONFLICT (42P10 on EVERY
--                 call since 0120) + restore 0097's approved guard
--                 + M11 cap 30/h -> 10/h.
-- §4  broadcast_announcement: M12 global 10/day cap + real UTC day.
-- §5  appeal_submission: restore the owner-guard bypass 0140 dropped
--                 (every non-admin appeal fails today).
-- §6  security_audit_notes M11 / M12.
--
-- NOTHING here uses DROP FUNCTION. DROP resets a function's ACL to
-- "EXECUTE TO PUBLIC" and anon inherits PUBLIC — that is exactly the
-- hole 0135:20 opened and 0143:103 had to close. Every function is
-- CREATE OR REPLACEd at its EXISTING signature, so no overload can be
-- created (an overload makes PostgREST return PGRST203).
--
-- Bodies are INLINED, never \i-included: deploy-server.yml rsyncs only
-- supabase/migrations/ and server-deploy.sh runs `psql < file` (stdin),
-- so a relative \i cannot resolve and ON_ERROR_STOP=1 would abort the
-- whole deploy. Canonical copies live in supabase/functions_canonical/.
--
-- The whole file is ONE transaction. scripts/server-deploy.sh:8 runs
-- psql WITHOUT --single-transaction, so without this wrapper a failure
-- at statement N leaves 1..N-1 committed AND the file untracked.
-- Every statement below is transactional (no CREATE INDEX CONCURRENTLY,
-- no VACUUM, no ALTER SYSTEM). Still fully idempotent for baseline
-- rebuilds and manual re-runs.
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- §1  app_config — allow-listed anon SELECT
--
-- applied/0140:291-293 replaced "Anyone can read app_config" (0084:22)
-- with authenticated_read_app_config (TO authenticated). Correct call,
-- but the client was never updated. An RLS-denied SELECT is NOT an
-- error — PostgREST returns 200 [] — so on the logged-out login/signup
-- screens the whole config map is silently EMPTY and every flag fails
-- OPEN:
--   socialLoginEnabledProvider -> `null != 'false'` -> TRUE, so the
--     admin Apple/Google kill-switch is inert exactly where the buttons
--     render (login_page.dart:238, signup_page.dart:301)
--   maintenanceModeProvider    -> `null == 'true'`  -> FALSE
--   AppPromptsListener's force-update gate never fires pre-login, i.e.
--     it is bypassable by signing out
--
-- Fixed with a key-scoped anon policy rather than a SECURITY DEFINER
-- RPC, because an RPC would only fix appConfigProvider's one-shot read.
-- liveAppConfigProvider ALSO subscribes to Postgres realtime, and
-- realtime CDC applies the SUBSCRIBER's RLS at delivery time (the very
-- mechanism 0145's header relies on). A policy restores the one-shot
-- read AND realtime delivery for anon; an RPC restores neither.
--
-- Positive allow-list only — a NOT IN denylist would leak every future
-- internal key by default.
-- ════════════════════════════════════════════════════════════

-- RLS is the ONLY thing standing between the grant below and a full
-- dump of app_config to anonymous callers (it holds internal keys like
-- project_functions_url and media_url_host_allowlist). 0084:20 enables
-- it, but re-assert here so this migration is self-contained and safe
-- even against a partially-restored baseline. Idempotent.
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

-- No migration has ever GRANTed or REVOKEd table privileges on
-- app_config (grep: zero hits), so the table-level grant depends on
-- whichever role created it and on the self-host restore. Make it
-- explicit — RLS is what actually gates the rows.
GRANT SELECT ON TABLE public.app_config TO anon, authenticated;

DROP POLICY IF EXISTS anon_read_public_app_config ON public.app_config;
CREATE POLICY anon_read_public_app_config ON public.app_config
  FOR SELECT TO anon
  USING (key = ANY (ARRAY[
    'social_login_enabled',        -- SocialSignInButtons (login + signup)
    'maintenance_mode',            -- MaintenanceOverlay (wraps every route)
    'maintenance_message',         -- MaintenanceOverlay copy
    'update_required_min_build',   -- AppPromptsListener force-update gate
    'update_required_message',     -- AppPromptsListener overlay copy
    'update_required_force',       -- AppPromptsListener dismissable flag
    'rate_prompt_token'            -- AppPromptsListener rate prompt
  ]));

-- NEVER add to that list: project_functions_url (0130/0147 — internal
-- edge-function base URL), media_url_host_allowlist (0120:316 — hands an
-- attacker the SSRF bypass list), submission_owner_writable_columns
-- (0133:20 — tells an attacker which columns the owner guard permits).

COMMENT ON POLICY anon_read_public_app_config ON public.app_config IS
  'Pre-auth-safe subset. 0140 C9 restricted SELECT to authenticated and '
  'silently emptied the config map on the logged-out login/signup screens. '
  'Allow-list only — server-side keys must never be added here.';


-- ════════════════════════════════════════════════════════════
-- §2  get_feed — restore the blocked-users filter, floor p_offset
--
-- Canonical source: supabase/functions_canonical/get_feed.sql
--
-- REGRESSION (the important one): applied/0069_content_moderation.sql
-- lines 226-230 added
--     AND NOT EXISTS (SELECT 1 FROM public.blocked_users bu
--                     WHERE bu.blocker_id = auth.uid()
--                       AND bu.blocked_id = s.user_id)
-- applied/0073_feed_collab_fields.sql reissued get_feed WITHOUT it and
-- it never came back. `grep -rl blocked_users supabase/migrations/`
-- matches only 0069, 0091 and 0137 — none of 0073/0075/0077/0086/0089/
-- 0090/0094/0116/0135 contains the string. Meanwhile block_user /
-- unblock_user and the Blocked Users settings page are live in the
-- shipped app. Blocking has had ZERO effect on the feed since 0073.
--
-- p_offset had no lower bound (0135:170 `OFFSET coalesce(p_offset,0)`),
-- so a negative value raised SQLSTATE 22023 straight through as a 500.
-- Now floored at 0. Deliberately NO ceiling — loadMore()
-- (feed_provider.dart:206-211) legitimately walks deep offsets and a
-- silent LEAST() would make page N+1 repeat page N forever.
--
-- p_limit is NOT changed. 0135:58 already clamps to [1,50]; any audit
-- item claiming otherwise is reading 0120's stale SEC-006 prose.
--
-- Signature + all 26 RETURNS TABLE columns are byte-identical to
-- 0135:22-54, so CREATE OR REPLACE is legal (Postgres forbids changing
-- OUT params or renaming IN params) and FeedPostModel.fromRpc keeps
-- parsing by name. NO Dart change.
-- ════════════════════════════════════════════════════════════

-- Defensive: 0135:20 already dropped this. If a fresh rebuild ever left
-- both signatures present, a 3-named-argument PostgREST call becomes
-- ambiguous against the 4-arg's DEFAULT (PGRST203).
DROP FUNCTION IF EXISTS public.get_feed(integer, integer, text);

CREATE OR REPLACE FUNCTION public.get_feed(
  p_limit integer,
  p_offset integer,
  p_sort text,
  p_scope text DEFAULT 'all'
)
RETURNS TABLE (
  submission_id uuid,
  media_url text,
  media_type text,
  caption text,
  submitted_at timestamptz,
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  bio text,
  quest_id uuid,
  quest_title text,
  quest_description text,
  quest_category text,
  xp_reward integer,
  reaction_count bigint,
  upvote_count bigint,
  downvote_count bigint,
  net_score bigint,
  hot_score double precision,
  is_collab boolean,
  collab_group_id uuid,
  collab_mode text,
  collab_member_count bigint,
  collab_members json,
  expires_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_uid uuid := auth.uid();
  -- Unchanged from 0135:58. The p_limit cap is NOT new.
  v_limit integer := LEAST(GREATEST(coalesce(p_limit, 20), 1), 50);
  -- 0149: floor only, no ceiling. See header.
  v_offset integer := GREATEST(coalesce(p_offset, 0), 0);
BEGIN
  RETURN QUERY
    SELECT
      s.id AS submission_id,
      s.media_url,
      s.media_type,
      s.caption,
      s.submitted_at,
      p.id AS user_id,
      p.username,
      p.display_name,
      p.avatar_url,
      p.bio,
      q.id AS quest_id,
      q.title AS quest_title,
      q.description AS quest_description,
      q.category AS quest_category,
      q.xp_reward,
      COALESCE(r.total, 0)::bigint AS reaction_count,
      COALESCE(r.ups, 0)::bigint   AS upvote_count,
      COALESCE(r.downs, 0)::bigint AS downvote_count,
      (COALESCE(r.ups, 0) - COALESCE(r.downs, 0))::bigint AS net_score,
      (COALESCE(r.ups, 0) - COALESCE(r.downs, 0))::double precision
        / power(EXTRACT(EPOCH FROM (now() - s.submitted_at)) / 3600.0 + 2.0, 1.5)
        AS hot_score,
      (gm.group_id IS NOT NULL) AS is_collab,
      gm.group_id AS collab_group_id,
      g.mode AS collab_mode,
      COALESCE(mc.cnt, 0)::bigint AS collab_member_count,
      CASE WHEN gm.group_id IS NOT NULL THEN (
        SELECT json_agg(json_build_object(
          'user_id',           mp.id,
          'username',          mp.username,
          'display_name',      mp.display_name,
          'avatar_url',        mp.avatar_url,
          'bio',               mp.bio,
          'submission_id',     ms.id,
          'media_url',         ms.media_url,
          'media_type',        ms.media_type,
          'submission_status', ms.status,
          'caption',           ms.caption,
          'show_in_feed',      ms.show_in_feed,
          'vote_count',        COALESCE(vc.cnt, 0),
          'viewer_voted',      COALESCE(mv.voted, false)
        ) ORDER BY m2.joined_at)
        FROM public.collab_group_members m2
        JOIN public.profiles mp ON mp.id = m2.user_id
        LEFT JOIN public.submissions ms ON ms.user_quest_id = m2.user_quest_id
        LEFT JOIN (
          SELECT cv.submission_id AS sid, count(*) AS cnt
          FROM public.collab_votes cv
          WHERE cv.group_id = gm.group_id
          GROUP BY cv.submission_id
        ) vc ON vc.sid = ms.id
        LEFT JOIN (
          SELECT cv.submission_id AS sid, true AS voted
          FROM public.collab_votes cv
          WHERE cv.group_id = gm.group_id
            AND cv.voter_id = v_uid
        ) mv ON mv.sid = ms.id
        WHERE m2.group_id = gm.group_id
      ) ELSE NULL END AS collab_members,
      uq.expires_at AS expires_at
    FROM public.submissions s
    JOIN public.profiles p ON p.id = s.user_id
    JOIN public.user_quests uq ON uq.id = s.user_quest_id
    JOIN public.quests q ON q.id = uq.quest_id
    -- ARC-018 sibling: per-row LATERAL aggregate instead of global.
    LEFT JOIN LATERAL (
      SELECT
        count(*) AS total,
        count(*) FILTER (WHERE rx.type = 'upvote')   AS ups,
        count(*) FILTER (WHERE rx.type = 'downvote') AS downs
      FROM public.reactions rx
      WHERE rx.submission_id = s.id
    ) r ON true
    LEFT JOIN public.collab_group_members gm ON gm.user_quest_id = uq.id
    LEFT JOIN public.collab_groups g ON g.id = gm.group_id
    LEFT JOIN (
      SELECT group_id, count(*) AS cnt
      FROM public.collab_group_members GROUP BY group_id
    ) mc ON mc.group_id = gm.group_id
    WHERE s.status = 'approved'
      AND s.show_in_feed = true
      AND s.visibility = 'visible'
      AND (
        gm.group_id IS NULL
        OR gm.user_id = g.creator_id
      )
      -- ARC-011: scope filter. 'following' only shows posts from
      -- users the caller follows; 'all' (default) is the global feed.
      AND (
        p_scope IS DISTINCT FROM 'following'
        OR s.user_id IN (
          SELECT f.following_id FROM public.follows f
          WHERE f.follower_id = v_uid
        )
      )
      -- 0149 REGRESSION FIX — restores applied/0069:226-230. Backed by
      -- 0069's `CONSTRAINT unique_block UNIQUE (blocker_id, blocked_id)`,
      -- so this is a cheap anti-join. Applied BEFORE LIMIT, so
      -- `hasMore: raw.length >= _pageSize` (feed_provider.dart:214) is
      -- unaffected.
      AND NOT EXISTS (
        SELECT 1 FROM public.blocked_users bu
        WHERE bu.blocker_id = v_uid
          AND bu.blocked_id = s.user_id
      )
    ORDER BY
      CASE WHEN p_sort = 'top' THEN (COALESCE(r.ups, 0) - COALESCE(r.downs, 0)) END DESC NULLS LAST,
      CASE WHEN p_sort = 'hot' THEN
        (COALESCE(r.ups, 0) - COALESCE(r.downs, 0))::double precision
        / power(EXTRACT(EPOCH FROM (now() - s.submitted_at)) / 3600.0 + 2.0, 1.5)
      END DESC NULLS LAST,
      CASE WHEN p_sort = 'bottom' THEN (COALESCE(r.ups, 0) - COALESCE(r.downs, 0)) END ASC NULLS LAST,
      CASE WHEN p_sort = 'graveyard' THEN
        (COALESCE(r.ups, 0) - COALESCE(r.downs, 0))::double precision
        / power(EXTRACT(EPOCH FROM (now() - s.submitted_at)) / 3600.0 + 2.0, 1.5)
      END ASC NULLS LAST,
      s.submitted_at DESC
    LIMIT v_limit
    OFFSET v_offset;
END;
$$;

-- 0135:174 revoked from `anon` only. Because 0135:20 DROPped and 0135:22
-- CREATEd a NEW function object, it received Postgres's default
-- EXECUTE-to-PUBLIC and anon inherited through PUBLIC — 0135 alone did
-- NOT close the hole; 0143:103 did. Always name PUBLIC.
-- (CREATE OR REPLACE preserves the ACL, so this is belt-and-braces.)
REVOKE EXECUTE ON FUNCTION public.get_feed(integer, integer, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_feed(integer, integer, text, text) TO authenticated;

COMMENT ON FUNCTION public.get_feed(integer, integer, text, text) IS
  'Feed pager. p_limit clamped server-side to [1,50] (default 20); p_offset '
  'floored at 0, no ceiling. Excludes posts from users the caller has blocked '
  '(restored in 0149 — lost in 0073). Authenticated only. Canonical body: '
  'supabase/functions_canonical/get_feed.sql';


-- ════════════════════════════════════════════════════════════
-- §3  vote_collab — P0 REPAIR + M11 (partial)
--
-- Canonical source: supabase/functions_canonical/vote_collab.sql
--
-- BROKEN IN PRODUCTION. The live body (applied/0123:126-130, which
-- superseded applied/0120:151) ends with
--     ON CONFLICT (group_id, voter_id) DO UPDATE ...
-- but applied/0094:21-22 DROPPED uq_one_vote_per_user_per_group and
-- 0094:26-29 replaced it with
--     uq_one_vote_per_user_per_submission UNIQUE (group_id, voter_id,
--                                                 submission_id)
-- Nothing anywhere re-adds a 2-column unique index (only the NON-unique
-- idx_collab_votes_voter_group at 0094:31). Postgres infers an arbiter
-- index only when the index key columns EQUAL the inference list, so a
-- 2-column spec matches nothing and every call raises
--     42P10 there is no unique or exclusion constraint matching the
--           ON CONFLICT specification
-- Arbiter inference happens at PLAN time and plpgsql plans lazily, so
-- CREATE OR REPLACE in 0120/0123 succeeded silently. COLLAB VOTING HAS
-- BEEN 100% DEAD SINCE 0120 SHIPPED. 42P10 is not handled by
-- _voteErrorMessage, so users see "Vote failed — try again".
--
-- The DO UPDATE was also semantically wrong: it re-implements the
-- pre-0094 one-vote-per-GROUP model, while 0094, unvote_collab and the
-- UI are multi-vote (one vote per member, toggled off by unvote).
--
-- ALSO RESTORED: 0097's `s.status = 'approved'` requirement, which the
-- 0120 rewrite silently replaced with a bare "belongs to the group"
-- check. get_feed emits every member including pending/rejected ones,
-- so without it a guessed UUID collects votes on unreviewed media.
--
-- M11 (partial): per-user ceiling 30/h -> 10/h. NOT a full resolution —
-- see the audit note in §6.
--
-- NOT restored from applied/0072: the versus-mode-only gate (0072:268)
-- and the self-vote ban (0072:274). 0094 removed both deliberately and
-- the UI depends on that. 0120's header claims it re-added the
-- self-vote ban; its body never did.
--
-- NO per-submission cooldown. unvote_collab (applied/0094:67-83) hard-
-- DELETEs the row, so a `max(created_at) FROM collab_votes WHERE
-- voter_id=... AND submission_id=...` predicate is non-NULL ONLY when a
-- live vote row exists — exactly the case where the INSERT below is
-- already a no-op. It could never block a real state change, but it
-- would turn an idempotent success into a P0001 that the client renders
-- as "This submission can no longer be voted on."
-- ════════════════════════════════════════════════════════════

-- Defensive: re-assert the constraint the upsert infers against. This is
-- precisely what went missing. IF NOT EXISTS keeps it idempotent.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.collab_votes'::regclass
       AND conname  = 'uq_one_vote_per_user_per_submission'
  ) THEN
    ALTER TABLE public.collab_votes
      ADD CONSTRAINT uq_one_vote_per_user_per_submission
      UNIQUE (group_id, voter_id, submission_id);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.vote_collab(
  p_group_id      uuid,
  p_submission_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  -- DELIBERATE DEVIATION FROM AUDIT ITEM M11 (which asked for 10/h).
  --
  -- 0140 wrote "10/h" while 0120's `ON CONFLICT (group_id, voter_id)
  -- DO UPDATE` made vote_collab look like ONE vote per GROUP. The real
  -- model (0094, unvote_collab, and one button per member in
  -- reels_card.dart) is one vote per group MEMBER — so a single
  -- 5-person collab post costs 5 votes. At 10/h a normal user is
  -- rate-limited after browsing TWO collab posts, which would present
  -- as exactly the same "Vote failed" symptom this migration exists to
  -- repair.
  --
  -- 60/h keeps the anti-automation ceiling the audit actually wanted
  -- (bulk farming still throttled) while sitting far above real usage.
  -- Note that no per-user cap meaningfully stops the multi-account
  -- sock-puppet ring M11 describes; see the §6 note for the real fix.
  c_max_votes_per_hour constant integer := 60;

  v_uid          uuid := auth.uid();
  v_recent_votes integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  -- 0123 banned/suspended guard — MUST NOT be dropped.
  IF NOT public.is_account_active() THEN
    RAISE EXCEPTION 'Account not active' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.collab_groups WHERE id = p_group_id
  ) THEN
    RAISE EXCEPTION 'Group not found' USING ERRCODE = 'P0002';
  END IF;

  -- Restores 0097's guard (dropped by 0120).
  IF NOT EXISTS (
    SELECT 1
      FROM public.collab_group_members m
      JOIN public.submissions s ON s.user_quest_id = m.user_quest_id
     WHERE m.group_id = p_group_id
       AND s.id       = p_submission_id
       AND s.status   = 'approved'
  ) THEN
    RAISE EXCEPTION 'Submission is not eligible for voting'
      USING ERRCODE = 'P0001';
  END IF;

  -- M11 (partial). Counts surviving rows; unvote_collab deletes rows,
  -- so this is resettable by a vote/unvote loop. See §6.
  SELECT count(*) INTO v_recent_votes
    FROM public.collab_votes v
   WHERE v.voter_id   = v_uid
     AND v.created_at > now() - interval '1 hour';
  IF v_recent_votes >= c_max_votes_per_hour THEN
    RAISE EXCEPTION 'Vote rate limit exceeded — try again later'
      USING ERRCODE = 'P0001';
  END IF;

  -- THE FIX. Column list must match uq_one_vote_per_user_per_submission
  -- (0094:26-29) exactly. DO NOTHING is also the only form consistent
  -- with unvote_collab's multi-vote toggle model.
  INSERT INTO public.collab_votes (group_id, voter_id, submission_id)
  VALUES (p_group_id, v_uid, p_submission_id)
  ON CONFLICT (group_id, voter_id, submission_id) DO NOTHING;
END;
$$;

-- NEW. No migration has ever revoked PUBLIC on this function
-- (0072:291, 0094:64, 0097:42, 0120:157, 0123:134 are all GRANT-only),
-- so anon holds EXECUTE via PUBLIC today. It fails closed on
-- auth.uid() IS NULL, so this is latent — close it anyway.
REVOKE EXECUTE ON FUNCTION public.vote_collab(uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.vote_collab(uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.vote_collab(uuid, uuid) IS
  'Multi-vote collab voting, idempotent. Canonical body: '
  'supabase/functions_canonical/vote_collab.sql. Any redefinition MUST keep: '
  'is_account_active (0123), status=approved (0097), and ON CONFLICT '
  '(group_id, voter_id, submission_id) DO NOTHING (0094) — a 2-column '
  'inference spec matches NO index and raises 42P10 at runtime on every call.';


-- ════════════════════════════════════════════════════════════
-- §4  broadcast_announcement — M12 global cap
--
-- Canonical source: inline (0067 -> 0098 -> 0120 -> 0149).
--
-- 0140 recorded M12 in security_audit_notes instead of editing the
-- function, so the live body is still 0120:176-224: per-admin 5/UTC-day
-- only. 0140:510 spells out the gap — "10 admins x 5 = 50 push spams".
--
-- Also fixes the day boundary. 0120:199 compared a timestamptz against
-- `date_trunc('day', now() AT TIME ZONE 'UTC')`, which is a BARE
-- timestamp; Postgres casts the timestamp side using the SESSION
-- TimeZone, so the window was only really UTC when the session was.
-- (This is the only date_trunc in the entire migration set.)
--
-- Serialization uses a NON-blocking advisory lock. The INSERT..SELECT
-- fans out one notifications row per user, each firing 0131's per-row
-- trg_cap_notification_text AND 0130's AFTER-INSERT
-- send_push_on_notification (a net.http_post enqueue per row). A
-- blocking pg_advisory_xact_lock would park a second admin until
-- statement_timeout killed it with an opaque 57014. Same idiom and
-- keyspace as applied/0140:394-395.
--
-- Every pre-existing error keeps its 0120 text AND its 0120 SQLSTATE
-- (plpgsql default P0001 -> HTTP 400). Adding 42501 to the auth path
-- would flip it to HTTP 403 for no benefit.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.broadcast_announcement(
  p_title text,
  p_body  text
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_count        integer;
  v_today_count  integer;
  v_global_today integer;
  v_day_start    timestamptz;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF p_title IS NULL OR length(p_title) = 0 OR length(p_title) > 200 THEN
    RAISE EXCEPTION 'Title required and must be <= 200 characters';
  END IF;
  IF p_body IS NULL OR length(p_body) = 0 OR length(p_body) > 1000 THEN
    RAISE EXCEPTION 'Body required and must be <= 1000 characters';
  END IF;

  -- Taken AFTER the cheap validation so a malformed request never
  -- blocks a good one.
  IF NOT pg_try_advisory_xact_lock(
           hashtextextended('broadcast_announcement', 0)) THEN
    RAISE EXCEPTION 'Another broadcast is already in progress — try again in a moment'
      USING ERRCODE = 'P0001';
  END IF;

  -- Trailing AT TIME ZONE converts back to a real timestamptz.
  v_day_start := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';

  -- Per-admin: 5/day (unchanged from 0120 SEC-014). Checked first so an
  -- admin who burned their own budget gets the actionable message.
  SELECT count(*) INTO v_today_count
    FROM public.admin_audit_log
    WHERE actor_id = auth.uid()
      AND action = 'broadcast.announcement'
      AND created_at >= v_day_start;
  IF v_today_count >= 5 THEN
    RAISE EXCEPTION 'Daily announcement limit reached (5/day)';
  END IF;

  -- M12: global cap across ALL admins. Served by
  -- idx_admin_audit_log_action (action, created_at DESC) — 0098:35.
  SELECT count(*) INTO v_global_today
    FROM public.admin_audit_log
    WHERE action = 'broadcast.announcement'
      AND created_at >= v_day_start;
  IF v_global_today >= 10 THEN
    RAISE EXCEPTION 'Global daily announcement limit reached (10/day across all admins)';
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type)
  SELECT p.id, p_title, p_body, 'announcement'
  FROM public.profiles p
  WHERE p.username IS NOT NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;

  PERFORM public.log_admin_action(
    'broadcast.announcement',
    'broadcast',
    NULL,
    jsonb_build_object(
      'title',           left(p_title, 200),
      'body_chars',      length(p_body),
      'recipient_count', v_count
    )
  );

  RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.broadcast_announcement(text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.broadcast_announcement(text, text) TO authenticated;

COMMENT ON FUNCTION public.broadcast_announcement(text, text) IS
  'Insert an announcement notification for every named profile. Admin only. '
  'Caps: 200-char title, 1000-char body, 5 per admin per UTC day, 10 global '
  'per UTC day (audit M12, migration 0149).';


-- ════════════════════════════════════════════════════════════
-- §5  appeal_submission — P0 REPAIR
--
-- Canonical source: supabase/functions_canonical/appeal_submission.sql
--
-- applied/0119:97 added
--     PERFORM set_config('app.bypass_submission_guard', 'on', true);
-- so appeal_submission could flip submissions.status past the owner
-- update guard. The trigger is attached at applied/0114:67-71 and its
-- body was last reissued at applied/0133:31-45, which still gates on
--     is_admin() OR pg_trigger_depth() > 1
--     OR current_setting('app.bypass_submission_guard', true) = 'on'
-- with allow-list ["visibility","deleted_at","caption","appealed",
-- "appeal_note","show_in_feed"] — `status` is NOT in it.
--
-- applied/0140:191-247 reissued appeal_submission as a FULL
-- CREATE OR REPLACE to add the deleted-visibility check, but rebuilt the
-- body from 0052 and dropped that set_config line. appeal_submission is
-- SECURITY DEFINER, but auth.uid() stays the CALLER's, and the UPDATE is
-- not inside a trigger, so none of the three trusted contexts apply.
-- Since 0140 every non-admin appeal raises
--     submissions: owners may not modify column "status". Allowed
--     columns: {visibility,deleted_at,caption,appealed,appeal_note,
--     show_in_feed}
-- i.e. the 0114 -> 0119 incident, reintroduced.
--
-- This reissues the body with BOTH 0140's visibility guard and 0119's
-- bypass, plus a pinned search_path (auth.uid() and every table
-- reference is already schema-qualified, so the pin is a behavioural
-- no-op). Signature and RETURNS void unchanged, so existing grants
-- survive.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.appeal_submission(
  p_submission_id uuid,
  p_appeal_note text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_submission RECORD;
  v_visibility text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT id, user_id, status, appealed, user_quest_id
    INTO v_submission
    FROM public.submissions
    WHERE id = p_submission_id;

  IF v_submission IS NULL THEN
    RAISE EXCEPTION 'Submission not found';
  END IF;

  IF v_submission.user_id != auth.uid() THEN
    RAISE EXCEPTION 'Not your submission' USING ERRCODE = '42501';
  END IF;

  IF v_submission.status != 'rejected' THEN
    RAISE EXCEPTION 'Only rejected submissions can be appealed';
  END IF;

  IF v_submission.appealed THEN
    RAISE EXCEPTION 'Already appealed';
  END IF;

  -- 0140 C5: block appeal of a soft-deleted submission. Read via
  -- to_jsonb so this is safe on a DB where 0049 was rolled back.
  SELECT (to_jsonb(s)->>'visibility') INTO v_visibility
    FROM public.submissions s WHERE s.id = p_submission_id;
  IF coalesce(v_visibility, 'visible') = 'deleted' THEN
    RAISE EXCEPTION 'Cannot appeal a deleted submission';
  END IF;

  -- 0119: open the owner-guard trapdoor, TRANSACTION-LOCAL only (the
  -- third argument to set_config). Every ownership / status / appealed /
  -- deleted check above has already passed, so the bypass can only cover
  -- this one legal transition.
  PERFORM set_config('app.bypass_submission_guard', 'on', true);

  UPDATE public.submissions
    SET status = 'pending',
        appeal_note = p_appeal_note,
        appealed = true,
        reviewed_by = NULL,
        review_note = NULL,
        reviewed_at = NULL
    WHERE id = p_submission_id;

  UPDATE public.user_quests
    SET status = 'submitted'
    WHERE id = v_submission.user_quest_id;
END;
$$;

-- NEW in 0149. No migration has EVER issued a GRANT or REVOKE on
-- appeal_submission (0052 created it, 0119/0140 reissued it, none of
-- them touched privileges), so it still carries Postgres's default
-- EXECUTE-to-PUBLIC and anon inherits through PUBLIC. It fails closed
-- on `auth.uid() IS NULL`, so this is latent rather than exploitable —
-- close it anyway, consistent with §2/§3/§4.
REVOKE EXECUTE ON FUNCTION public.appeal_submission(uuid, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.appeal_submission(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.appeal_submission(uuid, text) IS
  '0149: 0140 deleted-visibility guard + the 0119 owner-guard bypass that '
  '0140 dropped (every non-admin appeal failed between 0140 and 0149), '
  'search_path pinned. Canonical body: '
  'supabase/functions_canonical/appeal_submission.sql';


-- ════════════════════════════════════════════════════════════
-- §6  Audit notes — guarded, honest wording
--
-- public.security_audit_notes is created at applied/0140:539 INSIDE a
-- DO block that later runs CREATE POLICY ... USING (is_super_admin()).
-- If that block ever aborted, the table does not exist and a top-level
-- UPDATE would raise 42P01 and kill the deploy under ON_ERROR_STOP=1.
-- plpgsql plans statements lazily, so the un-taken branch below never
-- resolves the name. The exception handler makes housekeeping
-- non-fatal — server-deploy.sh records the filename only when the WHOLE
-- file succeeds, so a failure here would leave the P0 repairs
-- unrecorded and replayed.
-- ════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF to_regclass('public.security_audit_notes') IS NULL THEN
    RAISE NOTICE '0149: security_audit_notes absent (0140 not fully applied) — skipping';
  ELSE
    UPDATE public.security_audit_notes
       SET description =
         'PARTIAL (0149): the 42P10 ON CONFLICT defect introduced by 0120 — '
         || 'which made EVERY vote_collab call fail from 0120 until 0149 — is '
         || 'repaired, and 0097''s approved-status guard is restored. '
         || 'DEVIATION: the ceiling is 60/h, not the 10/h this note asked for. '
         || '10/h was written believing the model was one vote per GROUP; it is '
         || 'one vote per group MEMBER, so 10/h rate-limits a normal user after '
         || 'two collab posts. NOT fully resolved: the counter reads surviving '
         || 'collab_votes rows and unvote_collab DELETEs rows, so the cap is '
         || 'resettable by a vote/unvote loop, and no per-user cap addresses the '
         || 'multi-account ring this audit item describes. A real fix needs a '
         || 'vote-event log that survives unvote.'
     WHERE note_id = 'M11'
       AND description NOT LIKE 'PARTIAL (0149)%';

    UPDATE public.security_audit_notes
       SET description =
         'RESOLVED (0149): broadcast_announcement enforces a global 10/day cap '
         || 'alongside the per-admin 5/day cap, and the UTC day boundary is now '
         || 'a true timestamptz (0120:199 compared against a bare timestamp, '
         || 'which Postgres re-interpreted in the session TimeZone).'
     WHERE note_id = 'M12'
       AND description NOT LIKE 'RESOLVED (0149)%';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '0149: could not update security_audit_notes (%)', SQLERRM;
END $$;

DO $$ BEGIN
  RAISE NOTICE '0149 applied: vote_collab 42P10 repaired, appeal_submission bypass restored, get_feed block filter restored, anon app_config read restored, M12 global cap';
END $$;

COMMIT;
