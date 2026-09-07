-- ============================================================
-- MIGRATION 0130: Move hardcoded project URL into app_config (SEC-031).
--
-- 0050 / 0107 / 0128 all bake `https://dwbopjjvgepfnclrulvr.supabase.co`
-- into the function body. That couples the SQL to one deployment
-- environment and pollutes every clone of the schema with the prod
-- project ref.
--
-- This puts the base URL into public.app_config under
-- `project_functions_url`, then re-issues the trigger / cron callers
-- to read it dynamically with a hardcoded fallback so a config wipe
-- can't break prod silently.
-- ============================================================

-- Seed the app_config row. INSERT-IF-MISSING so we don't clobber
-- staging overrides someone may have set manually. Stored as plain
-- text — app_config.value is a text column, not jsonb.
INSERT INTO public.app_config (key, value)
VALUES (
  'project_functions_url',
  'https://dwbopjjvgepfnclrulvr.supabase.co/functions/v1'
)
ON CONFLICT (key) DO NOTHING;

-- Helper: resolve the functions URL once with a fallback.
CREATE OR REPLACE FUNCTION public.project_functions_url()
RETURNS text AS $$
  SELECT coalesce(
    (SELECT value FROM public.app_config WHERE key = 'project_functions_url'),
    'https://dwbopjjvgepfnclrulvr.supabase.co/functions/v1'
  );
$$ LANGUAGE sql STABLE;

REVOKE EXECUTE ON FUNCTION public.project_functions_url() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.project_functions_url() TO authenticated, service_role;

-- ── Reissue 0050's send_push_on_notification with the dynamic URL ─
CREATE OR REPLACE FUNCTION public.send_push_on_notification()
RETURNS trigger AS $$
DECLARE
  v_service_key text;
BEGIN
  SELECT decrypted_secret INTO v_service_key
    FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  IF v_service_key IS NULL OR v_service_key = '' THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url     := public.project_functions_url() || '/notify-on-insert',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body    := jsonb_build_object(
      'record', jsonb_build_object(
        'id',           NEW.id,
        'user_id',      NEW.user_id,
        'title',        NEW.title,
        'body',         NEW.body,
        'type',         NEW.type,
        'reference_id', NEW.reference_id,
        'created_at',   NEW.created_at
      )
    )
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Reissue 0107/0126's send_telegram_daily_summary similarly ────
CREATE OR REPLACE FUNCTION public.send_telegram_daily_summary()
RETURNS void AS $$
DECLARE
  v_service_key    text;
  v_webhook_secret text;
  v_headers        jsonb;
BEGIN
  SELECT decrypted_secret INTO v_service_key
    FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  IF v_service_key IS NULL OR v_service_key = '' THEN
    RAISE WARNING 'send_telegram_daily_summary: service_role_key not in vault, skipping';
    RETURN;
  END IF;

  SELECT decrypted_secret INTO v_webhook_secret
    FROM vault.decrypted_secrets WHERE name = 'telegram_webhook_secret' LIMIT 1;

  v_headers := jsonb_build_object(
    'Content-Type',  'application/json',
    'Authorization', 'Bearer ' || v_service_key
  );
  IF v_webhook_secret IS NOT NULL AND v_webhook_secret <> '' THEN
    v_headers := v_headers || jsonb_build_object('x-webhook-secret', v_webhook_secret);
  ELSE
    RAISE WARNING 'send_telegram_daily_summary: telegram_webhook_secret missing — call will 403';
  END IF;

  PERFORM net.http_post(
    url     := public.project_functions_url() || '/telegram-daily-summary',
    headers := v_headers,
    body    := '{}'::jsonb
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE ALL ON FUNCTION public.send_telegram_daily_summary() FROM anon, authenticated;

-- ── Reissue 0128's drain_account_deletion_queue similarly ────────
CREATE OR REPLACE FUNCTION public.drain_account_deletion_queue()
RETURNS void AS $$
DECLARE
  v_service_key text;
BEGIN
  SELECT decrypted_secret INTO v_service_key
    FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  IF v_service_key IS NULL OR v_service_key = '' THEN
    RAISE WARNING 'drain_account_deletion_queue: service_role_key not in vault, skipping';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url     := public.project_functions_url() || '/admin_manage_user',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body    := '{"action":"process_account_deletions"}'::jsonb
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE ALL ON FUNCTION public.drain_account_deletion_queue() FROM anon, authenticated;
