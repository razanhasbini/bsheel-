-- ============================================================
-- MIGRATION 0112: Comment mentions
-- Allows client-created mention notifications when the caller has
-- actually posted a comment on the referenced submission containing
-- @target_username.
-- ============================================================

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (type IN (
    'quest_assigned',
    'submission_approved',
    'submission_rejected',
    'reaction_received',
    'level_up',
    'announcement',
    'new_follower',
    'new_comment',
    'quest_expired',
    'follow_quest_completed',
    'reaction_milestone',
    'new_submission',
    'appeal_submitted',
    'leaderboard_overtaken',
    'top_10_entry',
    'quest_timer_warning',
    'pending_review_reminder',
    'comment_reply',
    'collab_joined',
    'collab_partner_approved',
    'content_report',
    'mention'
  ));

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
  v_target_username text;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF v_caller = p_target_user_id THEN
    RETURN;
  END IF;

  IF p_type NOT IN (
    'reaction_received',
    'new_follower',
    'new_comment',
    'comment_reply',
    'mention'
  ) THEN
    RAISE EXCEPTION 'Notification type not allowed: %', p_type;
  END IF;

  IF p_type = 'reaction_received' AND v_reference_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.submissions
      WHERE id = v_reference_id::uuid
        AND user_id = p_target_user_id
    ) THEN
      RAISE EXCEPTION 'Not authorized to send reaction notification for this submission';
    END IF;
  END IF;

  IF p_type = 'new_comment' AND v_reference_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.submissions
      WHERE id = v_reference_id::uuid
        AND user_id = p_target_user_id
    ) THEN
      RAISE EXCEPTION 'Not authorized to send comment notification for this submission';
    END IF;
  END IF;

  IF p_type = 'comment_reply' AND v_reference_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.comments
      WHERE submission_id = v_reference_id::uuid
        AND user_id = p_target_user_id
    ) THEN
      RAISE EXCEPTION 'Not authorized to send reply notification to this user';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.comments
      WHERE submission_id = v_reference_id::uuid
        AND user_id = v_caller
    ) THEN
      RAISE EXCEPTION 'You must have commented on this submission to send a reply notification';
    END IF;
  END IF;

  IF p_type = 'mention' THEN
    IF v_reference_id IS NULL THEN
      RAISE EXCEPTION 'Mention notifications require a referenced submission';
    END IF;

    SELECT username INTO v_target_username
    FROM public.profiles
    WHERE id = p_target_user_id;

    IF v_target_username IS NULL THEN
      RAISE EXCEPTION 'Mention target not found';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.comments
      WHERE submission_id = v_reference_id::uuid
        AND user_id = v_caller
        AND body ~* ('(^|[^A-Za-z0-9_])@' || v_target_username || '([^A-Za-z0-9_]|$)')
    ) THEN
      RAISE EXCEPTION 'Not authorized to send mention notification to this user';
    END IF;
  END IF;

  IF p_type = 'new_follower' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.follows
      WHERE follower_id = v_caller
        AND following_id = p_target_user_id
    ) THEN
      RAISE EXCEPTION 'Not authorized to send follow notification';
    END IF;
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id, actor_id)
  VALUES (
    p_target_user_id,
    p_title,
    p_body,
    p_type,
    v_reference_id,
    v_caller
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.send_notification(uuid, text, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_notification(uuid, text, text, text, jsonb) TO authenticated;
