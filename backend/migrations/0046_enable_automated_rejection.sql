-- Automated rejection, enabled where the media can actually settle the quest.
--
-- 0034 seeded `may_auto_reject` false for every category on the reasoning
-- that authority to tell a player their proof is fake should be earned from a
-- measured precision number rather than asserted in a migration. The gate
-- worked exactly as written, and the cost of it became the problem: every
-- submission the agent judged — including one it was 99% sure was a desktop
-- screenshot with 1% relevance to the quest — went to a human queue carrying
-- the agent's own correct conclusion, for a person to reach again by hand.
-- A player waited days for an answer the system already had.
--
-- So this flips it where the question is one the media answers, and only
-- there. `verifiability` is what separates those cases, and it is the same
-- column that already stops the agent being asked an incoherent question:
--
--   content          -> the asked-for thing is visible when it is there, so
--                       its absence is a finding. Rejection permitted.
--   provenance_only  -> nothing the player did is visible; a rejection could
--                       only rest on the file's provenance, which is the one
--                       accusation most worth a human. Unchanged.
--   none             -> nothing about a photograph bears on the task at all.
--                       Rejection here would be incoherent. Unchanged.
--
-- Approval authority is untouched; it was already granted in 0034.
--
-- Per-quest overrides (quests.may_auto_reject) are untouched and still win:
-- this moves the default under them, so a quest explicitly set either way
-- keeps what it was set to. The three quests set true by hand during testing
-- stay true and now agree with their category.
UPDATE quest_verification_defaults
   SET may_auto_reject = true
 WHERE verifiability = 'content';

COMMENT ON COLUMN quest_verification_defaults.may_auto_reject IS
  'Whether the agent may reject without a human on this category. True for '
  'content-verifiable categories, where the absence of the asked-for thing is '
  'a finding the media supports; false where a photograph cannot establish '
  'the task and a rejection could only be an accusation about the file.';
