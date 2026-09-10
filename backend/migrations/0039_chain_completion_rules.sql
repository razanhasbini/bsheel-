BEGIN;

-- Sequential-group and cross-country chains, which `quest_chains.mode` has
-- claimed to support since 0024 without anything ever reading it (#51).
--
-- The bug this fixes: the step gate in quests.repository.ts requires the
-- PREVIOUS step to be approved *for the same user*. In a group chain the
-- previous step is by definition somebody else's, so step 2 could never open
-- for anyone and `mode = 'group'` was unreachable. Nothing failed loudly;
-- the chain simply stopped after step 1.
--
-- Two orthogonal questions were also being conflated, so they are separated
-- here:
--   mode            — WHOSE approval counts (this user, or any group member)
--   completion_rule — whether ORDER matters at all
--
-- A cross-country challenge is the combination the proposal describes:
-- group + all_steps_any_order, three participants in three countries, no
-- reason for Lebanon to have to go before Palestine.
ALTER TABLE quest_chains ADD COLUMN IF NOT EXISTS completion_rule text NOT NULL DEFAULT 'sequential'
  CHECK (completion_rule IN ('sequential', 'all_steps_any_order'));

COMMENT ON COLUMN quest_chains.completion_rule IS
  'sequential: step N needs step N-1 approved. all_steps_any_order: steps '
  'may be taken in any order and the chain completes when all are approved '
  '— which is what a cross-country challenge needs.';

COMMENT ON COLUMN quest_chains.mode IS
  'solo: the same user must have the previous step approved. group: any '
  'member of the collab group on this chain may have satisfied it, which is '
  'what makes a sequential-group relay work.';

-- Which collab group is running a group chain. Without this, "any member"
-- has no membership to check against.
ALTER TABLE quest_chains ADD COLUMN IF NOT EXISTS collab_group_id uuid
  REFERENCES collab_groups(id) ON DELETE SET NULL;

COMMENT ON COLUMN quest_chains.collab_group_id IS
  'The group running a group-mode chain. Null for solo chains.';

CREATE INDEX IF NOT EXISTS quest_chains_group_idx ON quest_chains (collab_group_id)
  WHERE collab_group_id IS NOT NULL;

COMMIT;
