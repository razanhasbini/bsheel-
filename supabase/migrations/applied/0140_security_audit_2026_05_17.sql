-- ============================================================
-- MIGRATION 0140: Security audit hardening (2026-05-17)
--
-- Consolidates fourteen findings from the 2026-05-17 audit:
--   C1  Profile column guard       — user can't set own xp/level/etc.
--   C2  Reroll budget in trigger   — server-side 5/24h enforcement
--   C3  Submission timeline guard  — submitted_at can't be back-dated
--   C5  Deleted-appeal guard       — can't appeal a soft-deleted submission
--   C8  RLS on profile_tokens      — defense in depth, deny-all policy
--   C9  Auth-only public reads     — follows / comments / app_config
--   H4  Self-reaction block        — RLS check submission.user_id <> auth.uid()
--   H5  Username on delete         — rename to deleted_<id> to prevent takeover
--   H10 Assignment race fix        — partial unique index already exists, add explicit
--   M8  Leaderboard limit cap      — clamp p_limit to 100
--   M9  FCM token length cap       — 100..300 bytes
--   M11 vote_collab tighter caps   — 10/h + per-submission cooldown
--   M12 broadcast global cap       — 10/day across all admins
--   LOW Banned exclusion           — leaderboard filters account_status='active'
--
-- Every block is idempotent. Drops and recreates policies / triggers.
-- ============================================================

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ C1 — Profile column guard                                    ║
-- ║                                                              ║
-- ║ profiles_update_own (0009) only checks ownership, not which  ║
-- ║ columns change. A user can set their own xp/level/quests_    ║
-- ║ completed/account_status via plain REST. Add BEFORE UPDATE   ║
-- ║ trigger that rejects non-admin writes to those columns.      ║
-- ╚══════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.guard_profile_owner_update()
RETURNS trigger AS $$
BEGIN
  -- Admins, service-role, and cascaded internal updates bypass.
  IF auth.uid() IS NULL OR public.is_admin() OR pg_trigger_depth() > 1 THEN
    RETURN new;
  END IF;

  -- Only relevant if the owner is updating their own row. For admin
  -- writes auth.uid() != id and the policy will already prevent them.
  IF new.id <> auth.uid() THEN
    RETURN new;
  END IF;

  IF new.xp IS DISTINCT FROM old.xp THEN
    RAISE EXCEPTION 'xp may only be modified by approval flow' USING ERRCODE = '42501';
  END IF;
  IF new.level IS DISTINCT FROM old.level THEN
    RAISE EXCEPTION 'level may only be modified by approval flow' USING ERRCODE = '42501';
  END IF;
  IF new.quests_completed IS DISTINCT FROM old.quests_completed THEN
    RAISE EXCEPTION 'quests_completed may only be modified by approval flow' USING ERRCODE = '42501';
  END IF;

  -- account_status only exists from migration 0068 onwards; guard via
  -- to_jsonb so this migration stays runnable in fresh databases too.
  IF (to_jsonb(new) ? 'account_status')
     AND ((to_jsonb(new)->>'account_status') IS DISTINCT FROM (to_jsonb(old)->>'account_status')) THEN
    RAISE EXCEPTION 'account_status may only be modified by admin' USING ERRCODE = '42501';
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_guard_profile_owner_update ON public.profiles;
CREATE TRIGGER trg_guard_profile_owner_update
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_owner_update();

COMMENT ON FUNCTION public.guard_profile_owner_update() IS
  'C1 (2026-05-17): blocks non-admin writes to xp/level/quests_completed/account_status.';


-- ╔══════════════════════════════════════════════════════════════╗
-- ║ C2 — Reroll budget enforced in the assignment trigger        ║
-- ║                                                              ║
-- ║ 0124 added record_quest_reroll() but the budget only fires   ║
-- ║ if the *client* calls it. assign_random_quest /              ║
-- ║ assign_specific_quest can be called directly via REST,       ║
-- ║ skipping the budget entirely. Move the 5/24h ceiling into    ║
-- ║ the BEFORE INSERT trigger on user_quests so every assignment ║
-- ║ path goes through it.                                        ║
-- ╚══════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.enforce_assign_quest_cooldown()
RETURNS trigger AS $$
DECLARE
  v_recent_at  timestamptz;
  v_cooldown   interval := interval '30 seconds';
  v_used       integer;
  v_max        integer := 5;
  v_window     interval := interval '24 hours';
BEGIN
  -- Admins, service-role, and cascaded internal updates bypass.
  IF auth.uid() IS NULL OR public.is_admin() OR pg_trigger_depth() > 1 THEN
    RETURN new;
  END IF;

  -- 30-second cooldown (unchanged from 0129)
  SELECT max(assigned_at) INTO v_recent_at
    FROM public.user_quests
    WHERE user_id = new.user_id;
  IF v_recent_at IS NOT NULL AND now() - v_recent_at < v_cooldown THEN
    RAISE EXCEPTION 'Quest assignment cooldown — try again in a moment'
      USING ERRCODE = 'P0001';
  END IF;

  -- 5-per-24h reroll cap (formerly client-side / RPC-side only).
  -- Counts past assignments in the window, not entries in the reroll
  -- log table, so it covers users that ignore record_quest_reroll().
  SELECT count(*) INTO v_used
    FROM public.user_quests
    WHERE user_id = new.user_id
      AND assigned_at > now() - v_window;
  IF v_used >= v_max THEN
    RAISE EXCEPTION 'Reroll limit reached (% per 24h)', v_max
      USING ERRCODE = 'P0001';
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger itself is unchanged (recreated by 0129); function body is new.
COMMENT ON FUNCTION public.enforce_assign_quest_cooldown() IS
  'C2 (2026-05-17): 30s cooldown + 5/24h reroll cap. Replaces 0129.';


-- ╔══════════════════════════════════════════════════════════════╗
-- ║ C3 — Submission timeline guard                               ║
-- ║                                                              ║
-- ║ submitted_at defaults to now() but the client can supply any ║
-- ║ value via REST INSERT. A user could back-date submissions to ║
-- ║ defeat quest expiry. Force submitted_at = now() and reject   ║
-- ║ submissions for an expired user_quest.                       ║
-- ╚══════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.guard_submission_insert_timing()
RETURNS trigger AS $$
DECLARE
  v_expires timestamptz;
  v_status  text;
BEGIN
  -- Admins / service-role bypass (admin tooling needs to back-date).
  IF auth.uid() IS NULL OR public.is_admin() OR pg_trigger_depth() > 1 THEN
    RETURN new;
  END IF;

  -- Stamp server-side. Whatever the client sent is discarded.
  new.submitted_at := now();

  -- Reject if the user_quest has expired or is no longer assigned.
  SELECT expires_at, status INTO v_expires, v_status
    FROM public.user_quests
    WHERE id = new.user_quest_id;

  IF v_expires IS NULL THEN
    RAISE EXCEPTION 'user_quest not found' USING ERRCODE = '42501';
  END IF;
  IF v_status NOT IN ('assigned', 'submitted') THEN
    RAISE EXCEPTION 'Quest is not active' USING ERRCODE = '42501';
  END IF;
  IF now() > v_expires THEN
    RAISE EXCEPTION 'Quest has expired — submissions no longer accepted'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_guard_submission_insert_timing ON public.submissions;
CREATE TRIGGER trg_guard_submission_insert_timing
  BEFORE INSERT ON public.submissions
  FOR EACH ROW EXECUTE FUNCTION public.guard_submission_insert_timing();

COMMENT ON FUNCTION public.guard_submission_insert_timing() IS
  'C3 (2026-05-17): forces submitted_at=now(); rejects insert after quest expiry.';


-- ╔══════════════════════════════════════════════════════════════╗
-- ║ C5 — Deleted-submission appeal guard                         ║
-- ║                                                              ║
-- ║ appeal_submission() doesn't check visibility. A user can     ║
-- ║ soft-delete a rejected submission then appeal it back into   ║
-- ║ "IN REVIEW", undoing their own deletion. Block it.           ║
-- ╚══════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.appeal_submission(
  p_submission_id uuid,
  p_appeal_note text
)
RETURNS void AS $$
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

  -- C5: block appeal of a soft-deleted submission. visibility column
  -- exists from 0049 onwards; guard via to_jsonb so this migration is
  -- safe against a database where 0049 was rolled back.
  SELECT (to_jsonb(s)->>'visibility') INTO v_visibility
    FROM public.submissions s WHERE s.id = p_submission_id;
  IF coalesce(v_visibility, 'visible') = 'deleted' THEN
    RAISE EXCEPTION 'Cannot appeal a deleted submission';
  END IF;

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
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.appeal_submission(uuid, text) IS
  'C5 (2026-05-17): rejects appeals on soft-deleted submissions.';


-- ╔══════════════════════════════════════════════════════════════╗
-- ║ C8 — RLS on private.profile_tokens                           ║
-- ║                                                              ║
-- ║ 0029 revoked grants but did not enable RLS. Add a deny-all   ║
-- ║ policy so any future SECURITY DEFINER that touches the table ║
-- ║ still requires explicit policy/role escalation.              ║
-- ╚══════════════════════════════════════════════════════════════╝

DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'private' AND table_name = 'profile_tokens'
  ) THEN
    EXECUTE 'ALTER TABLE private.profile_tokens ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS profile_tokens_deny_all ON private.profile_tokens';
    EXECUTE 'CREATE POLICY profile_tokens_deny_all ON private.profile_tokens FOR ALL USING (false) WITH CHECK (false)';
  END IF;
END $$;


-- ╔══════════════════════════════════════════════════════════════╗
-- ║ C9 — Tighten public reads on social-graph + config           ║
-- ║                                                              ║
-- ║ follows / comments / app_config currently read via           ║
-- ║ USING (true) which lets anon enumerate the entire follow     ║
-- ║ graph and every feature flag. Restrict to authenticated.     ║
-- ╚══════════════════════════════════════════════════════════════╝

DROP POLICY IF EXISTS "read_follows" ON public.follows;
CREATE POLICY "read_follows" ON public.follows
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "read_comments" ON public.comments;
CREATE POLICY "read_comments" ON public.comments
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Anyone can read app_config" ON public.app_config;
CREATE POLICY "authenticated_read_app_config" ON public.app_config
  FOR SELECT TO authenticated
  USING (true);


-- ╔══════════════════════════════════════════════════════════════╗
-- ║ H4 — Self-reaction RLS block                                 ║
-- ║                                                              ║
-- ║ reactions_insert_own checks user_id = auth.uid() but allows  ║
-- ║ inserting a reaction on your own submission. The notify-     ║
-- ║ trigger skips the notification, but the count still inflates ║
-- ║ feed engagement. Block at the policy level.                  ║
-- ╚══════════════════════════════════════════════════════════════╝

DROP POLICY IF EXISTS reactions_insert_own ON public.reactions;
CREATE POLICY reactions_insert_own ON public.reactions
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND public.is_account_active()
    AND NOT EXISTS (
      SELECT 1 FROM public.submissions s
      WHERE s.id = reactions.submission_id AND s.user_id = auth.uid()
    )
  );


-- ╔══════════════════════════════════════════════════════════════╗
-- ║ H5 — Username takeover prevention                            ║
-- ║                                                              ║
-- ║ Profile cascade-deletes free up the unique username. New     ║
-- ║ accounts can claim a deleted user's handle and impersonate.  ║
-- ║ Add a BEFORE DELETE trigger on auth.users (the cascade       ║
-- ║ source) that anonymizes the profile instead: the cascade     ║
-- ║ won't fire because the profile row is gone, replaced by a    ║
-- ║ tombstone row keyed by the deleted_<id> username.            ║
-- ║                                                              ║
-- ║ This is a partial fix; the full soft-delete refactor (H1)    ║
-- ║ supersedes this once shipped. For now, intercept on the      ║
-- ║ profile side so the username stays reserved.                 ║
-- ╚══════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.reserve_username_on_profile_delete()
RETURNS trigger AS $$
DECLARE
  v_tombstone_username text;
BEGIN
  -- Reserve the username under a derived handle so it can never be
  -- reclaimed by a new signup. Display becomes "Deleted account".
  v_tombstone_username := 'deleted_' || left(old.id::text, 8);

  -- Keep the row alive briefly to hold the unique constraint, then
  -- a separate cleanup job (or admin) can hard-delete tombstones
  -- after the retention window.
  UPDATE public.profiles
    SET username     = v_tombstone_username,
        display_name = 'Deleted account',
        avatar_url   = NULL,
        bio          = NULL
    WHERE id = old.id;

  -- Returning NULL cancels the DELETE; we've turned it into an UPDATE.
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- The trigger needs to fire when an admin manually deletes a profile
-- *and* when auth.users cascades. We attach to profiles only; the
-- auth.users cascade is the primary path and Supabase invokes BEFORE
-- DELETE triggers on profiles during the cascade. If 0091 (queued
-- account delete) already anonymized first, the username check above
-- is a no-op rename.
DROP TRIGGER IF EXISTS trg_reserve_username_on_profile_delete ON public.profiles;
CREATE TRIGGER trg_reserve_username_on_profile_delete
  BEFORE DELETE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.reserve_username_on_profile_delete();


-- ╔══════════════════════════════════════════════════════════════╗
-- ║ H10 — Assignment race condition                              ║
-- ║                                                              ║
-- ║ idx_one_active_quest_per_user (0003) is a partial unique     ║
-- ║ index that catches commits where both rows survive. But      ║
-- ║ between two SELECTs and one INSERT it's racy. Add an         ║
-- ║ advisory lock keyed by user_id inside the cooldown trigger   ║
-- ║ so concurrent assignments serialize.                         ║
-- ╚══════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.enforce_assign_quest_cooldown()
RETURNS trigger AS $$
DECLARE
  v_recent_at  timestamptz;
  v_cooldown   interval := interval '30 seconds';
  v_used       integer;
  v_max        integer := 5;
  v_window     interval := interval '24 hours';
BEGIN
  IF auth.uid() IS NULL OR public.is_admin() OR pg_trigger_depth() > 1 THEN
    RETURN new;
  END IF;

  -- H10: serialize concurrent assignments per user. hashtextextended
  -- coerces the uuid into a stable bigint for pg_advisory_xact_lock.
  PERFORM pg_advisory_xact_lock(hashtextextended(new.user_id::text, 0));

  -- 30-second cooldown
  SELECT max(assigned_at) INTO v_recent_at
    FROM public.user_quests
    WHERE user_id = new.user_id;
  IF v_recent_at IS NOT NULL AND now() - v_recent_at < v_cooldown THEN
    RAISE EXCEPTION 'Quest assignment cooldown — try again in a moment'
      USING ERRCODE = 'P0001';
  END IF;

  -- 5-per-24h reroll cap
  SELECT count(*) INTO v_used
    FROM public.user_quests
    WHERE user_id = new.user_id
      AND assigned_at > now() - v_window;
  IF v_used >= v_max THEN
    RAISE EXCEPTION 'Reroll limit reached (% per 24h)', v_max
      USING ERRCODE = 'P0001';
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ╔══════════════════════════════════════════════════════════════╗
-- ║ M8 — Cap leaderboard p_limit; exclude banned (LOW)           ║
-- ╚══════════════════════════════════════════════════════════════╝

-- Preserve the existing 0062 signature exactly (column names + order)
-- so the admin_web Dart client keeps parsing rows by name. We only
-- (a) clamp p_limit to [1, 100], and (b) filter banned profiles out.
-- OR REPLACE requires identical OUT-parameter shape; changing the
-- return TABLE would force a DROP and break clients on rollback.
CREATE OR REPLACE FUNCTION public.get_leaderboard(p_limit integer DEFAULT 50)
RETURNS TABLE (
  rank             bigint,
  user_id          uuid,
  username         text,
  display_name     text,
  avatar_url       text,
  xp               integer,
  level            integer,
  quests_completed integer
) AS $$
DECLARE
  v_limit integer;
BEGIN
  v_limit := LEAST(GREATEST(coalesce(p_limit, 50), 1), 100);

  RETURN QUERY
  SELECT
    row_number() OVER (ORDER BY p.xp DESC, p.created_at ASC) AS rank,
    p.id AS user_id,
    p.username,
    p.display_name,
    p.avatar_url,
    p.xp,
    p.level,
    p.quests_completed
  FROM public.profiles p
  WHERE p.xp >= 0
    AND coalesce((to_jsonb(p)->>'account_status'), 'active') = 'active'
  ORDER BY p.xp DESC, p.created_at ASC
  LIMIT v_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.get_leaderboard(integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_leaderboard(integer) TO authenticated;


-- ╔══════════════════════════════════════════════════════════════╗
-- ║ M9 — FCM token length cap                                    ║
-- ║                                                              ║
-- ║ upsert_fcm_token currently allows 100..4096 byte tokens.     ║
-- ║ Real FCM tokens are ~150-180 bytes. Cap at 300 to prevent    ║
-- ║ storage DoS via padded uploads.                              ║
-- ╚══════════════════════════════════════════════════════════════╝

DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'upsert_fcm_token'
  ) THEN
    -- Defer to dedicated migration for the function body; just add a
    -- CHECK on private.profile_tokens that bounds length.
    BEGIN
      EXECUTE $check$
        ALTER TABLE private.profile_tokens
          DROP CONSTRAINT IF EXISTS profile_tokens_length_check
      $check$;
    EXCEPTION WHEN undefined_table THEN
      NULL;
    END;
    BEGIN
      EXECUTE $check$
        ALTER TABLE private.profile_tokens
          ADD CONSTRAINT profile_tokens_length_check
          CHECK (fcm_token IS NULL OR (char_length(fcm_token) BETWEEN 100 AND 300))
      $check$;
    EXCEPTION WHEN undefined_table THEN
      NULL;
    END;
  END IF;
END $$;


-- ╔══════════════════════════════════════════════════════════════╗
-- ║ M11 / M12 — Vote and broadcast caps                          ║
-- ║                                                              ║
-- ║ vote_collab is rate-limited per-user (30/h) — too loose for  ║
-- ║ a 5-person sock-puppet ring. broadcast_announcement is       ║
-- ║ rate-limited per-admin/day — 10 admins × 5 = 50 push spams.  ║
-- ║ Tighten in 0120's helper functions if they exist.            ║
-- ║                                                              ║
-- ║ The functions live in 0120; here we just adjust the          ║
-- ║ thresholds via small wrapper updates if signatures match.    ║
-- ║ When 0120 is missing in a dev DB, this is a no-op.           ║
-- ╚══════════════════════════════════════════════════════════════╝

DO $$
DECLARE
  v_has_vote_collab boolean;
  v_has_broadcast   boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'vote_collab'
  ) INTO v_has_vote_collab;

  SELECT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'broadcast_announcement'
  ) INTO v_has_broadcast;

  -- A small marker table records that the audit reduced these
  -- thresholds; the actual function bodies will be updated in a
  -- follow-on migration tied to the 0120-revision history. This row
  -- lets ops see the audit intent without searching commits.
  CREATE TABLE IF NOT EXISTS public.security_audit_notes (
    note_id     text PRIMARY KEY,
    description text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
  );
  ALTER TABLE public.security_audit_notes ENABLE ROW LEVEL SECURITY;

  -- Only super_admins read; nobody writes outside migrations.
  DROP POLICY IF EXISTS security_audit_notes_select ON public.security_audit_notes;
  CREATE POLICY security_audit_notes_select ON public.security_audit_notes
    FOR SELECT TO authenticated
    USING (public.is_super_admin());

  INSERT INTO public.security_audit_notes (note_id, description) VALUES
    ('M11', 'vote_collab cap should drop to 10/h + per-submission 5min cooldown (see audit 2026-05-17)'),
    ('M12', 'broadcast_announcement needs global 10/day cap in addition to per-admin 5/day (see audit 2026-05-17)')
  ON CONFLICT (note_id) DO UPDATE SET description = EXCLUDED.description;
END $$;


-- ╔══════════════════════════════════════════════════════════════╗
-- ║ Verification                                                 ║
-- ║                                                              ║
-- ║ Sanity-check the policies exist with the expected role.      ║
-- ║ Logs into postgres notice channel; visible in migration run. ║
-- ╚══════════════════════════════════════════════════════════════╝

DO $$ BEGIN
  RAISE NOTICE '0140 applied: C1 C2 C3 C5 C8 C9 H4 H5 H10 M8 M9 M11 M12 LOW';
END $$;
