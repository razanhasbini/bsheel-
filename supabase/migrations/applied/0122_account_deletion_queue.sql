-- ============================================================
-- MIGRATION 0122: Account deletion queue (SEC-005).
--
-- delete_own_account currently scrubs the public.profiles row but
-- leaves auth.users intact, so the on_auth_user_created trigger
-- recreates a profile on the user's next sign-in. Apple/GDPR also
-- expect the auth row to be removed within a window.
--
-- Plpgsql functions can't call Supabase's auth admin API directly,
-- so we queue deletions in a table that the admin_manage_user edge
-- function (or a cron) drains. The RPC marks the profile as
-- pending-deletion and inserts a queue row; the auth.users delete
-- happens out-of-band so a queue worker failure can't roll back the
-- user's intent.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.account_delete_requests (
  user_id      uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  requested_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  attempts     integer NOT NULL DEFAULT 0,
  last_error   text
);

ALTER TABLE public.account_delete_requests ENABLE ROW LEVEL SECURITY;

-- Caller can read their own queued request (lets the UI show
-- "deletion in progress…" if the user re-signs-in before it drains).
DROP POLICY IF EXISTS account_delete_requests_select_own ON public.account_delete_requests;
CREATE POLICY account_delete_requests_select_own ON public.account_delete_requests
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

-- Inserts only via the SECURITY DEFINER RPC below.
-- Admins can DELETE/UPDATE for queue maintenance.
DROP POLICY IF EXISTS account_delete_requests_admin_write ON public.account_delete_requests;
CREATE POLICY account_delete_requests_admin_write ON public.account_delete_requests
  FOR ALL TO authenticated
  USING  (public.is_admin())
  WITH CHECK (public.is_admin());

-- Reissue delete_own_account so it queues the auth-row deletion in
-- addition to scrubbing the profile.
CREATE OR REPLACE FUNCTION public.delete_own_account()
RETURNS void AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Existing profile scrub: keep behaviour parity with prior 0091.
  UPDATE public.profiles
    SET username     = 'deleted_' || substring(replace(id::text,'-',''), 1, 8),
        display_name = 'Deleted account',
        avatar_url   = NULL,
        bio          = NULL,
        account_status = 'deleted'
    WHERE id = v_uid;

  -- Mark FCM token gone so any in-flight push doesn't reach this user.
  DELETE FROM private.profile_tokens WHERE user_id = v_uid;

  -- Queue the auth.users delete for an out-of-band worker (the
  -- admin_manage_user edge function picks these up).
  INSERT INTO public.account_delete_requests (user_id)
    VALUES (v_uid)
    ON CONFLICT (user_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.delete_own_account() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.delete_own_account() TO authenticated;

COMMENT ON TABLE public.account_delete_requests IS
  'Queue of users awaiting auth.users deletion. Drained out-of-band by '
  'admin_manage_user edge fn. See SEC-005.';
