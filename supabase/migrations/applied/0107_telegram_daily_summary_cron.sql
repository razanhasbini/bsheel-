-- ============================================================
-- MIGRATION 0107: Daily admin summary via pg_cron
-- Posts a "yesterday at a glance" digest to the admin Telegram
-- chat once a day. Calls the telegram-daily-summary edge function.
--
-- Schedule: 06:00 UTC every day.
--   - Beirut summer (UTC+3, DST): 09:00 local
--   - Beirut winter (UTC+2):      08:00 local
-- pg_cron only speaks UTC, so the Beirut-local time drifts by one
-- hour across DST boundaries. That's an acceptable trade for not
-- needing to maintain a tz-aware scheduler.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Helper: hits the edge function. Kept as its own function so the
-- cron entry stays a one-liner and so it's easy to invoke manually
-- for testing (`SELECT public.send_telegram_daily_summary();`).
CREATE OR REPLACE FUNCTION public.send_telegram_daily_summary()
RETURNS void AS $$
DECLARE
  v_service_key text;
BEGIN
  SELECT decrypted_secret INTO v_service_key
    FROM vault.decrypted_secrets
    WHERE name = 'service_role_key'
    LIMIT 1;

  IF v_service_key IS NULL OR v_service_key = '' THEN
    RAISE WARNING 'send_telegram_daily_summary: service_role_key not in vault, skipping';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url     := 'https://dwbopjjvgepfnclrulvr.supabase.co/functions/v1/telegram-daily-summary',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body    := '{}'::jsonb
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Lock down: this should only ever run from pg_cron.
REVOKE ALL ON FUNCTION public.send_telegram_daily_summary() FROM anon, authenticated;

-- Replace any prior schedule of the same name so re-running this
-- migration is idempotent.
DO $$
DECLARE
  v_jobid integer;
BEGIN
  SELECT jobid INTO v_jobid FROM cron.job WHERE jobname = 'telegram-daily-summary';
  IF v_jobid IS NOT NULL THEN
    PERFORM cron.unschedule(v_jobid);
  END IF;
END $$;

SELECT cron.schedule(
  'telegram-daily-summary',
  '0 6 * * *',
  'SELECT public.send_telegram_daily_summary()'
);
