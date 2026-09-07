-- ============================================================
-- MIGRATION 0136: Enable Supabase Realtime for the tables that the
-- app's realtime sweep subscribes to.
--
-- Without these on the supabase_realtime publication, every
-- .onPostgresChanges() handler we just added (notifications badge,
-- feed, follows, profiles, leaderboard, saved posts, comments,
-- reactions) silently receives no events.
--
-- Tables already on the publication from earlier migrations:
--   public.submissions    (0082)
--   public.notifications  (0082)
--   public.app_config     (0108)
--
-- Each ADD is wrapped in a guarded DO block so the migration is
-- idempotent — if the dashboard already added the table the block
-- is a no-op rather than an error.
-- ============================================================

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'profiles',
    'follows',
    'reactions',
    'comments',
    'saved_posts',
    'user_quests'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename  = t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END $$;
