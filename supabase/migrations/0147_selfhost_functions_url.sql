-- ============================================================
-- MIGRATION 0147: Point functions URL at the self-hosted server.
--
-- The backend moved from Supabase cloud
-- (dwbopjjvgepfnclrulvr.supabase.co) to the self-hosted stack at
-- api.bsheel.app. 0130 made the cron/trigger callers read
-- `project_functions_url` from public.app_config, but both the seeded
-- row and the helper's hardcoded fallback still referenced the old
-- cloud project — so a fresh clone (or a config wipe) would silently
-- POST pushes, the Telegram daily summary, and the account-deletion
-- drain to the dead cloud instance.
--
-- This overwrites the config row and re-issues the helper so the
-- fallback also lands on the self-hosted domain.
-- ============================================================

INSERT INTO public.app_config (key, value)
VALUES ('project_functions_url', 'https://api.bsheel.app/functions/v1')
ON CONFLICT (key)
DO UPDATE SET value = EXCLUDED.value;

CREATE OR REPLACE FUNCTION public.project_functions_url()
RETURNS text AS $$
  SELECT coalesce(
    (SELECT value FROM public.app_config WHERE key = 'project_functions_url'),
    'https://api.bsheel.app/functions/v1'
  );
$$ LANGUAGE sql STABLE;

REVOKE EXECUTE ON FUNCTION public.project_functions_url() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.project_functions_url() TO authenticated, service_role;
