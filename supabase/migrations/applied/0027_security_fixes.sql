-- ============================================================
-- MIGRATION 0025: Security Fixes
-- Adds auth.uid() checks to RPC functions and restricts
-- notification insert policy to safe client-side types only.
-- ============================================================

-- 1. Replace assign_random_quest with auth check + duration_hours logic from 0025
CREATE OR REPLACE FUNCTION public.assign_random_quest(p_user_id uuid)
RETURNS public.user_quests AS $$
DECLARE
  v_quest_id uuid;
  v_duration_hours integer;
  v_result public.user_quests;
BEGIN
  -- Security: only the user themselves can assign a quest to their account
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Expire overdue assigned quests
  UPDATE public.user_quests
    SET status = 'expired'
    WHERE user_id = p_user_id
      AND status = 'assigned'
      AND expires_at IS NOT NULL
      AND expires_at < now();

  -- Only block if there's an assigned (in-progress) quest
  IF EXISTS (
    SELECT 1 FROM public.user_quests
    WHERE user_id = p_user_id AND status = 'assigned'
  ) THEN
    RAISE EXCEPTION 'User already has an active quest';
  END IF;

  SELECT id, coalesce(duration_hours, 4)
    INTO v_quest_id, v_duration_hours
    FROM public.quests
    WHERE is_active = true
      AND id NOT IN (
        SELECT quest_id FROM public.user_quests
        WHERE user_id = p_user_id
          AND status = 'approved'
          AND completed_at > now() - interval '7 days'
      )
    ORDER BY random()
    LIMIT 1;

  IF v_quest_id IS NULL THEN
    RAISE EXCEPTION 'No available quests';
  END IF;

  INSERT INTO public.user_quests (user_id, quest_id, expires_at)
  VALUES (
    p_user_id,
    v_quest_id,
    now() + make_interval(hours => v_duration_hours)
  )
  RETURNING * INTO v_result;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  VALUES (
    p_user_id,
    'New Quest!',
    format(
      'You have a new quest! Complete it within %s.',
      CASE
        WHEN v_duration_hours = 1 THEN '1 hour'
        ELSE v_duration_hours::text || ' hours'
      END
    ),
    'quest_assigned',
    v_result.id::text
  );

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Replace assign_specific_quest with auth check + duration_hours logic from 0025
CREATE OR REPLACE FUNCTION public.assign_specific_quest(p_user_id uuid, p_quest_id uuid)
RETURNS public.user_quests AS $$
DECLARE
  v_duration_hours integer;
  v_result public.user_quests;
BEGIN
  -- Security: only the user themselves can assign a quest to their account
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  UPDATE public.user_quests
    SET status = 'expired'
    WHERE user_id = p_user_id
      AND status = 'assigned'
      AND expires_at IS NOT NULL
      AND expires_at < now();

  -- Only block if there's an assigned (in-progress) quest
  IF EXISTS (
    SELECT 1 FROM public.user_quests
    WHERE user_id = p_user_id AND status = 'assigned'
  ) THEN
    RAISE EXCEPTION 'User already has an active quest';
  END IF;

  SELECT coalesce(duration_hours, 4)
    INTO v_duration_hours
    FROM public.quests
    WHERE id = p_quest_id AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Quest not found or inactive';
  END IF;

  INSERT INTO public.user_quests (user_id, quest_id, expires_at)
  VALUES (
    p_user_id,
    p_quest_id,
    now() + make_interval(hours => v_duration_hours)
  )
  RETURNING * INTO v_result;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  VALUES (
    p_user_id,
    'New Quest!',
    format(
      'You have a new quest! Complete it within %s.',
      CASE
        WHEN v_duration_hours = 1 THEN '1 hour'
        ELSE v_duration_hours::text || ' hours'
      END
    ),
    'quest_assigned',
    v_result.id::text
  );

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Replace increment_xp with auth check and stale-XP fix
CREATE OR REPLACE FUNCTION public.increment_xp(p_user_id uuid, p_amount integer)
RETURNS void AS $$
DECLARE
  v_old_xp integer;
  v_new_xp integer;
  v_old_level integer;
  v_new_level integer;
BEGIN
  -- Security: only the user themselves can increment their own XP
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Capture old XP before the UPDATE to avoid reading stale values post-UPDATE
  SELECT xp INTO v_old_xp FROM public.profiles WHERE id = p_user_id;
  v_new_xp := v_old_xp + p_amount;
  v_old_level := greatest(1, v_old_xp / 100 + 1);
  v_new_level := greatest(1, v_new_xp / 100 + 1);

  UPDATE public.profiles
    SET xp = v_new_xp,
        level = v_new_level
    WHERE id = p_user_id;

  -- Check for level up notification
  IF v_new_level > v_old_level THEN
    INSERT INTO public.notifications (user_id, title, body, type)
    VALUES (
      p_user_id,
      'Level Up!',
      'You reached level ' || v_new_level || '!',
      'level_up'
    );
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Replace expire_overdue_quests with authentication requirement
CREATE OR REPLACE FUNCTION public.expire_overdue_quests()
RETURNS void AS $$
BEGIN
  -- Security: require authentication (any authenticated user can trigger cleanup)
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  UPDATE public.user_quests
    SET status = 'expired'
    WHERE status = 'assigned'
      AND expires_at < now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Drop the overly permissive notification insert policy and replace
--    with a restricted version that only allows safe client-side types.
DROP POLICY IF EXISTS "authenticated_users_can_notify" ON public.notifications;

CREATE POLICY "authenticated_users_can_notify_limited"
  ON public.notifications
  FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND type IN ('reaction_received', 'new_follower', 'new_comment')
  );

-- 6. Admin notification insert policy (admins can insert any notification type)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'notifications'
      AND policyname = 'admins_can_insert_any_notification'
  ) THEN
    CREATE POLICY "admins_can_insert_any_notification"
      ON public.notifications
      FOR INSERT
      WITH CHECK (
        EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid())
      );
  END IF;
END
$$;

-- 7. FCM token visibility: Known issue. The fcm_token column on profiles
--    is exposed via the profiles_select_all policy (SELECT using true).
--    A proper fix requires either a separate fcm_tokens table or app-level
--    column filtering, both of which need coordinated app code changes.
--    Tracked for a future migration.
