-- ============================================================
-- MIGRATION 0054: Fix double-XP on re-approval (C1)
-- Adds xp_awarded column and gates the trigger so XP is only
-- awarded once per submission, even if approved→rejected→approved.
-- ============================================================

-- Add idempotency flag
ALTER TABLE public.submissions
  ADD COLUMN IF NOT EXISTS xp_awarded boolean NOT NULL DEFAULT false;

-- Backfill: mark all already-approved submissions as xp_awarded
UPDATE public.submissions SET xp_awarded = true WHERE status = 'approved';

-- Replace the trigger function with idempotency guard
CREATE OR REPLACE FUNCTION public.handle_submission_approved()
RETURNS trigger AS $$
DECLARE
  quest_xp integer;
BEGIN
  if new.status = 'approved' AND (old.status IS NULL OR old.status != 'approved') THEN
    -- Idempotency: if XP was already awarded, skip
    IF new.xp_awarded THEN
      RETURN new;
    END IF;

    -- Update user_quest
    UPDATE public.user_quests
      SET status = 'approved', completed_at = now()
      WHERE id = new.user_quest_id;

    -- Get XP reward
    SELECT q.xp_reward INTO quest_xp
      FROM public.quests q
      JOIN public.user_quests uq ON uq.quest_id = q.id
      WHERE uq.id = new.user_quest_id;

    -- Award XP and increment quests_completed
    UPDATE public.profiles
      SET xp = xp + coalesce(quest_xp, 10),
          quests_completed = quests_completed + 1,
          level = greatest(1, (xp + coalesce(quest_xp, 10)) / 100 + 1)
      WHERE id = new.user_id;

    -- Mark XP as awarded atomically
    new.xp_awarded := true;

    -- Create approval notification
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      new.user_id,
      'Submission Approved!',
      'Your submission was approved! +' || coalesce(quest_xp, 10) || ' XP',
      'submission_approved',
      new.id::text
    );
  END IF;

  IF new.status = 'rejected' AND (old.status IS NULL OR old.status != 'rejected') THEN
    -- Update user_quest
    UPDATE public.user_quests
      SET status = 'rejected'
      WHERE id = new.user_quest_id;

    -- Create rejection notification
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      new.user_id,
      'Submission Rejected',
      coalesce('Reason: ' || new.review_note, 'Your submission was not approved. Try again!'),
      'submission_rejected',
      new.id::text
    );
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
