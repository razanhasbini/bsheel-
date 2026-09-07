-- ============================================================
-- MIGRATION 0150: Fix the two cron jobs that have never worked.
--
-- Numbered 0150 because 0149_repair_voting_appeals_feed_config_and_caps.sql
-- already occupies 0149. That file repairs vote_collab / appeal_submission /
-- get_feed / app_config; it does NOT touch either function below. The two
-- are complementary — apply both, 0149 first.
--
-- Found 2026-08-04 by reading cron.job_run_details on prod: two of the five
-- scheduled jobs were failing 100% of the time, silently, because nothing
-- monitors them.
--
--   expire-overdue-quests    2016 failures / 7 days (every 5 min)
--     ERROR: Not authorized  (expire_overdue_quests() line 6)
--
--   pending-review-reminder   168 failures / 7 days (hourly)
--     ERROR: column "created_at" does not exist
--
-- User-visible impact of the first: quests never expired, so 14 users have
-- been stuck holding an 'assigned' quest since 2026-05-04. assign_random_quest
-- refuses anyone who already has an active quest, so those users cannot roll
-- a new quest at all — the core loop is dead for them.
--
-- Wrapped in a single transaction for the same reason 0149 is:
-- scripts/server-deploy.sh:8 runs psql WITHOUT --single-transaction, so
-- without this a failure at statement N leaves 1..N-1 committed AND the file
-- untracked. Every statement here is transactional. Idempotent.
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- §1  expire_overdue_quests — authorization guard rejected pg_cron
--
-- pg_cron runs this job as `supabase_admin` with the `role` GUC unset
-- ('none'), so the original guard
--     auth.uid() IS NULL AND current_setting('role',true) != 'service_role'
-- was true on every run and raised.
--
-- The guard is NOT redundant and must not simply be deleted: despite
-- applied/0066_revoke_expire_from_users.sql, PUBLIC and anon STILL hold
-- EXECUTE on this function in prod (verified via
-- information_schema.routine_privileges on 2026-08-04). Until the revoke
-- below lands, this guard is the only thing stopping an anonymous caller
-- from mass-expiring every user's active quest.
--
-- Use session_user, NOT current_user. This function is SECURITY DEFINER and
-- owned by `postgres`, so current_user is rewritten to 'postgres' inside the
-- body regardless of caller — useless for authorization, and the reason a
-- pg_has_role(current_user, ...) check also fails here. session_user keeps
-- the real connected role:
--     pg_cron           -> supabase_admin
--     psql on the box   -> postgres / supabase_admin
--     ALL PostgREST API -> authenticator (both anon and authenticated, which
--                          then SET ROLE) — API traffic can never satisfy it.
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.expire_overdue_quests()
RETURNS void AS $$
DECLARE
  v_rec RECORD;
BEGIN
  -- Allowed callers:
  --   * authenticated end user     (auth.uid() IS NOT NULL)
  --   * service_role               (edge functions)
  --   * supabase_admin / postgres  (pg_cron — this is the new arm)
  IF auth.uid() IS NULL
     AND coalesce(current_setting('role', true), 'none') <> 'service_role'
     AND session_user NOT IN ('supabase_admin', 'postgres')
  THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  FOR v_rec IN
    SELECT uq.id AS user_quest_id, uq.user_id
    FROM public.user_quests uq
    WHERE uq.status = 'assigned'
      AND uq.expires_at < now()
  LOOP
    UPDATE public.user_quests
      SET status = 'expired'
      WHERE id = v_rec.user_quest_id;

    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_rec.user_id,
      'Quest gone. Poof. 💨',
      'Time ran out. Pull a new one and try again. No streak shame here.',
      'quest_expired',
      v_rec.user_quest_id::text
    );
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Finish what 0066 intended. No Dart code calls this RPC (see the note in
-- packages/supabase_contracts/lib/rpc_names.dart); it runs from cron only.
-- service_role keeps EXECUTE so edge functions are unaffected.
REVOKE EXECUTE ON FUNCTION public.expire_overdue_quests() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.expire_overdue_quests() FROM anon;
REVOKE EXECUTE ON FUNCTION public.expire_overdue_quests() FROM authenticated;

COMMENT ON FUNCTION public.expire_overdue_quests() IS
  'Cron-only (every 5 min). Guard uses session_user because SECURITY DEFINER '
  'rewrites current_user to the owner. Fixed 0150 after 2016 failures/week.';


-- ════════════════════════════════════════════════════════════
-- §2  send_pending_review_reminders — queried a column that doesn't exist
--
-- public.submissions has submitted_at / reviewed_at / deleted_at. There is
-- no created_at, so the COUNT(*) threw on every run and no admin has ever
-- received a stale-queue reminder. 4 submissions have been pending since
-- 2026-05-12.
--
-- NOTE: the second created_at reference in this function (on
-- public.notifications) is CORRECT — that table does have created_at.
-- Only the submissions predicate changes.
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.send_pending_review_reminders()
RETURNS void AS $$
DECLARE
  v_pending_count integer;
  v_admin         RECORD;
BEGIN
  SELECT COUNT(*) INTO v_pending_count
    FROM public.submissions
    WHERE status = 'pending'
      AND submitted_at < now() - interval '24 hours';   -- was: created_at

  IF v_pending_count = 0 THEN
    RETURN;
  END IF;

  FOR v_admin IN SELECT user_id FROM public.admins LOOP
    -- notifications.created_at IS a real column — correct as-is.
    IF NOT EXISTS (
      SELECT 1 FROM public.notifications
      WHERE user_id    = v_admin.user_id
        AND type       = 'pending_review_reminder'
        AND created_at > now() - interval '24 hours'
    ) THEN
      INSERT INTO public.notifications (user_id, title, body, type)
      VALUES (
        v_admin.user_id,
        '⚠️ ' || v_pending_count || ' submissions are getting stale.',
        'These have been sitting in the queue for over 24 hours. Time to triage.',
        'pending_review_reminder'
      );
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- On first successful run this sends ONE reminder to each admin about the 4
-- stale pending submissions. Expected, not a bug.


-- ════════════════════════════════════════════════════════════
-- §3  Backfill the 14 stuck quests QUIETLY.
--
-- ⚠️ READ BEFORE PUSHING — deliberate product choice.
--
-- The moment §1 works, the next cron tick (within 5 min) expires all 14
-- overdue quests AND sends each of those users a "Quest gone. Poof. 💨"
-- push — for quests that expired up to three months ago. Fourteen dormant
-- friends-and-family testers would get a confusing notification.
--
-- This block expires them first without notifications, so the cron finds
-- nothing to announce and only notifies on genuinely fresh expiries after.
--
-- KEEP   -> silent cleanup, no notifications.  (default)
-- DELETE -> the 14 users each get a push within ~5 min, which you may want
--           as a re-engagement nudge.
--
-- Either way they become unstuck and can roll a new quest again.
-- ════════════════════════════════════════════════════════════
UPDATE public.user_quests
   SET status = 'expired'
 WHERE status = 'assigned'
   AND expires_at < now();

DO $$ BEGIN
  RAISE NOTICE '0150 applied: expire_overdue_quests guard fixed (was 2016 failures/wk), send_pending_review_reminders created_at->submitted_at, stuck quests backfilled silently';
END $$;

COMMIT;

-- ════════════════════════════════════════════════════════════
-- Verify after deploy, on the server:
--
--   docker exec -i supabase-db psql -U supabase_admin -d postgres -c "
--     SELECT j.jobname, d.status, count(*)
--     FROM cron.job_run_details d JOIN cron.job j USING (jobid)
--     WHERE d.start_time > now() - interval '20 minutes'
--     GROUP BY 1,2 ORDER BY 1;"
--
-- Both jobs should read 'succeeded'. Then confirm nobody is stuck:
--
--   SELECT count(*) FROM public.user_quests
--    WHERE status='assigned' AND expires_at < now();   -- expect 0
-- ════════════════════════════════════════════════════════════
