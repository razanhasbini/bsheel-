-- ============================================================
-- MIGRATION 0126: Pass webhook secret header to telegram-daily-summary
-- (SEC-030 follow-up).
--
-- The edge function now requires `x-webhook-secret` to match
-- TELEGRAM_WEBHOOK_SECRET. The cron caller in 0107 didn't set that
-- header, so without this migration the cron would 403. This pulls
-- the secret from Vault and adds it to the request.
-- ============================================================

CREATE OR REPLACE FUNCTION public.send_telegram_daily_summary()
RETURNS void AS $$
DECLARE
  v_service_key text;
  v_webhook_secret text;
  v_headers jsonb;
BEGIN
  SELECT decrypted_secret INTO v_service_key
    FROM vault.decrypted_secrets
    WHERE name = 'service_role_key'
    LIMIT 1;

  IF v_service_key IS NULL OR v_service_key = '' THEN
    RAISE WARNING 'send_telegram_daily_summary: service_role_key not in vault, skipping';
    RETURN;
  END IF;

  SELECT decrypted_secret INTO v_webhook_secret
    FROM vault.decrypted_secrets
    WHERE name = 'telegram_webhook_secret'
    LIMIT 1;

  v_headers := jsonb_build_object(
    'Content-Type',  'application/json',
    'Authorization', 'Bearer ' || v_service_key
  );

  IF v_webhook_secret IS NOT NULL AND v_webhook_secret <> '' THEN
    v_headers := v_headers || jsonb_build_object('x-webhook-secret', v_webhook_secret);
  ELSE
    RAISE WARNING 'send_telegram_daily_summary: telegram_webhook_secret missing in vault — call will 403';
  END IF;

  PERFORM net.http_post(
    url     := 'https://dwbopjjvgepfnclrulvr.supabase.co/functions/v1/telegram-daily-summary',
    headers := v_headers,
    body    := '{}'::jsonb
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE ALL ON FUNCTION public.send_telegram_daily_summary() FROM anon, authenticated;

COMMENT ON FUNCTION public.send_telegram_daily_summary() IS
  'Cron-only. Requires both service_role_key and telegram_webhook_secret in vault.decrypted_secrets.';
