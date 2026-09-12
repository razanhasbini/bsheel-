-- How a journey reaches the feed: one post per stop, or one post for the route.
--
-- A three-stop route produced three feed posts, one per checkpoint, and there
-- was no way to ask for anything else. The stops are a single story — a player
-- who walked a route wants to show the route, not three unrelated photographs
-- separated by however long each checkpoint took to approve.
--
-- Nullable on purpose, and this is the whole point of the column: NULL means
-- the player has not been asked yet, which is a different state from having
-- chosen per-stop. The client asks once, at the start of the journey; until
-- then behaviour is per-stop, because that is what every existing run has been
-- doing and a migration must not silently retitle anyone's feed.
ALTER TABLE quest_chain_runs
  ADD COLUMN IF NOT EXISTS feed_mode text
    CHECK (feed_mode IS NULL OR feed_mode IN ('per_stop', 'one_post'));

COMMENT ON COLUMN quest_chain_runs.feed_mode IS
  'Chosen once at the start of a run. per_stop: every checkpoint posts as it '
  'is approved. one_post: checkpoints are withheld from the feed and the final '
  'one carries the whole route as a single post. NULL: not asked yet, behaves '
  'as per_stop.';

-- Which submission carries a one_post run, and which are its stops.
--
-- Deliberately not a new kind of feed row. The feed already assembles one post
-- from several submissions for collab groups — an anchor that appears in the
-- ranking and members attached to it — and everything downstream (comments,
-- reactions, saves, moderation, takedown) keys on that anchor's submission id.
-- A second mechanism for the same shape would have to re-earn all of it.
--
-- So the final checkpoint's submission is the anchor, the earlier ones are its
-- stops, and they stay ordinary submissions: independently verified,
-- independently appealable, with their own agent evidence and their own media.
-- Nothing about a submission is rewritten to build the post.
CREATE TABLE IF NOT EXISTS journey_post_stops (
  anchor_submission_id uuid NOT NULL REFERENCES submissions(id) ON DELETE CASCADE,
  stop_submission_id   uuid NOT NULL REFERENCES submissions(id) ON DELETE CASCADE,
  chain_run_id         uuid NOT NULL REFERENCES quest_chain_runs(id) ON DELETE CASCADE,
  step_order           integer NOT NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (anchor_submission_id, stop_submission_id)
);

-- The feed reads every stop of an anchor in step order, on every post it draws.
CREATE INDEX IF NOT EXISTS journey_post_stops_anchor_idx
  ON journey_post_stops (anchor_submission_id, step_order);

-- One anchor per run: publishing twice would put the same route in the feed
-- twice, and the completion handler is retried.
CREATE UNIQUE INDEX IF NOT EXISTS journey_post_stops_run_idx
  ON journey_post_stops (chain_run_id, step_order);
