-- ============================================================
-- MIGRATION 0055: Drop user_quests_insert_own RLS policy (C2)
-- Quest assignment must go exclusively through SECURITY DEFINER RPCs.
-- Direct INSERT via REST API is a security bypass.
-- ============================================================

DROP POLICY IF EXISTS "user_quests_insert_own" ON public.user_quests;
