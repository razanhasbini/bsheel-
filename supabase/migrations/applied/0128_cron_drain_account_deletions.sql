-- ============================================================
-- MIGRATION 0128: pg_cron job to drain the account-deletion queue
-- (SEC-005 follow-up).
--
-- 0122 added public.account_delete_requests, but rows just sit there
-- unless something calls admin_manage_user with action='process_account_deletions'.
-- This schedules an hourly drain via pg_cron + pg_net.
--
-- The wrapper function reads the service-role key + project URL the
-- same way 0050 / 0107 already do (Vault). Falls open with a WARNING
-- if either is missing so a misconfigured environment doesn't break.
-- ============================================================

CREATE OR REPLACE FUNCTION public.drain_account_deletion_queue()
RETURNS void AS $$
DECLARE
  v_service_key text;
  v_project_url text;
BEGIN
  SELECT decrypted_secret INTO v_service_key
    FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  IF v_service_key IS NULL OR v_service_key = '' THEN
    RAISE WARNING 'drain_account_deletion_queue: service_role_key not in vault, skipping';
    RETURN;
  END IF;

  -- Fetch the project URL from app_config (set by 0130, with safe default).
  SELECT value #>> '{}' INTO v_project_url
    FROM public.app_config WHERE key = 'project_functions_url';
  IF v_project_url IS NULL OR length(v_project_url) = 0 THEN
    v_project_url := 'https://dwbopjjvgepfnclrulvr.supabase.co/functions/v1';
  END IF;

  PERFORM net.http_post(
    url     := v_project_url || '/admin_manage_user',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body    := '{"action":"process_account_deletions"}'::jsonb
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE ALL ON FUNCTION public.drain_account_deletion_queue() FROM anon, authenticated;

-- Replace any prior schedule so re-running this migration is idempotent.
DO $$
DECLARE v_jobid integer;
BEGIN
  SELECT jobid INTO v_jobid FROM cron.job WHERE jobname = 'drain-account-deletion-queue';
  IF v_jobid IS NOT NULL THEN
    PERFORM cron.unschedule(v_jobid);
  END IF;
END $$;

SELECT cron.schedule(
  'drain-account-deletion-queue',
  '15 * * * *', -- top of every hour, +15 min so it doesn't collide with telegram-daily-summary
  $$SELECT public.drain_account_deletion_queue()$$
);

COMMENT ON FUNCTION public.drain_account_deletion_queue() IS
  'Hourly pg_cron drain of public.account_delete_requests via admin_manage_user edge fn. SEC-005.';
