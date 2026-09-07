-- ============================================================
-- MIGRATION 0125: Telegram-sourced submission review with audit
-- (SEC-018).
--
-- The Telegram webhook can't call admin_approve_submission /
-- admin_reject_submission directly because those check is_admin()
-- against auth.uid(), and the webhook runs under a service-role
-- token where auth.uid() is NULL.
--
-- This adds a parallel RPC the webhook can use that:
--   * is granted only to service_role (REVOKE from PUBLIC + anon +
--     authenticated)
--   * sets the 0119 bypass GUC so the BEFORE-UPDATE guard lets the
--     row through
--   * writes the same audit log row admin_approve_submission would,
--     with actor_id=NULL and payload.source='telegram' so the row
--     can be filtered/identified
-- ============================================================

CREATE OR REPLACE FUNCTION public.telegram_review_submission(
  p_submission_id     uuid,
  p_approve           boolean,
  p_review_note       text DEFAULT NULL,
  p_telegram_chat_id  text DEFAULT NULL,
  p_telegram_msg_id   text DEFAULT NULL
) RETURNS void AS $$
DECLARE
  v_status text;
  v_user_id uuid;
  v_note text := coalesce(btrim(p_review_note), '');
BEGIN
  IF p_submission_id IS NULL THEN
    RAISE EXCEPTION 'submission_id is required';
  END IF;
  IF NOT p_approve AND v_note = '' THEN
    -- Always have a note for rejections, even if it's a placeholder.
    v_note := 'Rejected via Telegram';
  END IF;

  SELECT status, user_id INTO v_status, v_user_id
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

  -- Open the 0119 trapdoor so the BEFORE-UPDATE guard lets the
  -- write through. Local to this transaction.
  PERFORM set_config('app.bypass_submission_guard', 'on', true);

  IF p_approve THEN
    UPDATE public.submissions
      SET status = 'approved',
          reviewed_by = NULL,           -- no actor: Telegram is "system"
          reviewed_at = now(),
          review_note = NULL
      WHERE id = p_submission_id;
  ELSE
    UPDATE public.submissions
      SET status = 'rejected',
          reviewed_by = NULL,
          reviewed_at = now(),
          review_note = v_note
      WHERE id = p_submission_id;
  END IF;

  -- Audit row, tagged as Telegram-sourced.
  INSERT INTO public.admin_audit_log (
    actor_id, action, target_type, target_id, payload
  ) VALUES (
    NULL,
    CASE WHEN p_approve THEN 'submission.approve' ELSE 'submission.reject' END,
    'submission',
    p_submission_id::text,
    jsonb_build_object(
      'source',           'telegram',
      'previous_status',  v_status,
      'submission_user',  v_user_id,
      'telegram_chat_id', p_telegram_chat_id,
      'telegram_msg_id',  p_telegram_msg_id,
      'note_chars',       length(v_note)
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.telegram_review_submission(uuid, boolean, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.telegram_review_submission(uuid, boolean, text, text, text)
  TO service_role;

COMMENT ON FUNCTION public.telegram_review_submission(uuid, boolean, text, text, text) IS
  'Service-role-only review path for Telegram-sourced moderation. '
  'Audited via admin_audit_log with payload.source=telegram.';
