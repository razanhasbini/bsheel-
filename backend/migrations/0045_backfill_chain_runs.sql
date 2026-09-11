BEGIN;

-- Chains already under way when 0044 landed.
--
-- Without this an assignment that legitimately existed before the run table
-- becomes a dead end: step 1 approved, no run, so the progression consumer
-- has nothing to advance and step 2 never opens. The journey would simply
-- stop, and the player would have no way to tell why.
--
-- SOLO ONLY. A relay's roster cannot be reconstructed from history — the
-- order participants were meant to act in is not recoverable from
-- user_quests, and inventing one would silently hand somebody else's
-- checkpoint to the wrong person. Both group chains currently have zero
-- user_quests, so nothing is stranded by leaving them alone; if that ever
-- changes, the correct fix is for the participants to start a fresh run.
INSERT INTO quest_chain_runs (chain_id, run_kind, owner_user_id, created_by_user_id, status, started_at)
SELECT DISTINCT cs.chain_id, 'solo', uq.user_id, uq.user_id, 'active', min(uq.assigned_at) OVER (PARTITION BY cs.chain_id, uq.user_id)
FROM user_quests uq
JOIN quest_chain_steps cs ON cs.quest_id = uq.quest_id
JOIN quest_chains ch ON ch.id = cs.chain_id AND ch.mode = 'solo'
WHERE uq.status IN ('assigned', 'submitted', 'approved')
ON CONFLICT DO NOTHING;

-- Open the checkpoint each backfilled run is actually standing on.
--
-- Sequential: the step after the highest approved one. Any-order: every step
-- not yet approved, because that rule gates nothing and all of them are
-- legitimately available at once.
INSERT INTO journey_stage_unlocks (chain_run_id, step_order, quest_id, target_user_id)
SELECT r.id, cs.step_order, cs.quest_id, r.owner_user_id
FROM quest_chain_runs r
JOIN quest_chains ch ON ch.id = r.chain_id
JOIN quest_chain_steps cs ON cs.chain_id = r.chain_id
WHERE r.run_kind = 'solo'
  AND r.status = 'active'
  -- Not already finished by this user.
  AND NOT EXISTS (
    SELECT 1 FROM user_quests done
    WHERE done.quest_id = cs.quest_id AND done.user_id = r.owner_user_id
      AND done.status = 'approved'
  )
  AND (
    ch.completion_rule = 'all_steps_any_order'
    OR cs.step_order = 1 + COALESCE((
      SELECT max(prev.step_order)
      FROM quest_chain_steps prev
      JOIN user_quests puq ON puq.quest_id = prev.quest_id
      WHERE prev.chain_id = r.chain_id AND puq.user_id = r.owner_user_id
        AND puq.status = 'approved'
    ), 0)
  )
ON CONFLICT DO NOTHING;

-- A run whose every step is already approved was completed before the table
-- existed. Close it rather than leave a finished journey looking active.
UPDATE quest_chain_runs r SET status = 'completed', completed_at = now(), updated_at = now()
WHERE r.status = 'active'
  AND NOT EXISTS (
    SELECT 1 FROM quest_chain_steps cs
    WHERE cs.chain_id = r.chain_id
      AND NOT EXISTS (
        SELECT 1 FROM user_quests uq
        WHERE uq.quest_id = cs.quest_id AND uq.user_id = r.owner_user_id
          AND uq.status = 'approved'
      )
  );

-- Retire the duplicated chain dependency (#5 of the review).
--
-- quest_chain_steps.step_order is the single authority for chain
-- progression; these rows said the same thing a second time and nothing
-- read them. Scoped to the EXACT generated pattern — a prerequisite
-- pointing at the immediately preceding step of the SAME chain — so a
-- genuine hidden-quest prerequisite that happens to sit on a chain quest is
-- left alone.
DELETE FROM quest_unlock_rules r
USING quest_chain_steps cs, quest_chain_steps prev
WHERE r.unlock_type = 'prerequisite_quest'
  AND cs.quest_id = r.quest_id
  AND prev.quest_id = r.prerequisite_quest_id
  AND prev.chain_id = cs.chain_id
  AND prev.step_order = cs.step_order - 1;

COMMIT;
