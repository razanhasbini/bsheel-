-- ============================================================
-- MIGRATION 0109: Quest injection isolation
--
-- Goals:
--   1. An injected quest must NEVER leak to any other user — not
--      via assign_random_quest, not via the picker. Even after
--      the target user picks or skips it, the quest stays out of
--      everyone else's pool.
--   2. The injection pops up on the target user's *first* press
--      of "generate" after the inject. After that first show,
--      it does not appear again — for anyone, including them.
--
-- Changes:
--   * assign_random_quest: drop the `consumed_at IS NULL` clause
--     so an injected quest is excluded from the random pool
--     forever, regardless of consumption state.
--   * assign_specific_quest: defensively consume any matching
--     injection when the target user picks the quest directly.
--   * NEW get_quest_picker_options(p_count): returns up to N
--     quests for the calling user's roll-the-wheel sheet. If a
--     pending injection exists, it is pinned at index 0 and
--     marked consumed at the same time. The remaining slots are
--     random active quests with all injection-tied quests
--     filtered out (regardless of consumption). Already
--     submitted/approved quests for the user are also excluded.
-- ============================================================

-- ── 1. assign_random_quest: hard-exclude all injection-tied quests ──
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
          AND uq.status IN ('submitted', 'approved')
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.admin_quest_injections i
        WHERE i.quest_id = q.id
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

-- ── 2. assign_specific_quest: defensively consume matching injection ──
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

  -- If this quest was injected for this user, mark the injection
  -- consumed so it never resurfaces and the row is auditable.
  UPDATE public.admin_quest_injections
    SET consumed_at = now()
    WHERE target_user_id = p_user_id
      AND quest_id = p_quest_id
      AND consumed_at IS NULL;

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

-- ── 3. get_quest_picker_options: roll-the-wheel options for caller ──
-- Returns up to p_count quests. If the caller has a pending
-- admin injection, that quest is the first row and is marked
-- consumed by this call (so subsequent presses of generate do
-- NOT re-show it — fulfilling "first time only"). Remaining
-- slots are random active quests excluding (a) any quest tied
-- to any injection record, consumed or not, so they never leak
-- to other users, and (b) quests the caller already submitted
-- or approved.
CREATE OR REPLACE FUNCTION public.get_quest_picker_options(p_count integer DEFAULT 3)
RETURNS SETOF public.quests AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_injection_quest_id uuid;
  v_remaining integer;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF p_count IS NULL OR p_count < 1 THEN
    p_count := 3;
  END IF;

  -- Pop the oldest pending injection (if any) and mark it consumed.
  WITH popped AS (
    UPDATE public.admin_quest_injections
       SET consumed_at = now()
     WHERE id = (
       SELECT id
         FROM public.admin_quest_injections
        WHERE target_user_id = v_user_id
          AND consumed_at IS NULL
        ORDER BY created_at ASC
        LIMIT 1
     )
     RETURNING quest_id
  )
  SELECT quest_id INTO v_injection_quest_id FROM popped;

  IF v_injection_quest_id IS NOT NULL THEN
    RETURN QUERY
      SELECT q.*
        FROM public.quests q
       WHERE q.id = v_injection_quest_id
         AND q.is_active = true;
  END IF;

  v_remaining := p_count - (CASE WHEN v_injection_quest_id IS NULL THEN 0 ELSE 1 END);

  IF v_remaining > 0 THEN
    RETURN QUERY
      SELECT q.*
        FROM public.quests q
       WHERE q.is_active = true
         AND (v_injection_quest_id IS NULL OR q.id <> v_injection_quest_id)
         AND NOT EXISTS (
           SELECT 1
             FROM public.admin_quest_injections i
            WHERE i.quest_id = q.id
         )
         AND NOT EXISTS (
           SELECT 1
             FROM public.user_quests uq
            WHERE uq.user_id = v_user_id
              AND uq.quest_id = q.id
              AND uq.status IN ('submitted', 'approved')
         )
       ORDER BY random()
       LIMIT v_remaining;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_quest_picker_options(integer) TO authenticated;
