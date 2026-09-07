-- ============================================================
-- MIGRATION 0095: delete_own_fcm_token RPC (logout cleanup)
--
-- private.profile_tokens is service_role-only (see 0029), so a
-- logged-in user can't DELETE from it directly. This RPC runs
-- as SECURITY DEFINER and only ever deletes the caller's own
-- row, gated on auth.uid() — there is no way for caller to
-- target another user's token.
--
-- Called from the client right BEFORE _client.auth.signOut()
-- so auth.uid() is still valid. Without this, the device keeps
-- receiving pushes for the now-logged-out account because
-- send-push / notify-on-insert look tokens up by user_id only.
-- ============================================================

CREATE OR REPLACE FUNCTION public.delete_own_fcm_token()
RETURNS void AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  DELETE FROM private.profile_tokens
  WHERE user_id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.delete_own_fcm_token() TO authenticated;
