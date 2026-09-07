-- ============================================================
-- MIGRATION 0091: delete_own_account RPC
-- Lets an authenticated user remove their own profile and all
-- associated rows. Required for GDPR and Apple 5.1.1(v) /
-- Google Play account-deletion compliance.
--
-- Strategy:
--   * Tables with FK to public.profiles(id) ON DELETE CASCADE
--     (user_quests, submissions, reactions, notifications,
--     admins, reports, blocked_users, saved_posts, fcm_tokens,
--     admin_quest_injections.target_user_id) are cleaned up
--     automatically when the profile row is deleted.
--   * Tables that reference auth.users(id) instead of profiles
--     (comments, follows, collab_* tables) do NOT cascade when
--     only the profile is deleted, so we clean them up
--     explicitly.
--   * admin_quest_injections.created_by is NOT NULL so any rows
--     the user created as an admin are deleted too.
--   * The auth.users row itself is NOT deleted here; that
--     requires service-role and is handled by the
--     admin_manage_user edge function or a cleanup job.
--     Deleting the profile row is sufficient to revoke all
--     further access because every RLS policy joins through it.
-- ============================================================

CREATE OR REPLACE FUNCTION public.delete_own_account()
RETURNS void AS $$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  -- Tables referencing auth.users(id) — no cascade from profiles.
  DELETE FROM public.comments       WHERE user_id = uid;
  DELETE FROM public.follows        WHERE follower_id = uid OR following_id = uid;
  DELETE FROM public.collab_votes   WHERE voter_id = uid;

  -- Deleting collab_groups cascades to its members + votes.
  DELETE FROM public.collab_group_members WHERE user_id = uid;
  DELETE FROM public.collab_groups        WHERE creator_id = uid;

  -- Injections the user authored as an admin (created_by is NOT NULL,
  -- SET NULL would fail, so remove explicitly).
  DELETE FROM public.admin_quest_injections WHERE created_by = uid;

  -- The profile row. Cascades take care of user_quests, submissions,
  -- reactions, notifications, admins, reports, blocked_users,
  -- saved_posts, fcm_tokens, and admin_quest_injections.target_user_id.
  DELETE FROM public.profiles WHERE id = uid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE ALL ON FUNCTION public.delete_own_account() FROM public;
GRANT EXECUTE ON FUNCTION public.delete_own_account() TO authenticated;
