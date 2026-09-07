-- ============================================================
-- MIGRATION 0113: Persist xp_awarded correctly + recompute stats
--
-- Root cause of "deleted posts still count toward XP/badges":
--
--   handle_submission_approved is an AFTER UPDATE trigger but tries
--   to flag the row with `new.xp_awarded := true`. Postgres silently
--   discards NEW assignments in AFTER triggers, so since migration
--   0054 every approval awarded XP but never persisted the flag.
--   Migration 0110's revoke trigger gates on OLD.xp_awarded, so it
--   has been a no-op for every post-0054 deletion. profiles.xp /
--   .quests_completed / .level (and the badges derived from them)
--   stayed inflated.
--
-- This migration:
--   1. Replaces the approval trigger function so xp_awarded is
--      persisted via a direct UPDATE (works in AFTER triggers).
--   2. Recomputes profiles.xp / quests_completed / level for every
--      user from their currently-approved, non-deleted submissions.
--   3. Resets submissions.xp_awarded so the flag matches reality
--      (true ⇔ approved AND visible) — keeps the 0110 trigger
--      reliable going forward.
-- ============================================================

-- ── 1) Approval trigger: persist xp_awarded via UPDATE ──────
CREATE OR REPLACE FUNCTION public.handle_submission_approved()
RETURNS trigger AS $$
DECLARE
  quest_xp integer;
BEGIN
  IF new.status = 'approved' AND (old.status IS NULL OR old.status != 'approved') THEN
    IF new.xp_awarded THEN
      RETURN new;
    END IF;

    UPDATE public.user_quests
       SET status = 'approved', completed_at = now()
     WHERE id = new.user_quest_id;

    SELECT q.xp_reward INTO quest_xp
      FROM public.quests q
      JOIN public.user_quests uq ON uq.quest_id = q.id
     WHERE uq.id = new.user_quest_id;

    UPDATE public.profiles
       SET xp = xp + COALESCE(quest_xp, 10),
           quests_completed = quests_completed + 1,
           level = GREATEST(1, (xp + COALESCE(quest_xp, 10)) / 100 + 1)
     WHERE id = new.user_id;

    -- AFTER triggers can't mutate NEW; persist the flag with an
    -- explicit UPDATE. This re-fires the trigger for this row, but
    -- the second invocation hits `IF new.xp_awarded THEN RETURN new`
    -- and exits without re-awarding. The trigger is also scoped to
    -- UPDATE OF status, so an UPDATE that only touches xp_awarded
    -- would not refire it anyway.
    UPDATE public.submissions
       SET xp_awarded = true
     WHERE id = new.id;

    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      new.user_id,
      'Submission Approved!',
      'Your submission was approved! +' || COALESCE(quest_xp, 10) || ' XP',
      'submission_approved',
      new.id::text
    );
  END IF;

  IF new.status = 'rejected' AND (old.status IS NULL OR old.status != 'rejected') THEN
    UPDATE public.user_quests
       SET status = 'rejected'
     WHERE id = new.user_quest_id;

    IF new.visibility = 'deleted' THEN
      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      VALUES (
        new.user_id,
        'We removed your post',
        'Sorry — our team had to take this one down. The XP has been reverted, but you can submit the quest again.',
        'submission_rejected',
        new.id::text
      );
    ELSE
      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      VALUES (
        new.user_id,
        'Submission Rejected',
        COALESCE('Reason: ' || new.review_note, 'Your submission was not approved. Try again!'),
        'submission_rejected',
        new.id::text
      );
    END IF;
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 2) Recompute per-user totals from current valid submissions ─
-- Valid = submission.status='approved' AND visibility <> 'deleted'.
-- Self-deletes leave user_quest.status='approved', so we key off
-- submission state, not user_quest.status.
WITH valid AS (
  SELECT s.user_id,
         COALESCE(SUM(q.xp_reward), 0)::int AS total_xp,
         COUNT(*)::int                       AS cnt
    FROM public.submissions s
    JOIN public.user_quests uq ON uq.id = s.user_quest_id
    JOIN public.quests q       ON q.id = uq.quest_id
   WHERE s.status = 'approved'
     AND s.visibility <> 'deleted'
   GROUP BY s.user_id
)
UPDATE public.profiles p
   SET xp               = COALESCE(v.total_xp, 0),
       quests_completed = COALESCE(v.cnt, 0),
       level            = GREATEST(1, COALESCE(v.total_xp, 0) / 100 + 1)
  FROM (
    SELECT p2.id AS user_id,
           v.total_xp,
           v.cnt
      FROM public.profiles p2
      LEFT JOIN valid v ON v.user_id = p2.id
  ) v
 WHERE p.id = v.user_id;

-- ── 3) Reset xp_awarded so it matches reality ───────────────
-- True only for currently-approved, currently-visible submissions.
UPDATE public.submissions
   SET xp_awarded = (status = 'approved' AND visibility <> 'deleted');
