-- ============================================================
-- MIGRATION 0067: Persist announcement notifications (L3)
-- RPC that inserts an 'announcement' notification for every user.
-- Called by admin after sending FCM push.
-- ============================================================

CREATE OR REPLACE FUNCTION public.broadcast_announcement(
  p_title text,
  p_body  text
)
RETURNS integer AS $$
DECLARE
  v_count integer;
BEGIN
  -- Only admins can broadcast
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type)
  SELECT p.id, p_title, p_body, 'announcement'
  FROM public.profiles p
  WHERE p.username IS NOT NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.broadcast_announcement(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.broadcast_announcement(text, text) TO authenticated;
