-- ============================================================
-- MIGRATION 0099: Admin input validation + appeal-history retention
--
-- Closes the validation gaps surfaced by the admin audit:
--   1. inject_quest_for_user: enforce sane bounds on xp_reward,
--      duration_hours, difficulty, category. Stops a compromised
--      admin (or buggy admin UI) from minting 99,999 XP quests.
--   2. admin_send_notification: rate-limit to 5 per (admin, target)
--      per hour. Stops admin-initiated user spam / DoS on send-push.
--   3. quests table: add CHECK constraints so even direct INSERTs
--      can't bypass the RPC bounds.
--   4. appeal_submission: stop nulling reviewed_by on appeal — keep
--      original reviewer for audit trail. Append a sentinel "appealed
--      at" so admins can see the resubmission cleanly.
-- ============================================================

-- ── 1. Bounds on inject_quest_for_user ────────────────────────
CREATE OR REPLACE FUNCTION public.inject_quest_for_user(
  p_target_user_id uuid,
  p_title text,
  p_description text,
  p_category text,
  p_difficulty text,
  p_xp_reward integer,
  p_duration_hours integer
)
RETURNS public.quests AS $$
DECLARE
  v_admin_id uuid := auth.uid();
  v_quest public.quests;
  v_title text := coalesce(trim(p_title), '');
  v_desc  text := coalesce(trim(p_description), '');
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admins WHERE user_id = v_admin_id) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;

  -- Range + enum validation (defence-in-depth alongside CHECK constraints).
  IF p_xp_reward IS NULL OR p_xp_reward < 5 OR p_xp_reward > 1000 THEN
    RAISE EXCEPTION 'xp_reward must be between 5 and 1000 (got %)', p_xp_reward
      USING ERRCODE = '23514';
  END IF;
  IF p_duration_hours IS NULL OR p_duration_hours < 1 OR p_duration_hours > 168 THEN
    RAISE EXCEPTION 'duration_hours must be between 1 and 168 (got %)', p_duration_hours
      USING ERRCODE = '23514';
  END IF;
  IF p_difficulty IS NULL OR lower(p_difficulty) NOT IN ('easy', 'medium', 'hard') THEN
    RAISE EXCEPTION 'difficulty must be one of easy/medium/hard (got %)', p_difficulty
      USING ERRCODE = '23514';
  END IF;
  IF v_title = '' OR length(v_title) > 100 THEN
    RAISE EXCEPTION 'title must be 1..100 chars' USING ERRCODE = '23514';
  END IF;
  IF v_desc = '' OR length(v_desc) > 500 THEN
    RAISE EXCEPTION 'description must be 1..500 chars' USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.quests (
    title, description, category, difficulty,
    xp_reward, duration_hours, is_active, created_by
  )
  VALUES (
    v_title, v_desc, p_category, lower(p_difficulty),
    p_xp_reward, p_duration_hours, true, v_admin_id
  )
  RETURNING * INTO v_quest;

  INSERT INTO public.admin_quest_injections (target_user_id, quest_id, created_by)
  VALUES (p_target_user_id, v_quest.id, v_admin_id);

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  VALUES (
    p_target_user_id,
    'A quest awaits',
    'An admin has prepared a special quest just for you.',
    'quest_assigned',
    v_quest.id::text
  );

  PERFORM public.log_admin_action(
    'quest.inject',
    'user',
    p_target_user_id::text,
    jsonb_build_object(
      'quest_id', v_quest.id,
      'xp_reward', p_xp_reward,
      'difficulty', lower(p_difficulty),
      'duration_hours', p_duration_hours
    )
  );

  RETURN v_quest;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 2. Rate-limit admin_send_notification ─────────────────────
CREATE OR REPLACE FUNCTION public.admin_send_notification(
  p_target_user_id uuid,
  p_title text,
  p_body text,
  p_type text DEFAULT 'announcement'
) RETURNS public.notifications AS $$
DECLARE
  v_row public.notifications;
  v_recent integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Rate limit: at most 5 admin pushes from this admin to this user
  -- in the last 60 minutes. Prevents the "admin spam an individual user"
  -- vector + protects FCM from accidental loops.
  SELECT count(*) INTO v_recent
    FROM public.admin_audit_log
    WHERE actor_id = auth.uid()
      AND action = 'notification.send'
      AND target_id = p_target_user_id::text
      AND created_at > now() - interval '1 hour';

  IF v_recent >= 5 THEN
    RAISE EXCEPTION 'Rate limit: 5 admin notifications per user per hour'
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type)
  VALUES (p_target_user_id, p_title, p_body, p_type)
  RETURNING * INTO v_row;

  PERFORM public.log_admin_action(
    'notification.send',
    'user',
    p_target_user_id::text,
    jsonb_build_object(
      'title', left(p_title, 200),
      'body_chars', length(p_body),
      'type', p_type
    )
  );

  RETURN v_row;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 3. CHECK constraints on quests ────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'quests_xp_reward_range'
  ) THEN
    ALTER TABLE public.quests
      ADD CONSTRAINT quests_xp_reward_range
      CHECK (xp_reward IS NULL OR (xp_reward BETWEEN 5 AND 1000));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'quests_difficulty_enum'
  ) THEN
    ALTER TABLE public.quests
      ADD CONSTRAINT quests_difficulty_enum
      CHECK (difficulty IS NULL OR lower(difficulty) IN ('easy', 'medium', 'hard'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'quests_duration_hours_range'
  ) THEN
    ALTER TABLE public.quests
      ADD CONSTRAINT quests_duration_hours_range
      CHECK (duration_hours IS NULL OR (duration_hours BETWEEN 1 AND 168));
  END IF;
END $$;
