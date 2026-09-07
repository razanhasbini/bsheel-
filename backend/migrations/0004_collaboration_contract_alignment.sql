ALTER TYPE collab_mode RENAME VALUE 'against' TO 'versus';
ALTER TYPE collab_status ADD VALUE IF NOT EXISTS 'closed';

ALTER TABLE collab_votes
  DROP CONSTRAINT IF EXISTS collab_votes_group_id_voter_id_key;
ALTER TABLE collab_votes
  ADD CONSTRAINT collab_votes_group_voter_submission_key
  UNIQUE (group_id, voter_id, submission_id);

CREATE INDEX collab_votes_voter_group_idx ON collab_votes (voter_id, group_id);
