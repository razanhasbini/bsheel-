-- ============================================================
-- MIGRATION 0035: get_fcm_token RPC for edge function use
-- The notify-on-insert edge function needs to look up a user's
-- FCM token from private.profile_tokens. PostgREST does not
-- expose the private schema, so a SECURITY DEFINER RPC is the
-- only way to read from it via the Supabase JS client.
-- Only the service_role can call this function.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_fcm_token(p_user_id uuid)
RETURNS text AS $$
DECLARE
  v_token text;
BEGIN
  SELECT fcm_token INTO v_token
  FROM private.profile_tokens
  WHERE user_id = p_user_id;
  RETURN v_token;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Restrict: no public/anon/authenticated access — only service_role
REVOKE EXECUTE ON FUNCTION public.get_fcm_token(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_fcm_token(uuid) TO service_role;
