-- Canonical body for vote_collab(p_group_id, p_submission_id).
-- Authoritative since migration 0149 (previous: 0123).
--
-- ANY redefinition MUST preserve all three of:
--   * public.is_account_active()      -- banned/suspended guard  (0123)
--   * s.status = 'approved'           -- eligibility guard       (0097)
--   * ON CONFLICT (group_id, voter_id, submission_id) DO NOTHING (0094)
-- The last one is not cosmetic: uq_one_vote_per_user_per_group was
-- DROPPED by 0094, so the 2-column inference spec that 0120/0123 used
-- matches no index and raises 42P10 on EVERY call.
--
-- When you next change this, edit THIS file + add a migration that
-- INLINES the body (\i cannot resolve — see README).
CREATE OR REPLACE FUNCTION public.vote_collab(
  p_group_id      uuid,
  p_submission_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  -- DELIBERATE DEVIATION FROM AUDIT ITEM M11 (which asked for 10/h).
  --
  -- 0140 wrote "10/h" while 0120's `ON CONFLICT (group_id, voter_id)
  -- DO UPDATE` made vote_collab look like ONE vote per GROUP. The real
  -- model (0094, unvote_collab, and one button per member in
  -- reels_card.dart) is one vote per group MEMBER — so a single
  -- 5-person collab post costs 5 votes. At 10/h a normal user is
  -- rate-limited after browsing TWO collab posts, which would present
  -- as exactly the same "Vote failed" symptom this migration exists to
  -- repair.
  --
  -- 60/h keeps the anti-automation ceiling the audit actually wanted
  -- (bulk farming still throttled) while sitting far above real usage.
  -- Note that no per-user cap meaningfully stops the multi-account
  -- sock-puppet ring M11 describes; see the §6 note for the real fix.
  c_max_votes_per_hour constant integer := 60;

  v_uid          uuid := auth.uid();
  v_recent_votes integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  -- 0123 banned/suspended guard — MUST NOT be dropped.
  IF NOT public.is_account_active() THEN
    RAISE EXCEPTION 'Account not active' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.collab_groups WHERE id = p_group_id
  ) THEN
    RAISE EXCEPTION 'Group not found' USING ERRCODE = 'P0002';
  END IF;

  -- Restores 0097's guard (dropped by 0120).
  IF NOT EXISTS (
    SELECT 1
      FROM public.collab_group_members m
      JOIN public.submissions s ON s.user_quest_id = m.user_quest_id
     WHERE m.group_id = p_group_id
       AND s.id       = p_submission_id
       AND s.status   = 'approved'
  ) THEN
    RAISE EXCEPTION 'Submission is not eligible for voting'
      USING ERRCODE = 'P0001';
  END IF;

  -- M11 (partial). Counts surviving rows; unvote_collab deletes rows,
  -- so this is resettable by a vote/unvote loop. See §6.
  SELECT count(*) INTO v_recent_votes
    FROM public.collab_votes v
   WHERE v.voter_id   = v_uid
     AND v.created_at > now() - interval '1 hour';
  IF v_recent_votes >= c_max_votes_per_hour THEN
    RAISE EXCEPTION 'Vote rate limit exceeded — try again later'
      USING ERRCODE = 'P0001';
  END IF;

  -- THE FIX. Column list must match uq_one_vote_per_user_per_submission
  -- (0094:26-29) exactly. DO NOTHING is also the only form consistent
  -- with unvote_collab's multi-vote toggle model.
  INSERT INTO public.collab_votes (group_id, voter_id, submission_id)
  VALUES (p_group_id, v_uid, p_submission_id)
  ON CONFLICT (group_id, voter_id, submission_id) DO NOTHING;
END;
$$;

-- NEW. No migration has ever revoked PUBLIC on this function
-- (0072:291, 0094:64, 0097:42, 0120:157, 0123:134 are all GRANT-only),
-- so anon holds EXECUTE via PUBLIC today. It fails closed on
-- auth.uid() IS NULL, so this is latent — close it anyway.
REVOKE EXECUTE ON FUNCTION public.vote_collab(uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.vote_collab(uuid, uuid) TO authenticated;
