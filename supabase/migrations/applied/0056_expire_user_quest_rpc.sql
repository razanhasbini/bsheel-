-- ============================================================
-- MIGRATION 0056: User-callable quest expiry RPC (H3)
-- Allows the owning user to expire their own assigned quest.
-- Replaces broken direct UPDATE which is blocked by RLS.
-- ============================================================

CREATE OR REPLACE FUNCTION public.expire_user_quest(p_user_quest_id uuid)
RETURNS void AS $$
BEGIN
  -- Validate ownership and status
  UPDATE public.user_quests
    SET status = 'expired'
    WHERE id = p_user_quest_id
      AND user_id = auth.uid()
      AND status = 'assigned';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Quest not found, not owned by you, or not in assigned status';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.expire_user_quest(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.expire_user_quest(uuid) TO authenticated;
