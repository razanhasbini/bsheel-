-- ============================================================
-- MIGRATION 0100: Extend admin_approve_submission to accept an
-- optional review note. The admin web's submission_review_page
-- prompts the reviewer for a free-form note when approving;
-- previously this went through a direct table UPDATE that
-- bypassed the audit log added in 0098. Adding the param so
-- both admin code paths can use the same RPC.
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_approve_submission(
  p_submission_id uuid,
  p_review_note   text DEFAULT NULL
) RETURNS void AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_status text;
  v_note text := NULLIF(trim(coalesce(p_review_note, '')), '');
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_status
    FROM public.submissions
    WHERE id = p_submission_id
    FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Submission not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Submission is no longer pending (current: %)', v_status
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.submissions
    SET status = 'approved',
        reviewed_by = v_actor,
        reviewed_at = now(),
        review_note = COALESCE(v_note, review_note)
    WHERE id = p_submission_id;

  PERFORM public.log_admin_action(
    'submission.approve',
    'submission',
    p_submission_id::text,
    jsonb_build_object(
      'previous_status', v_status,
      'note_chars', COALESCE(length(v_note), 0)
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.admin_approve_submission(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_approve_submission(uuid, text) TO authenticated;

-- Drop the old single-arg overload (added in 0098) so callers must use
-- the new signature. Keeps the surface area clean.
DROP FUNCTION IF EXISTS public.admin_approve_submission(uuid);
