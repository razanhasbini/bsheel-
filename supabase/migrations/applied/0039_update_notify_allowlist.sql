-- ============================================================
-- MIGRATION 0039: Extend send_notification RPC allowlist
-- Adds comment_reply as a client-callable notification type.
-- ============================================================

CREATE OR REPLACE FUNCTION public.send_notification(
  p_target_user_id uuid,
  p_type          text,
  p_title         text,
  p_body          text,
  p_data          jsonb DEFAULT NULL
)
RETURNS void AS $$
DECLARE
  v_caller       uuid := auth.uid();
  v_reference_id text := p_data->>'reference_id';
BEGIN
  -- Require authentication
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Don't notify yourself
  IF v_caller = p_target_user_id THEN
    RETURN;
  END IF;

  -- Validate allowed notification types (client-callable only)
  IF p_type NOT IN ('reaction_received', 'new_follower', 'new_comment', 'comment_reply') THEN
    RAISE EXCEPTION 'Notification type not allowed: %', p_type;
  END IF;

  -- For reaction_received: target must own the submission
  IF p_type = 'reaction_received' AND v_reference_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.submissions
      WHERE id      = v_reference_id::uuid
        AND user_id = p_target_user_id
    ) THEN
      RAISE EXCEPTION 'Not authorized to send reaction notification for this submission';
    END IF;
  END IF;

  -- For new_comment: target must own the submission
  IF p_type = 'new_comment' AND v_reference_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.submissions
      WHERE id      = v_reference_id::uuid
        AND user_id = p_target_user_id
    ) THEN
      RAISE EXCEPTION 'Not authorized to send comment notification for this submission';
    END IF;
  END IF;

  -- For comment_reply: target must have previously commented on the submission
  IF p_type = 'comment_reply' AND v_reference_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.comments
      WHERE submission_id = v_reference_id::uuid
        AND user_id       = p_target_user_id
    ) THEN
      RAISE EXCEPTION 'Not authorized to send reply notification to this user';
    END IF;
  END IF;

  -- For new_follower: caller must be following the target
  IF p_type = 'new_follower' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.follows
      WHERE follower_id  = v_caller
        AND following_id = p_target_user_id
    ) THEN
      RAISE EXCEPTION 'Not authorized to send follow notification';
    END IF;
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  VALUES (
    p_target_user_id,
    p_title,
    p_body,
    p_type,
    v_reference_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Maintain same grants
REVOKE EXECUTE ON FUNCTION public.send_notification(uuid, text, text, text, jsonb) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.send_notification(uuid, text, text, text, jsonb) TO authenticated;
