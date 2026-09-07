-- Fix: submitted quests should NOT block new quest generation.
-- Only 'assigned' quests block (quest in progress, no proof yet).
-- 'submitted' means proof uploaded, waiting for review — user can take new quest.

CREATE OR REPLACE FUNCTION public.assign_random_quest(p_user_id uuid)
RETURNS public.user_quests AS $$
DECLARE
  v_quest_id uuid;
  v_result public.user_quests;
BEGIN
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

  SELECT id INTO v_quest_id
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

  INSERT INTO public.user_quests (user_id, quest_id)
  VALUES (p_user_id, v_quest_id)
  RETURNING * INTO v_result;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  VALUES (p_user_id, 'New Quest!', 'You have a new quest! Complete it within 4 hours.', 'quest_assigned', v_result.id::text);

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.assign_specific_quest(p_user_id uuid, p_quest_id uuid)
RETURNS public.user_quests AS $$
DECLARE
  v_result public.user_quests;
BEGIN
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

  IF NOT EXISTS (
    SELECT 1 FROM public.quests
    WHERE id = p_quest_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Quest not found or inactive';
  END IF;

  INSERT INTO public.user_quests (user_id, quest_id)
  VALUES (p_user_id, p_quest_id)
  RETURNING * INTO v_result;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  VALUES (p_user_id, 'New Quest!', 'You have a new quest! Complete it within 4 hours.', 'quest_assigned', v_result.id::text);

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
