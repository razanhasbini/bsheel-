-- ============================================================
-- MIGRATION 0028b: Add upsert_fcm_token RPC
-- Allows authenticated users to save their own FCM token into
-- private.profile_tokens without direct table access.
-- ============================================================

CREATE OR REPLACE FUNCTION public.upsert_fcm_token(p_token text)
RETURNS void AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  INSERT INTO private.profile_tokens (user_id, fcm_token)
  VALUES (auth.uid(), p_token)
  ON CONFLICT (user_id) DO UPDATE SET fcm_token = EXCLUDED.fcm_token;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Only authenticated users can call this; service_role can always call it.
REVOKE EXECUTE ON FUNCTION public.upsert_fcm_token(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_fcm_token(text) TO authenticated;
