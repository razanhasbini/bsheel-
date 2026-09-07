-- ============================================================
-- MIGRATION 0131: Hard cap on notification title/body length
-- (SEC-021 partial).
--
-- broadcast_announcement caps title/body at insert time, but every
-- other notification path (reactions, follows, comments, mentions,
-- admin_send_notification, system) has no length validation. Long
-- bodies leak through to the realtime publication and into FCM
-- payloads where they get truncated server-side, and they bloat the
-- notifications table.
--
-- A BEFORE INSERT trigger on public.notifications enforces the same
-- 200/1000 cap globally. Trims rather than rejects so unintended-
-- but-good notifications don't disappear silently.
-- ============================================================

CREATE OR REPLACE FUNCTION public.cap_notification_text()
RETURNS trigger AS $$
BEGIN
  -- Defensive defaults if a path forgets to set them.
  IF new.title IS NULL THEN new.title := ''; END IF;
  IF new.body  IS NULL THEN new.body  := ''; END IF;

  IF length(new.title) > 200 THEN
    new.title := substring(new.title, 1, 200);
  END IF;
  IF length(new.body) > 1000 THEN
    new.body := substring(new.body, 1, 1000);
  END IF;
  RETURN new;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cap_notification_text ON public.notifications;
CREATE TRIGGER trg_cap_notification_text
  BEFORE INSERT OR UPDATE OF title, body ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.cap_notification_text();

COMMENT ON FUNCTION public.cap_notification_text() IS
  'Globally clamp notifications.title to 200 chars and body to 1000 chars (trim, do not reject). SEC-021.';
