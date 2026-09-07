-- ============================================================
-- MIGRATION 0059: Fix submissions_insert_own ownership check (M1)
-- Validates that the user_quest_id belongs to the caller.
-- ============================================================

DROP POLICY IF EXISTS "submissions_insert_own" ON public.submissions;

CREATE POLICY "submissions_insert_own" ON public.submissions
  FOR INSERT WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.user_quests
      WHERE id = user_quest_id
        AND user_id = auth.uid()
    )
  );
