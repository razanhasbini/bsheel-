-- ============================================================
-- MIGRATION 0119: Prefer admin-created quests in user picker
--
-- Problem:
--   The picker was technically reading from public.quests, but pure
--   ORDER BY random() buried new admin-created quests under the older
--   seed pool. With many seed rows and few new rows, users could roll
--   repeatedly and mostly see the original filler quests.
--
-- Behavior:
--   * Targeted injections still surface first, only for the target user.
--   * Injection-tied quests still never leak to other users.
--   * Normal active admin-created quests are intentionally favored in
--     picker options and random assignment.
--   * Remaining slots are filled from the rest of the active pool.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_quest_picker_options(p_count integer DEFAULT 3)
RETURNS SETOF public.quests AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_injection_quest_id uuid;
  v_remaining integer;
  v_admin_slots integer;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF p_count IS NULL OR p_count < 1 THEN
    p_count := 3;
  END IF;

  -- Pop the oldest pending targeted injection, if any. This keeps
  -- injected quests private to the target and first in their next roll.
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
  IF v_remaining <= 0 THEN
    RETURN;
  END IF;

  -- Reserve about half the non-injection slots for recent admin-created
  -- quests. For the normal 3-card picker, this means up to 2 newer admin
  -- quests plus 1 broader random quest.
  v_admin_slots := GREATEST(1, CEIL(v_remaining / 2.0)::integer);

  RETURN QUERY
  WITH eligible AS (
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
  ),
  preferred_admin AS (
    SELECT e.*
      FROM eligible e
     WHERE e.created_by IS NOT NULL
     ORDER BY e.created_at DESC, random()
     LIMIT v_admin_slots
  ),
  filler AS (
    SELECT e.*
      FROM eligible e
     WHERE NOT EXISTS (
       SELECT 1 FROM preferred_admin p WHERE p.id = e.id
     )
     ORDER BY random()
     LIMIT GREATEST(0, v_remaining - (SELECT COUNT(*)::integer FROM preferred_admin))
  )
  SELECT * FROM preferred_admin
  UNION ALL
  SELECT * FROM filler;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_quest_picker_options(integer) TO authenticated;

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
    ORDER BY
      CASE
        WHEN q.created_by IS NOT NULL THEN random() * 0.35
        ELSE 0.35 + random() * 0.65
      END,
      q.created_at DESC
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
