BEGIN;

ALTER TABLE submissions ADD COLUMN moderation_removed_at timestamptz;

-- Existing moderation audit records are authoritative; an author must not be
-- able to restore an older takedown after this migration either.
UPDATE submissions s SET moderation_removed_at = removal.created_at
FROM (
  SELECT target_id, max(created_at) AS created_at
  FROM admin_audit_log WHERE action = 'post.remove' AND target_type = 'submission'
  GROUP BY target_id
) removal
WHERE removal.target_id = s.id::text;

COMMIT;
