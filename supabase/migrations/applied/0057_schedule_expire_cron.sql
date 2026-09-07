-- ============================================================
-- MIGRATION 0057: Schedule pg_cron for expire_overdue_quests (H4)
-- The function exists but was never scheduled.
-- ============================================================

SELECT cron.schedule(
  'expire-overdue-quests',
  '*/5 * * * *',
  $$SELECT public.expire_overdue_quests()$$
);
