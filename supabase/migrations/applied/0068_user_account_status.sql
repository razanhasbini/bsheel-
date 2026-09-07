-- ============================================================
-- MIGRATION 0068: User account status (L4 — Ban/Suspend)
-- Adds account_status to profiles: active, suspended, banned.
-- ============================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS account_status text NOT NULL DEFAULT 'active'
  CONSTRAINT account_status_check CHECK (account_status IN ('active', 'suspended', 'banned'));

-- RPC for admins to set user account status
CREATE OR REPLACE FUNCTION public.set_user_account_status(
  p_user_id uuid,
  p_status  text
)
RETURNS void AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF p_status NOT IN ('active', 'suspended', 'banned') THEN
    RAISE EXCEPTION 'Invalid status: %', p_status;
  END IF;

  UPDATE public.profiles
    SET account_status = p_status
    WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User not found';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.set_user_account_status(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_user_account_status(uuid, text) TO authenticated;

-- RPC for mobile app to check own account status on login
CREATE OR REPLACE FUNCTION public.get_my_account_status()
RETURNS text AS $$
BEGIN
  RETURN (SELECT account_status FROM public.profiles WHERE id = auth.uid());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

REVOKE EXECUTE ON FUNCTION public.get_my_account_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_account_status() TO authenticated;
