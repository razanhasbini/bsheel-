-- ============================================================
-- MIGRATION 0110: Revoke XP when an approved post is deleted
-- Adds a trigger on submissions.visibility transitioning to
-- 'deleted'. When the post had xp_awarded = true, decrements
-- profiles.xp / quests_completed / level so the user's stats
-- match what is actually visible on their profile.
--
-- Covers both deletion paths:
--   • Admin "remove from feed" (apps/admin_web)
--   • User self-delete from profile (apps/mobile_app)
-- Both write visibility = 'deleted' to submissions.
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_submission_deletion_xp_revoke()
RETURNS trigger AS $$
DECLARE
  quest_xp integer;
BEGIN
  IF NEW.visibility = 'deleted'
     AND OLD.visibility IS DISTINCT FROM 'deleted'
     AND COALESCE(OLD.xp_awarded, false) = true THEN

    SELECT q.xp_reward INTO quest_xp
      FROM public.quests q
      JOIN public.user_quests uq ON uq.quest_id = q.id
     WHERE uq.id = NEW.user_quest_id;

    quest_xp := COALESCE(quest_xp, 10);

    UPDATE public.profiles
       SET xp = GREATEST(0, xp - quest_xp),
           quests_completed = GREATEST(0, quests_completed - 1),
           level = GREATEST(1, GREATEST(0, xp - quest_xp) / 100 + 1)
     WHERE id = NEW.user_id;

    -- Clear the award flag so a future un-delete + re-approve
    -- can re-award XP through the existing approval trigger.
    UPDATE public.submissions
       SET xp_awarded = false
     WHERE id = NEW.id;
  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_submission_deletion_revoke_xp ON public.submissions;
CREATE TRIGGER on_submission_deletion_revoke_xp
  AFTER UPDATE OF visibility ON public.submissions
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_submission_deletion_xp_revoke();

-- ── Backfill ────────────────────────────────────────────────
-- Reconcile users whose posts were deleted before this trigger
-- existed: subtract the XP that was awarded for each
-- already-deleted submission whose xp_awarded flag is still true.
WITH to_revoke AS (
  SELECT s.id,
         s.user_id,
         COALESCE(q.xp_reward, 10) AS quest_xp
    FROM public.submissions s
    JOIN public.user_quests uq ON uq.id = s.user_quest_id
    JOIN public.quests q       ON q.id = uq.quest_id
   WHERE s.visibility = 'deleted'
     AND s.xp_awarded = true
),
agg AS (
  SELECT user_id,
         SUM(quest_xp)::int AS total_xp,
         COUNT(*)::int      AS cnt
    FROM to_revoke
   GROUP BY user_id
),
profile_update AS (
  UPDATE public.profiles p
     SET xp = GREATEST(0, p.xp - a.total_xp),
         quests_completed = GREATEST(0, p.quests_completed - a.cnt),
         level = GREATEST(1, GREATEST(0, p.xp - a.total_xp) / 100 + 1)
    FROM agg a
   WHERE p.id = a.user_id
  RETURNING p.id
)
UPDATE public.submissions
   SET xp_awarded = false
 WHERE id IN (SELECT id FROM to_revoke);
