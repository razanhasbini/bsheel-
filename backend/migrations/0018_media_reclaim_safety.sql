BEGIN;

-- A file can appear in several submissions (including multi-file proofs).
-- Retain links for soft-deleted submissions: moderation can restore them.
CREATE TABLE media_submission_links (
  media_object_id uuid NOT NULL REFERENCES media_objects(id) ON DELETE CASCADE,
  submission_id uuid NOT NULL REFERENCES submissions(id) ON DELETE CASCADE,
  PRIMARY KEY (media_object_id, submission_id)
);
CREATE INDEX media_submission_links_submission_idx ON media_submission_links (submission_id);

-- Parse old scalar/JSON-array references deliberately. Malformed arrays fail
-- migration instead of silently classifying possibly referenced files as orphans.
CREATE FUNCTION pg_temp.submission_media_keys(raw text) RETURNS text[]
LANGUAGE plpgsql AS $$
DECLARE parsed jsonb;
BEGIN
  IF left(ltrim(raw), 1) <> '[' THEN RETURN ARRAY[btrim(raw)]; END IF;
  parsed := raw::jsonb;
  IF jsonb_typeof(parsed) <> 'array' OR EXISTS (
    SELECT 1 FROM jsonb_array_elements(parsed) value WHERE jsonb_typeof(value) <> 'string'
  ) THEN RAISE EXCEPTION 'Invalid legacy submission media reference'; END IF;
  RETURN ARRAY(SELECT btrim(value) FROM jsonb_array_elements_text(parsed) value);
END;
$$;

INSERT INTO media_submission_links (media_object_id, submission_id)
SELECT m.id, s.id FROM submissions s
CROSS JOIN LATERAL unnest(pg_temp.submission_media_keys(s.media_url)) reference(object_key)
JOIN media_objects m ON m.object_key = reference.object_key
ON CONFLICT DO NOTHING;
INSERT INTO media_submission_links (media_object_id, submission_id)
SELECT id, submission_id FROM media_objects WHERE submission_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- A durable tombstone closes the upload/bind lifecycle BEFORE deleting bytes.
-- Leases distribute work; an expired lease never reopens the tombstone.
ALTER TABLE media_objects
  ADD COLUMN upload_expires_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN reclaim_started_at timestamptz,
  ADD COLUMN reclaim_lease_until timestamptz,
  ADD COLUMN reclaim_token uuid,
  ADD COLUMN reclaim_reason text,
  ADD COLUMN storage_deleted_at timestamptz;

-- Old signed PUT grants were not recorded. Protect them for S3's maximum
-- seven-day validity once during migration, including previously deleted rows.
UPDATE media_objects SET upload_expires_at = now() + interval '7 days';
UPDATE media_objects SET reclaim_started_at = now(), reclaim_reason = 'user_deleted'
WHERE status = 'deleted';
CREATE INDEX media_objects_reclaim_retry_idx ON media_objects (reclaim_lease_until)
WHERE reclaim_started_at IS NOT NULL AND storage_deleted_at IS NULL;

COMMIT;
