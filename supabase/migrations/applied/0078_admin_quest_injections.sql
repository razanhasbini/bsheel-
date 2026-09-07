-- ============================================================
-- MIGRATION 0078: Admin quest injections
-- Lets an admin write a private custom quest and inject it
-- for a specific user. On their next generate, the injected
-- quest is offered as one of the three options. It is consumed
-- the moment the user actually picks it.
--
-- Design:
--   * quests row is real (is_active = true) but excluded from
--     the random pool for all users via assign_random_quest().
--   * admin_quest_injections ties the quest to its target user
--     and carries a consumed_at marker.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.admin_quest_injections (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_user_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  quest_id        uuid NOT NULL REFERENCES public.quests(id) ON DELETE CASCADE,
  created_by      uuid NOT NULL REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  consumed_at     timestamptz
);

CREATE INDEX IF NOT EXISTS admin_quest_injections_target_pending_idx
  ON public.admin_quest_injections (target_user_id)
  WHERE consumed_at IS NULL;

CREATE INDEX IF NOT EXISTS admin_quest_injections_quest_pending_idx
  ON public.admin_quest_injections (quest_id)
  WHERE consumed_at IS NULL;

ALTER TABLE public.admin_quest_injections ENABLE ROW LEVEL SECURITY;

-- Owners can read their own pending injection (for mobile client lookup).
DROP POLICY IF EXISTS admin_quest_injections_self_read ON public.admin_quest_injections;
CREATE POLICY admin_quest_injections_self_read
  ON public.admin_quest_injections
  FOR SELECT
  USING (target_user_id = auth.uid());

-- Admins can manage all rows.
DROP POLICY IF EXISTS admin_quest_injections_admin_all ON public.admin_quest_injections;
CREATE POLICY admin_quest_injections_admin_all
  ON public.admin_quest_injections
  FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admins a WHERE a.user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.admins a WHERE a.user_id = auth.uid()));

-- ============================================================
-- assign_random_quest: exclude quests that are the subject of
-- any pending (unconsumed) injection so they do not leak into
-- the public random pool.
-- ============================================================

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
          AND i.consumed_at IS NULL
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

-- ============================================================
-- inject_quest_for_user: admin-only. Creates a quest row and a
-- matching admin_quest_injections row in one transaction.
-- Returns the created quest row.
-- ============================================================
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
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admins WHERE user_id = v_admin_id) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  INSERT INTO public.quests (
    title, description, category, difficulty,
    xp_reward, duration_hours, is_active, created_by
  )
  VALUES (
    p_title, p_description, p_category, p_difficulty,
    p_xp_reward, p_duration_hours, true, v_admin_id
  )
  RETURNING * INTO v_quest;

  INSERT INTO public.admin_quest_injections (
    target_user_id, quest_id, created_by
  )
  VALUES (p_target_user_id, v_quest.id, v_admin_id);

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  VALUES (
    p_target_user_id,
    'A quest awaits',
    'An admin has prepared a special quest just for you.',
    'quest_assigned',
    v_quest.id::text
  );

  RETURN v_quest;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- get_pending_injection: returns the oldest pending quest row
-- for the calling user, or nothing if none exists.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_pending_injection()
RETURNS public.quests AS $$
DECLARE
  v_quest public.quests;
BEGIN
  SELECT q.*
    INTO v_quest
    FROM public.admin_quest_injections i
    JOIN public.quests q ON q.id = i.quest_id
    WHERE i.target_user_id = auth.uid()
      AND i.consumed_at IS NULL
    ORDER BY i.created_at ASC
    LIMIT 1;

  RETURN v_quest;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ============================================================
-- consume_injection: marks any pending injection of the given
-- quest for the calling user as consumed. Idempotent.
-- ============================================================
CREATE OR REPLACE FUNCTION public.consume_injection(p_quest_id uuid)
RETURNS void AS $$
BEGIN
  UPDATE public.admin_quest_injections
    SET consumed_at = now()
    WHERE target_user_id = auth.uid()
      AND quest_id = p_quest_id
      AND consumed_at IS NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- admin_send_notification: admin-only. Inserts a row into
-- public.notifications for the target user. Used by the admin
-- panel "Inject notification" form.
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_send_notification(
  p_target_user_id uuid,
  p_title text,
  p_body text,
  p_type text DEFAULT 'announcement'
)
RETURNS public.notifications AS $$
DECLARE
  v_row public.notifications;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type)
  VALUES (p_target_user_id, p_title, p_body, p_type)
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
