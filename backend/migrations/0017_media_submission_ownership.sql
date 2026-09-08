-- Link ready submission media to the submission that references it.
-- submissions.media_url is a JSON string/array, so reclaim must not infer
-- ownership by comparing it as a scalar text value.
BEGIN;

ALTER TABLE media_objects
  ADD COLUMN IF NOT EXISTS submission_id uuid
  REFERENCES submissions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS media_objects_submission_idx
  ON media_objects (submission_id)
  WHERE submission_id IS NOT NULL;

COMMIT;
