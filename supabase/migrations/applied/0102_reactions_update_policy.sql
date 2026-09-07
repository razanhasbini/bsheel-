-- ============================================================
-- MIGRATION 0102: Allow users to switch their own vote
-- (imported from PR #30, originally authored as 0093)
--
-- The vote UI uses upsert on UNIQUE(submission_id, user_id) so changing
-- upvote <-> downvote is an UPDATE after the first vote. Existing RLS only
-- allowed INSERT/DELETE, so vote switches could fail after optimistic UI.
-- ============================================================

-- Idempotent: drop any prior version before re-creating, so re-running this
-- migration on a DB that already has the policy doesn't 42710-error.
DROP POLICY IF EXISTS "reactions_update_own" ON public.reactions;

CREATE POLICY "reactions_update_own"
  ON public.reactions
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
