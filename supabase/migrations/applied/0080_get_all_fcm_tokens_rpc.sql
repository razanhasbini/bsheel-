-- ============================================================
-- MIGRATION 0080: get_all_fcm_tokens RPC
--
-- The telegram-webhook edge function needs to iterate every
-- registered FCM token to fan out /broadcast pushes. The
-- `private` schema is not exposed to PostgREST, so we expose
-- this via an RPC locked down to service_role.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_all_fcm_tokens()
RETURNS TABLE(user_id uuid, fcm_token text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT user_id, fcm_token
  FROM private.profile_tokens
  WHERE fcm_token IS NOT NULL;
$$;

REVOKE EXECUTE ON FUNCTION public.get_all_fcm_tokens() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_all_fcm_tokens() TO service_role;
