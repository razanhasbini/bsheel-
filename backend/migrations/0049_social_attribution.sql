-- Virality attribution: which post a BSHEEEL (or a view, or a share) came from.
--
-- The event store knew that somebody pressed BSHEEEL on the feed. It did not
-- know which post they pressed it on, so "User A's post made User B do this
-- quest" was not a fact anyone could compute — the funnel's top half was
-- per quest and per surface, never per post. This column is the missing
-- link: the submission whose card the event was raised from.
--
-- Nullable, because most events have no source post: a quest opened from the
-- map, a BSHEEEL from the home roll. ON DELETE SET NULL, not CASCADE — the
-- event still happened and still counts for the quest's exposure; it merely
-- stops crediting a post that no longer exists.
--
-- Everything downstream — activations and verified completions credited to
-- a post — is a JOIN from here onto user_quests and submissions, the tables
-- that already own those facts. Nothing is copied into this table, so the
-- attribution can never drift from what actually happened.
BEGIN;

ALTER TABLE analytics_events
  ADD COLUMN IF NOT EXISTS source_submission_id uuid REFERENCES submissions(id) ON DELETE SET NULL;

COMMENT ON COLUMN analytics_events.source_submission_id IS
  'The post (submission) whose card this event was raised from, when there was one. '
  'Client-attested like the rest of the row. Activations and completions credited to '
  'a post are joined from user_quests/submissions at read time, never stored here.';

-- Per-post credit reads: everything raised from this post, by type.
CREATE INDEX IF NOT EXISTS analytics_events_source_idx
  ON analytics_events (source_submission_id, event_type)
  WHERE source_submission_id IS NOT NULL;

-- The attribution join: a BSHEEEL by this user on this quest, then the
-- assignment that followed it.
CREATE INDEX IF NOT EXISTS analytics_events_bsheeel_user_quest_idx
  ON analytics_events (user_id, quest_id, occurred_at)
  WHERE event_type = 'quest_bsheeel';

COMMIT;
