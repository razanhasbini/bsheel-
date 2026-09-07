-- Migration 0046: Fix assign_specific_quest to not block quests with 'submitted' status.
-- Only 'approved' quests should prevent reassignment (no re-doing completed quests).
-- 'submitted' = proof uploaded, pending review — user might get rejected and want to retry,
-- or this is a different quest entirely that shouldn't be blocked.
-- Also update assign_random_quest to match.

CREATE OR REPLACE FUNCTION public.assign_specific_quest(p_user_id uuid, p_quest_id uuid)
RETURNS public.user_quests AS $$
DECLARE
  v_duration_hours integer;
  v_result public.user_quests;
BEGIN
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  UPDATE public.user_quests
    SET status = 'expired'
    WHERE user_id = p_user_id
      AND status = 'assigned'
      AND expires_at IS NOT NULL
      AND expires_at < now();

  IF EXISTS (
    SELECT 1
    FROM public.user_quests
    WHERE user_id = p_user_id
      AND status = 'assigned'
  ) THEN
    RAISE EXCEPTION 'User already has an active quest';
  END IF;

  -- Only block approved quests (completed). Submitted quests can be retried if rejected.
  IF EXISTS (
    SELECT 1
    FROM public.user_quests
    WHERE user_id = p_user_id
      AND quest_id = p_quest_id
      AND status = 'approved'
  ) THEN
    RAISE EXCEPTION 'Quest already completed by user';
  END IF;

  SELECT COALESCE(duration_hours, 4)
    INTO v_duration_hours
    FROM public.quests
    WHERE id = p_quest_id
      AND is_active = true;

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

-- Also update assign_random_quest to only exclude approved quests from the pool
CREATE OR REPLACE FUNCTION public.assign_random_quest(p_user_id uuid)
RETURNS public.user_quests AS $$
DECLARE
  v_quest_id uuid;
  v_duration_hours integer;
  v_result public.user_quests;
BEGIN
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  UPDATE public.user_quests
    SET status = 'expired'
    WHERE user_id = p_user_id
      AND status = 'assigned'
      AND expires_at IS NOT NULL
      AND expires_at < now();

  IF EXISTS (
    SELECT 1
    FROM public.user_quests
    WHERE user_id = p_user_id
      AND status = 'assigned'
  ) THEN
    RAISE EXCEPTION 'User already has an active quest';
  END IF;

  SELECT q.id, COALESCE(q.duration_hours, 4)
    INTO v_quest_id, v_duration_hours
    FROM public.quests q
    WHERE q.is_active = true
      AND NOT EXISTS (
        SELECT 1
        FROM public.user_quests uq
        WHERE uq.user_id = p_user_id
          AND uq.quest_id = q.id
          AND uq.status = 'approved'
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
