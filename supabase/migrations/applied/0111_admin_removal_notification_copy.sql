-- ============================================================
-- MIGRATION 0111: Custom notification copy for admin post removal
-- Splits the rejection branch of handle_submission_approved:
--   • visibility='deleted' (admin removed an approved post)
--       → "We removed your post" / apologetic body, mentions XP revert
--   • everything else (regular pending → rejected review)
--       → existing "Submission Rejected" copy
-- ============================================================

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
      SET xp = xp + coalesce(quest_xp, 10),
          quests_completed = quests_completed + 1,
          level = greatest(1, (xp + coalesce(quest_xp, 10)) / 100 + 1)
      WHERE id = new.user_id;

    new.xp_awarded := true;

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
    UPDATE public.user_quests
      SET status = 'rejected'
      WHERE id = new.user_quest_id;

    IF new.visibility = 'deleted' THEN
      -- Admin removed an approved post from the feed.
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
        coalesce('Reason: ' || new.review_note, 'Your submission was not approved. Try again!'),
        'submission_rejected',
        new.id::text
      );
    END IF;
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
