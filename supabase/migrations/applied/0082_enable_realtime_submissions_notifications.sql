-- ============================================================
-- MIGRATION 0082: Enable Supabase Realtime for submissions and
-- notifications tables.
--
-- Without this, .onPostgresChanges() subscriptions silently
-- receive no events because the tables are not in the
-- supabase_realtime publication.
-- ============================================================

ALTER PUBLICATION supabase_realtime ADD TABLE public.submissions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
