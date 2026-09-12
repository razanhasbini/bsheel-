BEGIN;

-- Poster frames for video proof.
--
-- The map's moments layer draws a square per approved submission. For a photo
-- that square is the photograph; for a video it was a play glyph on the
-- quest's category tint, because nothing in this system had ever decoded a
-- frame for display. On a board of mostly-green squares a video moment read
-- as a rendering bug rather than as a video — and the layer's whole job is to
-- make somebody want to tap it.
--
-- A poster is a derived asset, not a second submission, and the distinction
-- matters in two places:
--
--   * `media_object_kind` gets its own value rather than reusing 'submission'.
--     The forensics indexes (content_md5, etag, perceptual_hash) are all
--     partial on kind = 'submission', so a poster filed as one would be
--     hashed into the duplicate-detection space and could collide with a
--     real photograph — accusing somebody of stealing proof with a frame we
--     generated ourselves.
--   * the poster is linked through `media_submission_links`, so
--     `MediaRepository.authorizeKeys` grants it under the submission's own
--     visibility predicate with no new branch. A poster is exactly as public
--     as the video it was cut from, automatically and permanently.
ALTER TYPE media_object_kind ADD VALUE IF NOT EXISTS 'poster';

ALTER TABLE submissions
  ADD COLUMN IF NOT EXISTS poster_object_key text;

COMMENT ON COLUMN submissions.poster_object_key IS
  'Object key of a still frame cut from a video submission, for map tiles and '
  'any other surface that needs a picture rather than a player. NULL is an '
  'ordinary state: a photo submission has none, and so does a video whose '
  'frame could not be decoded or which was uploaded before this existed.';

-- Only video submissions ever have one, and only one job writes it.
CREATE INDEX IF NOT EXISTS submissions_poster_pending_idx
  ON submissions (submitted_at)
  WHERE media_type = 'video' AND poster_object_key IS NULL AND deleted_at IS NULL;

COMMIT;
