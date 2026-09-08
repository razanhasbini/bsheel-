BEGIN;

-- Database-maintained so imports, account deletion and every reaction writer agree.
ALTER TABLE submissions ADD COLUMN net_score bigint NOT NULL DEFAULT 0;
UPDATE submissions s SET net_score = r.score
FROM (SELECT submission_id, sum(CASE WHEN type = 'upvote' THEN 1 ELSE -1 END) AS score
      FROM reactions GROUP BY submission_id) r WHERE r.submission_id = s.id;

CREATE FUNCTION maintain_submission_net_score() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.submission_id = OLD.submission_id THEN
    UPDATE submissions SET net_score = net_score
      + CASE WHEN NEW.type = 'upvote' THEN 1 ELSE -1 END
      - CASE WHEN OLD.type = 'upvote' THEN 1 ELSE -1 END
    WHERE id = NEW.submission_id;
  ELSE
    IF TG_OP <> 'INSERT' THEN
      UPDATE submissions SET net_score = net_score - CASE WHEN OLD.type = 'upvote' THEN 1 ELSE -1 END
      WHERE id = OLD.submission_id;
    END IF;
    IF TG_OP <> 'DELETE' THEN
      UPDATE submissions SET net_score = net_score + CASE WHEN NEW.type = 'upvote' THEN 1 ELSE -1 END
      WHERE id = NEW.submission_id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;
CREATE TRIGGER reactions_net_score AFTER INSERT OR UPDATE OR DELETE ON reactions
FOR EACH ROW EXECUTE FUNCTION maintain_submission_net_score();

CREATE INDEX submissions_feed_top_idx ON submissions (net_score DESC, submitted_at DESC, id DESC)
WHERE status = 'approved' AND show_in_feed AND visibility = 'visible' AND deleted_at IS NULL;
CREATE INDEX submissions_feed_bottom_idx ON submissions (net_score ASC, submitted_at DESC, id DESC)
WHERE status = 'approved' AND show_in_feed AND visibility = 'visible' AND deleted_at IS NULL;
COMMIT;
