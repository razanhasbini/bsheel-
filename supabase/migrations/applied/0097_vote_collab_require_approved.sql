-- ============================================================
-- MIGRATION 0097: Tighten vote_collab to require an approved
-- submission. Defense-in-depth — the client only renders
-- approved+submitted members, but voting on a pending or
-- rejected submission via a guessed UUID was structurally
-- possible after 0094 (public per-member voting opened the
-- check from "members of versus group only" to "any auth'd
-- user"). Re-add the status guard.
-- ============================================================

CREATE OR REPLACE FUNCTION public.vote_collab(
  p_group_id uuid,
  p_submission_id uuid
) RETURNS void AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.collab_groups WHERE id = p_group_id) THEN
    RAISE EXCEPTION 'Group not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.collab_group_members m
    JOIN public.submissions s ON s.user_quest_id = m.user_quest_id
    WHERE m.group_id = p_group_id
      AND s.id = p_submission_id
      AND s.status = 'approved'
  ) THEN
    RAISE EXCEPTION 'Submission is not eligible for voting'
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.collab_votes (group_id, voter_id, submission_id)
  VALUES (p_group_id, auth.uid(), p_submission_id)
  ON CONFLICT (group_id, voter_id, submission_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.vote_collab(uuid, uuid) TO authenticated;
