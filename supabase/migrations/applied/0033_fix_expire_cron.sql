-- ============================================================
-- MIGRATION 0031: Fix expire_overdue_quests for cron/service_role
-- The prior version raised an exception when auth.uid() IS NULL,
-- which broke the pg_cron job that runs as service_role (no JWT).
-- Now allows both authenticated users AND service_role to call it.
-- ============================================================

CREATE OR REPLACE FUNCTION public.expire_overdue_quests()
RETURNS void AS $$
BEGIN
  -- Allow if called by an authenticated user OR by service_role (cron job).
  -- current_setting('role') returns 'service_role' when called via service key.
  IF auth.uid() IS NULL AND current_setting('role', true) != 'service_role' THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  UPDATE public.user_quests
    SET status = 'expired'
    WHERE status = 'assigned'
      AND expires_at < now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
