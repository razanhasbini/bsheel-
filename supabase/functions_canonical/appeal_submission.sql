-- Canonical body for appeal_submission(p_submission_id, p_appeal_note).
-- Authoritative since migration 0149 (previous: 0140 C5, NOT 0119).
--
-- ANY redefinition MUST preserve both of:
--   * the deleted-visibility guard                            (0140 C5)
--   * PERFORM set_config('app.bypass_submission_guard', ...)  (0119)
-- The bypass is what lets this function move submissions.status past
-- guard_submission_owner_update (0114 trigger, 0133 body), whose
-- allow-list does not contain `status`. 0140 rebuilt the body from
-- 0052 and dropped it, so every non-admin appeal failed until 0149.
--
-- When you next change this, edit THIS file + add a migration that
-- INLINES the body (\i cannot resolve — see README).
CREATE OR REPLACE FUNCTION public.appeal_submission(
  p_submission_id uuid,
  p_appeal_note text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_submission RECORD;
  v_visibility text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT id, user_id, status, appealed, user_quest_id
    INTO v_submission
    FROM public.submissions
    WHERE id = p_submission_id;

  IF v_submission IS NULL THEN
    RAISE EXCEPTION 'Submission not found';
  END IF;

  IF v_submission.user_id != auth.uid() THEN
    RAISE EXCEPTION 'Not your submission' USING ERRCODE = '42501';
  END IF;

  IF v_submission.status != 'rejected' THEN
    RAISE EXCEPTION 'Only rejected submissions can be appealed';
  END IF;

  IF v_submission.appealed THEN
    RAISE EXCEPTION 'Already appealed';
  END IF;

  -- 0140 C5: block appeal of a soft-deleted submission. Read via
  -- to_jsonb so this is safe on a DB where 0049 was rolled back.
  SELECT (to_jsonb(s)->>'visibility') INTO v_visibility
    FROM public.submissions s WHERE s.id = p_submission_id;
  IF coalesce(v_visibility, 'visible') = 'deleted' THEN
    RAISE EXCEPTION 'Cannot appeal a deleted submission';
  END IF;

  -- 0119: open the owner-guard trapdoor, TRANSACTION-LOCAL only (the
  -- third argument to set_config). Every ownership / status / appealed /
  -- deleted check above has already passed, so the bypass can only cover
  -- this one legal transition.
  PERFORM set_config('app.bypass_submission_guard', 'on', true);

  UPDATE public.submissions
    SET status = 'pending',
        appeal_note = p_appeal_note,
        appealed = true,
        reviewed_by = NULL,
        review_note = NULL,
        reviewed_at = NULL
    WHERE id = p_submission_id;

  UPDATE public.user_quests
    SET status = 'submitted'
    WHERE id = v_submission.user_quest_id;
END;
$$;

-- NEW in 0149. No migration has EVER issued a GRANT or REVOKE on
-- appeal_submission (0052 created it, 0119/0140 reissued it, none of
-- them touched privileges), so it still carries Postgres's default
-- EXECUTE-to-PUBLIC and anon inherits through PUBLIC. It fails closed
-- on `auth.uid() IS NULL`, so this is latent rather than exploitable —
-- close it anyway, consistent with §2/§3/§4.
REVOKE EXECUTE ON FUNCTION public.appeal_submission(uuid, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.appeal_submission(uuid, text) TO authenticated;
