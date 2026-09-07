-- ============================================================
-- MIGRATION 0038: Admin pending-review reminder (24h) via pg_cron
-- Creates send_pending_review_reminders() and schedules it hourly.
-- ============================================================

CREATE OR REPLACE FUNCTION public.send_pending_review_reminders()
RETURNS void AS $$
DECLARE
  v_pending_count integer;
  v_admin         RECORD;
BEGIN
  -- Count submissions pending for more than 24 hours
  SELECT COUNT(*) INTO v_pending_count
    FROM public.submissions
    WHERE status = 'pending'
      AND created_at < now() - interval '24 hours';

  -- Nothing to remind about
  IF v_pending_count = 0 THEN
    RETURN;
  END IF;

  -- Notify each admin (skip if they already got a reminder in the last 24 h)
  FOR v_admin IN
    SELECT user_id FROM public.admins
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.notifications
      WHERE user_id    = v_admin.user_id
        AND type       = 'pending_review_reminder'
        AND created_at > now() - interval '24 hours'
    ) THEN
      INSERT INTO public.notifications (user_id, title, body, type)
      VALUES (
        v_admin.user_id,
        '⚠️ Pending Reviews',
        v_pending_count || ' submissions have been waiting for review for over 24 hours',
        'pending_review_reminder'
      );
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Schedule to run every hour
SELECT cron.schedule(
  'pending-review-reminder',
  '0 * * * *',
  'SELECT send_pending_review_reminders()'
);
