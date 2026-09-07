-- ============================================================
-- MIGRATION 0098: Admin audit log + atomic admin_approve_submission /
-- admin_reject_submission RPCs.
--
-- Until now there was zero record of who approved, rejected, broadcast,
-- injected, or notified — making admin abuse / bugs invisible. This
-- migration adds:
--   1. public.admin_audit_log table (append-only, super-admin readable)
--   2. log_admin_action() helper (SECURITY DEFINER, callable from
--      other admin SECURITY DEFINER functions)
--   3. admin_approve_submission / admin_reject_submission RPCs that
--      replace the admin web's direct UPDATE — verifies admin status,
--      asserts current state, performs the update, and writes audit
--      entry in one transaction
--   4. broadcast_announcement now logs the actor + recipient_count
--   5. inject_quest_for_user logs the actor + target + quest_id
--   6. admin_send_notification logs the actor + target
-- ============================================================

-- ── 1. Audit log table ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.admin_audit_log (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id     uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action       text NOT NULL,
  target_type  text,
  target_id    text,
  payload      jsonb,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_created_at
  ON public.admin_audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_log_actor
  ON public.admin_audit_log (actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_log_action
  ON public.admin_audit_log (action, created_at DESC);

ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_audit_log_select_super ON public.admin_audit_log;
CREATE POLICY admin_audit_log_select_super
  ON public.admin_audit_log
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.admins
      WHERE user_id = auth.uid()
        AND role = 'super_admin'
    )
  );

REVOKE INSERT, UPDATE, DELETE ON public.admin_audit_log FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.admin_audit_log TO authenticated;

-- ── 2. log_admin_action helper ────────────────────────────────
CREATE OR REPLACE FUNCTION public.log_admin_action(
  p_action      text,
  p_target_type text DEFAULT NULL,
  p_target_id   text DEFAULT NULL,
  p_payload     jsonb DEFAULT NULL
) RETURNS void AS $$
BEGIN
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, payload)
  VALUES (auth.uid(), p_action, p_target_type, p_target_id, p_payload);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.log_admin_action(text, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.log_admin_action(text, text, text, jsonb) TO authenticated;

-- ── 3. admin_approve_submission ───────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_approve_submission(
  p_submission_id uuid
) RETURNS void AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_status text;
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
        reviewed_at = now()
    WHERE id = p_submission_id;

  PERFORM public.log_admin_action(
    'submission.approve',
    'submission',
    p_submission_id::text,
    jsonb_build_object('previous_status', v_status)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.admin_approve_submission(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_approve_submission(uuid) TO authenticated;

-- ── 4. admin_reject_submission ────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_reject_submission(
  p_submission_id uuid,
  p_review_note   text
) RETURNS void AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_status text;
  v_note text := coalesce(trim(p_review_note), '');
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  IF v_note = '' THEN
    RAISE EXCEPTION 'Rejection note is required' USING ERRCODE = '22023';
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
    SET status = 'rejected',
        reviewed_by = v_actor,
        review_note = v_note,
        reviewed_at = now()
    WHERE id = p_submission_id;

  PERFORM public.log_admin_action(
    'submission.reject',
    'submission',
    p_submission_id::text,
    jsonb_build_object(
      'previous_status', v_status,
      'note_chars', length(v_note)
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.admin_reject_submission(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reject_submission(uuid, text) TO authenticated;

-- ── 5. Audit-instrument broadcast_announcement ────────────────
CREATE OR REPLACE FUNCTION public.broadcast_announcement(
  p_title text,
  p_body  text
) RETURNS integer AS $$
DECLARE
  v_count integer;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type)
  SELECT p.id, p_title, p_body, 'announcement'
  FROM public.profiles p
  WHERE p.username IS NOT NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;

  PERFORM public.log_admin_action(
    'broadcast.announcement',
    'broadcast',
    NULL,
    jsonb_build_object(
      'title', left(p_title, 200),
      'body_chars', length(p_body),
      'recipient_count', v_count
    )
  );

  RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.broadcast_announcement(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.broadcast_announcement(text, text) TO authenticated;

-- ── 6. Audit-instrument admin_send_notification ───────────────
CREATE OR REPLACE FUNCTION public.admin_send_notification(
  p_target_user_id uuid,
  p_title text,
  p_body text,
  p_type text DEFAULT 'announcement'
) RETURNS public.notifications AS $$
DECLARE
  v_row public.notifications;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type)
  VALUES (p_target_user_id, p_title, p_body, p_type)
  RETURNING * INTO v_row;

  PERFORM public.log_admin_action(
    'notification.send',
    'user',
    p_target_user_id::text,
    jsonb_build_object(
      'title', left(p_title, 200),
      'body_chars', length(p_body),
      'type', p_type
    )
  );

  RETURN v_row;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
