-- ============================================================
-- MIGRATION 0037: Quest timer warning (30 min) via pg_cron
-- Creates send_quest_timer_warnings() and schedules it every 5 min.
-- ============================================================

CREATE OR REPLACE FUNCTION public.send_quest_timer_warnings()
RETURNS void AS $$
DECLARE
  v_rec RECORD;
BEGIN
  FOR v_rec IN
    SELECT uq.id AS user_quest_id, uq.user_id
    FROM public.user_quests uq
    WHERE uq.status = 'assigned'
      -- expires within the 25–35 minute window (30-min warning band)
      AND uq.expires_at BETWEEN now() + interval '25 minutes'
                            AND now() + interval '35 minutes'
      -- no existing timer warning for this user_quest
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.user_id      = uq.user_id
          AND n.type         = 'quest_timer_warning'
          AND n.reference_id = uq.id::text
      )
  LOOP
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_rec.user_id,
      '⏰ 30 Minutes Left!',
      'Hurry! Your quest expires in 30 minutes',
      'quest_timer_warning',
      v_rec.user_quest_id::text
    );
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Schedule to run every 5 minutes
SELECT cron.schedule(
  'quest-timer-warnings',
  '*/5 * * * *',
  'SELECT send_quest_timer_warnings()'
);
