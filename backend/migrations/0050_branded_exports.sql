-- Branded video export: the Bsheel band burned into the exported file.
--
-- Photos leave the app with the quest / date / place band composited on the
-- phone. Videos could not: compositing onto video is a transcode, which is a
-- dependency and a long wait on a handset, so a shared video carried the
-- template only as accompanying text. The worker already has ffmpeg (it cuts
-- video proof into frames for AI verification), so the render moves there —
-- one job per submission, the result stored beside the original and served
-- through the same signed-URL path as every other private object.
--
-- One export per submission, not per requester: the band is a fact about
-- the post (quest, author, date, place), so two people sharing the same post
-- want the same file. The unique index is what makes a second request return
-- the first's row instead of a second render.
BEGIN;

CREATE TABLE IF NOT EXISTS branded_exports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  submission_id uuid NOT NULL REFERENCES submissions(id) ON DELETE CASCADE,
  -- Who asked first. Informational: the export belongs to the post.
  requested_by uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'rendering', 'ready', 'failed')),
  -- Where the rendered file lives once ready; the same private bucket as
  -- the original, under exports/.
  object_key text,
  error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS branded_exports_submission_idx ON branded_exports (submission_id);

COMMENT ON TABLE branded_exports IS
  'Server-rendered copies of a submission''s video with the Bsheel quest/date/place band '
  'burned in (ffmpeg, on the worker). One per submission; served through signed URLs.';

COMMIT;
