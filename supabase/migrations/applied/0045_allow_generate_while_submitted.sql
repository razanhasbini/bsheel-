-- Migration 0045: Allow generating a new quest while another is submitted (in review)
-- The old index blocked having more than one quest with status 'assigned' OR 'submitted'.
-- Now only block on 'assigned' — submitted quests should not prevent new quest generation.

DROP INDEX IF EXISTS idx_one_active_quest_per_user;

CREATE UNIQUE INDEX idx_one_active_quest_per_user
  ON public.user_quests (user_id)
  WHERE status = 'assigned';
