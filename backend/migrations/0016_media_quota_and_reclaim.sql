-- Per-user media quota, and indexes for reclaiming unreferenced objects.
--
-- Both capabilities existed only in the deleted Cloudflare worker, and both
-- were implemented there by LISTing the R2 bucket: the quota listed a user's
-- prefix on every single upload, and the sweeper listed the whole bucket.
-- That is O(objects) network round-trips for work the database can answer
-- from an index, and it does not scale past a small bucket.
--
-- `media_objects` already tracks every object's lifecycle, so both become
-- ordinary indexed queries. These indexes are what make them cheap.

BEGIN;

-- Quota counting: "how many live objects of this kind does this user own".
-- The existing media_objects_user_created_idx leads with user_id but then
-- created_at, so it cannot filter on kind without a heap visit per row.
-- Partial on the live rows because a deleted object must not count against
-- the quota — otherwise a user who deletes and re-uploads stays capped.
CREATE INDEX IF NOT EXISTS media_objects_user_kind_live_idx
  ON media_objects (user_id, kind)
  WHERE deleted_at IS NULL AND status <> 'deleted';

-- Reclaim pass 1: objects that were rejected at completion, or whose storage
-- delete failed. `complete()` deletes the bytes then marks the row rejected,
-- so a row in this state with bytes still present means that delete failed.
-- Retrying it is the whole point of a sweep.
CREATE INDEX IF NOT EXISTS media_objects_rejected_idx
  ON media_objects (created_at)
  WHERE status = 'rejected';

-- Reclaim pass 2: superseded avatars. A profile holds exactly one
-- avatar_url, so every avatar change orphans the previous object. Before
-- this, each change leaked one object forever.
CREATE INDEX IF NOT EXISTS media_objects_ready_avatar_idx
  ON media_objects (user_id, created_at)
  WHERE status = 'ready' AND kind = 'avatar' AND deleted_at IS NULL;

-- Reclaim pass 3 support: ready submission objects, oldest first, so the
-- sweep can walk them in bounded batches rather than scanning the table.
CREATE INDEX IF NOT EXISTS media_objects_ready_submission_idx
  ON media_objects (created_at)
  WHERE status = 'ready' AND kind = 'submission' AND deleted_at IS NULL;

-- `profiles.avatar_url` is compared against an object key in the avatar
-- sweep. It holds a single key, never a JSON array, so equality is exact.
CREATE INDEX IF NOT EXISTS profiles_avatar_url_idx
  ON profiles (avatar_url)
  WHERE avatar_url IS NOT NULL;

COMMIT;
