-- ============================================================
-- MIGRATION 0061: Revoke public access to admin-only RPCs (L1, L2)
-- expire_overdue_quests, send_quest_timer_warnings, and
-- send_pending_review_reminders should only be callable by service_role.
-- ============================================================

-- L1: expire_overdue_quests — callable by any authenticated user (DoS nuisance)
REVOKE EXECUTE ON FUNCTION public.expire_overdue_quests() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.expire_overdue_quests() TO service_role;

-- L2: send_quest_timer_warnings — should only run via pg_cron
REVOKE EXECUTE ON FUNCTION public.send_quest_timer_warnings() FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.send_quest_timer_warnings() TO service_role;

-- L2: send_pending_review_reminders — should only run via pg_cron
REVOKE EXECUTE ON FUNCTION public.send_pending_review_reminders() FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.send_pending_review_reminders() TO service_role;
