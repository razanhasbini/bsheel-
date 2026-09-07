-- ============================================================
-- MIGRATION 0050: Auto-send FCM push when notification is inserted
-- Uses pg_net to call the notify-on-insert edge function directly
-- from a database trigger, eliminating the need for a webhook.
-- ============================================================

-- Ensure pg_net extension is enabled (Supabase projects have it available)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Trigger function: fires on every INSERT into notifications
-- and sends an HTTP POST to the notify-on-insert edge function.
-- Uses the same FCM path as the working manual admin notifications.
-- Reads the service role key from Supabase Vault.
CREATE OR REPLACE FUNCTION public.send_push_on_notification()
RETURNS trigger AS $$
DECLARE
  v_service_key text;
BEGIN
  -- Read service role key from Supabase Vault
  SELECT decrypted_secret INTO v_service_key
    FROM vault.decrypted_secrets
    WHERE name = 'service_role_key'
    LIMIT 1;

  -- If service key is not configured, skip silently (don't break inserts)
  IF v_service_key IS NULL OR v_service_key = '' THEN
    RETURN NEW;
  END IF;

  -- pg_net.http_post is async (fire-and-forget) so it won't slow down the trigger
  PERFORM net.http_post(
    url     := 'https://dwbopjjvgepfnclrulvr.supabase.co/functions/v1/notify-on-insert',
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

-- Attach the trigger
DROP TRIGGER IF EXISTS on_notification_send_push ON public.notifications;
CREATE TRIGGER on_notification_send_push
  AFTER INSERT ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.send_push_on_notification();
