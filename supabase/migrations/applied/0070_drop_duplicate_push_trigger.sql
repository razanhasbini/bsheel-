-- ============================================================
-- MIGRATION 0070: Drop duplicate push notification trigger
-- Two triggers were firing on notification INSERT:
--   1. push_on_notification_insert (Supabase Database Webhook)
--   2. on_notification_send_push (pg_net via migration 0050)
-- Both called the same edge function, causing double pushes.
-- Keep the pg_net version (reads service key from vault).
-- ============================================================

DROP TRIGGER IF EXISTS push_on_notification_insert ON public.notifications;
