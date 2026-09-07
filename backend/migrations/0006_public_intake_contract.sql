ALTER TABLE quest_suggestions DROP CONSTRAINT IF EXISTS quest_suggestions_status_check;
UPDATE quest_suggestions SET status = 'approved' WHERE status = 'accepted';
ALTER TABLE quest_suggestions
  ADD CONSTRAINT quest_suggestions_status_check
  CHECK (status IN ('pending', 'approved', 'rejected'));

ALTER TABLE quest_suggestions
  ALTER COLUMN description SET NOT NULL,
  ALTER COLUMN category SET NOT NULL,
  ALTER COLUMN difficulty SET NOT NULL;
