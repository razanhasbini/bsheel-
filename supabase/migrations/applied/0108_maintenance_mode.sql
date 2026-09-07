-- ============================================================
-- MIGRATION 0108: Maintenance-mode flag
-- Adds two app_config keys that the mobile app watches in realtime
-- to lock every user out of the app behind a maintenance screen.
-- Toggled from the admin web settings page.
-- ============================================================

INSERT INTO public.app_config (key, value)
VALUES ('maintenance_mode', 'false')
ON CONFLICT (key) DO NOTHING;

-- Optional custom message shown on the maintenance screen. Empty =
-- the app uses the default copy.
INSERT INTO public.app_config (key, value)
VALUES ('maintenance_message', '')
ON CONFLICT (key) DO NOTHING;

-- Realtime: ensure app_config is on the supabase_realtime publication
-- so mobile clients get push updates when an admin flips the flag,
-- not just on next cold start.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename  = 'app_config'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.app_config';
  END IF;
END $$;
