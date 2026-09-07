-- ============================================================
-- MIGRATION 0066: FCM stale token cleanup (L9)
-- Handle invalid FCM tokens by adding cleanup function.
-- Called by notify-on-insert when FCM returns UNREGISTERED.
-- ============================================================

CREATE OR REPLACE FUNCTION public.cleanup_stale_fcm_token(p_user_id uuid)
RETURNS void AS $$
BEGIN
  DELETE FROM private.profile_tokens
  WHERE user_id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Only service_role can call this (edge functions use service role)
REVOKE EXECUTE ON FUNCTION public.cleanup_stale_fcm_token(uuid) FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.cleanup_stale_fcm_token(uuid) TO service_role;
