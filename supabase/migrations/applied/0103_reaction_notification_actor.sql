-- ============================================================
-- MIGRATION 0103: Store actor_id for vote notifications
-- (imported from PR #30, originally authored as 0094)
--
-- Migration 0101 adds notifications.actor_id. This updates the automatic
-- reaction/vote trigger so new upvote/downvote notifications can display
-- the reactor's profile in the mobile app.
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_reaction_created()
RETURNS trigger AS $$
DECLARE
  v_submitter_id uuid;
  v_reactor_name text;
  v_vote_label text;
BEGIN
  -- Skip notification if user voted on their own submission
  SELECT s.user_id INTO v_submitter_id
    FROM public.submissions s
   WHERE s.id = NEW.submission_id;

  IF v_submitter_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  SELECT display_name INTO v_reactor_name
    FROM public.profiles
   WHERE id = NEW.user_id;

  IF NEW.type = 'upvote' THEN
    v_vote_label := 'upvoted';
  ELSE
    v_vote_label := 'downvoted';
  END IF;

  INSERT INTO public.notifications (
    user_id,
    title,
    body,
    type,
    reference_id,
    actor_id
  )
  VALUES (
    v_submitter_id,
    'New Vote',
    COALESCE(v_reactor_name, 'Someone') || ' ' || v_vote_label || ' your submission',
    'reaction_received',
    NEW.submission_id,
    NEW.user_id
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
