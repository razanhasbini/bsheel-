-- ============================================================
-- MIGRATION 0139: Quest of the Day (QOTD)
--
-- A single, hand-picked quest per UTC day surfaced as a "ticket" at
-- the top of the home page. Admins can stack future entries in
-- advance — uniqueness on `display_date` means only one ticket per
-- day, and the read RPC always picks today's row.
--
-- Read paths:
--   * mobile  → `get_quest_of_the_day()` RPC (SECURITY DEFINER)
--   * admin   → direct SELECT on `quest_of_the_day` (RLS-gated)
-- Write paths:
--   * admin   → direct UPSERT on `quest_of_the_day` (RLS = admin only)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.quest_of_the_day (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  display_date date        NOT NULL UNIQUE,
  quest_id     uuid        NOT NULL REFERENCES public.quests(id) ON DELETE CASCADE,
  ticket_no    text,       -- optional override; UI falls back to date-derived number
  bonus_xp     integer     NOT NULL DEFAULT 0 CHECK (bonus_xp >= 0),
  note         text,       -- optional admin-only memo (not shown to users)
  created_by   uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_qotd_display_date
  ON public.quest_of_the_day (display_date DESC);

COMMENT ON TABLE public.quest_of_the_day IS
  'Admin-curated Quest-of-the-Day picks. One row per UTC day, surfaced via get_quest_of_the_day().';
COMMENT ON COLUMN public.quest_of_the_day.ticket_no IS
  'Optional vanity ticket number shown in the UI. Defaults derived client-side from display_date when null.';
COMMENT ON COLUMN public.quest_of_the_day.bonus_xp IS
  'Extra XP awarded on top of the quest base reward when the user completes this QOTD on its display_date. Currently informational; the assign/award path can opt in later.';

-- ─── RLS ─────────────────────────────────────────────────────
ALTER TABLE public.quest_of_the_day ENABLE ROW LEVEL SECURITY;

-- Every authenticated user can read so the home page ticket loads.
DROP POLICY IF EXISTS "qotd readable by authenticated" ON public.quest_of_the_day;
CREATE POLICY "qotd readable by authenticated"
  ON public.quest_of_the_day
  FOR SELECT
  USING (auth.role() = 'authenticated');

-- Only admins can write.
DROP POLICY IF EXISTS "qotd writable by admins" ON public.quest_of_the_day;
CREATE POLICY "qotd writable by admins"
  ON public.quest_of_the_day
  FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()));

-- ─── updated_at touch trigger ───────────────────────────────
CREATE OR REPLACE FUNCTION public.touch_quest_of_the_day_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_quest_of_the_day_updated_at
  ON public.quest_of_the_day;
CREATE TRIGGER trg_quest_of_the_day_updated_at
  BEFORE UPDATE ON public.quest_of_the_day
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_quest_of_the_day_updated_at();

-- ─── Read RPC ───────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.get_quest_of_the_day();

CREATE OR REPLACE FUNCTION public.get_quest_of_the_day()
RETURNS TABLE (
  id                   uuid,
  display_date         date,
  ticket_no            text,
  bonus_xp             integer,
  quest_id             uuid,
  quest_title          text,
  quest_description    text,
  quest_category       text,
  quest_difficulty     text,
  quest_xp_reward      integer,
  quest_duration_hours integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    qotd.id,
    qotd.display_date,
    qotd.ticket_no,
    qotd.bonus_xp,
    q.id,
    q.title,
    q.description,
    q.category,
    q.difficulty,
    q.xp_reward,
    q.duration_hours
  FROM public.quest_of_the_day qotd
  JOIN public.quests q ON q.id = qotd.quest_id
  WHERE qotd.display_date = (now() AT TIME ZONE 'UTC')::date
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_quest_of_the_day() TO authenticated;

COMMENT ON FUNCTION public.get_quest_of_the_day() IS
  'Returns the QOTD row for today (UTC) joined with quest details. NULL result if no entry has been queued.';
