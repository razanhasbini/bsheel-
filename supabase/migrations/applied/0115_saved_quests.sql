-- ============================================================
-- MIGRATION 0115: saved_quests — user wishlist of quests they've
--                 BSHEEEL'd from search / discover. Mirrors the
--                 saved_posts table from 0086.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.saved_quests (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  quest_id    uuid        NOT NULL REFERENCES public.quests(id)   ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, quest_id)
);

CREATE INDEX IF NOT EXISTS saved_quests_user_idx
  ON public.saved_quests (user_id, created_at DESC);

ALTER TABLE public.saved_quests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "saved_quests_select_own" ON public.saved_quests;
CREATE POLICY "saved_quests_select_own"
  ON public.saved_quests FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "saved_quests_insert_own" ON public.saved_quests;
CREATE POLICY "saved_quests_insert_own"
  ON public.saved_quests FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "saved_quests_delete_own" ON public.saved_quests;
CREATE POLICY "saved_quests_delete_own"
  ON public.saved_quests FOR DELETE
  USING (auth.uid() = user_id);

COMMENT ON TABLE public.saved_quests IS
  'Per-user quest wishlist. One row per (user, quest). Created when the user taps the BSHEEEL button on a quest tile in search/discover.';
