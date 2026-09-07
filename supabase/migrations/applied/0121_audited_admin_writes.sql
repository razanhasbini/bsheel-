-- ============================================================
-- MIGRATION 0121: Audited admin write RPCs (SEC-009).
--
-- The admin web's xp_management_page and feed_management_page write
-- directly to `profiles` and `submissions`, bypassing the audit log
-- introduced in 0098. This migration adds two SECURITY DEFINER RPCs
-- that wrap the same writes plus a log_admin_action() entry, so every
-- admin write surface is captured.
--
-- These complement (do not replace) the existing
-- admin_approve_submission / admin_reject_submission from 0098/0100 —
-- those handle moderation transitions; these handle the "fix bad
-- state" admin actions.
-- ============================================================

-- ── admin_set_user_xp ──────────────────────────────────────────
-- Used by xp_management_page._fixUser / _fixAll. Wraps the
-- profiles UPDATE in an admin guard + audit log entry.
CREATE OR REPLACE FUNCTION public.admin_set_user_xp(
  p_user_id          uuid,
  p_xp               integer,
  p_level            integer,
  p_quests_completed integer,
  p_reason           text
) RETURNS void AS $$
DECLARE
  v_old_xp     integer;
  v_old_level  integer;
  v_old_done   integer;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF p_xp < 0 OR p_level < 1 OR p_quests_completed < 0 THEN
    RAISE EXCEPTION 'XP / level / quests_completed must be non-negative';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'A reason is required (>= 3 characters)';
  END IF;

  SELECT xp, level, quests_completed
    INTO v_old_xp, v_old_level, v_old_done
    FROM public.profiles WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found';
  END IF;

  UPDATE public.profiles
    SET xp               = p_xp,
        level            = p_level,
        quests_completed = p_quests_completed,
        updated_at       = now()
    WHERE id = p_user_id;

  PERFORM public.log_admin_action(
    'user.set_xp',
    'profile',
    p_user_id::text,
    jsonb_build_object(
      'old', jsonb_build_object('xp', v_old_xp, 'level', v_old_level,
                                'quests_completed', v_old_done),
      'new', jsonb_build_object('xp', p_xp, 'level', p_level,
                                'quests_completed', p_quests_completed),
      'reason', left(p_reason, 500)
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.admin_set_user_xp(uuid, integer, integer, integer, text)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_set_user_xp(uuid, integer, integer, integer, text)
  TO authenticated;

-- ── admin_remove_post ──────────────────────────────────────────
-- Used by feed_management_page._removePost. Soft-deletes a post (does
-- not change submission.status) plus writes an audit row. Pairs with
-- the existing 0114 deleted_posts view for review.
CREATE OR REPLACE FUNCTION public.admin_remove_post(
  p_submission_id uuid,
  p_reason        text
) RETURNS void AS $$
DECLARE
  v_user_id     uuid;
  v_old_status  text;
  v_old_visi    text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'A reason is required (>= 3 characters)';
  END IF;

  SELECT user_id, status, visibility
    INTO v_user_id, v_old_status, v_old_visi
    FROM public.submissions
    WHERE id = p_submission_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Submission not found';
  END IF;

  UPDATE public.submissions
    SET visibility = 'deleted',
        deleted_at = now()
    WHERE id = p_submission_id;

  PERFORM public.log_admin_action(
    'post.remove',
    'submission',
    p_submission_id::text,
    jsonb_build_object(
      'user_id',         v_user_id,
      'previous_status', v_old_status,
      'prev_visibility', v_old_visi,
      'reason',          left(p_reason, 500)
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.admin_remove_post(uuid, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_remove_post(uuid, text) TO authenticated;
