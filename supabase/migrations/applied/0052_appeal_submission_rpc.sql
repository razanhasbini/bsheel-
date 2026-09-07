-- ============================================================
-- MIGRATION 0052: RPC for submitting an appeal
-- Users can't update submissions directly (admin-only RLS).
-- This SECURITY DEFINER function lets a user appeal their own
-- rejected submission safely.
-- ============================================================

CREATE OR REPLACE FUNCTION public.appeal_submission(
  p_submission_id uuid,
  p_appeal_note text
)
RETURNS void AS $$
DECLARE
  v_submission RECORD;
BEGIN
  -- Must be authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Fetch the submission and verify ownership + eligibility
  SELECT id, user_id, status, appealed, user_quest_id
    INTO v_submission
    FROM public.submissions
    WHERE id = p_submission_id;

  IF v_submission IS NULL THEN
    RAISE EXCEPTION 'Submission not found';
  END IF;

  IF v_submission.user_id != auth.uid() THEN
    RAISE EXCEPTION 'Not your submission';
  END IF;

  IF v_submission.status != 'rejected' THEN
    RAISE EXCEPTION 'Only rejected submissions can be appealed';
  END IF;

  IF v_submission.appealed THEN
    RAISE EXCEPTION 'Already appealed';
  END IF;

  -- Update the submission: reset to pending with appeal info
  UPDATE public.submissions
    SET status = 'pending',
        appeal_note = p_appeal_note,
        appealed = true,
        reviewed_by = NULL,
        review_note = NULL,
        reviewed_at = NULL
    WHERE id = p_submission_id;

  -- Update user_quests status back to submitted
  UPDATE public.user_quests
    SET status = 'submitted'
    WHERE id = v_submission.user_quest_id;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
