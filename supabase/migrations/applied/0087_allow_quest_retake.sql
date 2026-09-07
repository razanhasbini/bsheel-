-- ============================================================
-- MIGRATION 0087: Allow retaking previously approved quests
--
-- Changes:
-- 1. Modify assign_specific_quest to ALLOW retaking approved quests
--    (removes the "Quest already completed by user" block)
-- 2. Add is_retake column to detect retakes in admin review
-- ============================================================

-- ── 1. Recreate assign_specific_quest: allow retakes ───────────────
CREATE OR REPLACE FUNCTION public.assign_specific_quest(p_user_id uuid, p_quest_id uuid)
RETURNS public.user_quests AS $$
DECLARE
  v_duration_hours integer;
  v_result public.user_quests;
BEGIN
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Auto-expire any overdue assigned quests
  UPDATE public.user_quests
    SET status = 'expired'
    WHERE user_id = p_user_id
      AND status = 'assigned'
      AND expires_at IS NOT NULL
      AND expires_at < now();

  -- Block if user already has an active (assigned) quest
  IF EXISTS (
    SELECT 1
    FROM public.user_quests
    WHERE user_id = p_user_id
      AND status = 'assigned'
  ) THEN
    RAISE EXCEPTION 'User already has an active quest';
  END IF;

  -- NOTE: We no longer block retaking approved quests.
  -- Users can redo quests they've already completed.

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

-- ── 2. Helper: check if a submission is a retake ───────────────────
-- Returns true if the user has previously completed (approved) the
-- same quest. Used by admin review to flag retakes.
CREATE OR REPLACE FUNCTION public.is_quest_retake(p_submission_id uuid)
RETURNS boolean AS $$
DECLARE
  v_user_id uuid;
  v_quest_id uuid;
BEGIN
  SELECT uq.user_id, uq.quest_id
    INTO v_user_id, v_quest_id
    FROM public.submissions s
    JOIN public.user_quests uq ON uq.id = s.user_quest_id
    WHERE s.id = p_submission_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.user_quests uq2
    WHERE uq2.user_id = v_user_id
      AND uq2.quest_id = v_quest_id
      AND uq2.status = 'approved'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
