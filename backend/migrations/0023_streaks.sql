BEGIN;

-- Streaks (#46). A streak is the run of consecutive UTC days on which a user
-- has at least one APPROVED submission, counted by `submitted_at` — the day
-- they did the work — and never by `reviewed_at`.
--
-- Keying on the review date would make a moderator's backlog break a user's
-- streak, and the admin dashboard tracks queue ages in hours. A user cannot
-- clear that backlog, so it must not cost them anything.
--
-- Nothing is denormalised onto `profiles`. XP is stored and has drifted badly
-- enough to need a reconciliation screen (/xp); a second derived counter kept
-- in two places would earn a second such screen. The run is an indexed query
-- instead, so it cannot disagree with the submissions it is derived from.

-- Supports the gaps-and-islands query: one user's approved submission days,
-- newest first. `visibility` is included so a moderator takedown drops out of
-- the streak without a second lookup.
CREATE INDEX IF NOT EXISTS submissions_user_approved_day_idx
  ON submissions (user_id, submitted_at DESC)
  WHERE status = 'approved';

COMMENT ON INDEX submissions_user_approved_day_idx IS
  'Streak computation (#46): consecutive approved-submission days per user.';

-- The daily "your streak dies tonight" reminder must not fire twice in one
-- day, however many times the job runs or is retried. One date per user is
-- enough state to guarantee that, and it is cheap to reset.
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS streak_reminder_sent_on date;

COMMENT ON COLUMN profiles.streak_reminder_sent_on IS
  'UTC date of the last streak-at-risk reminder, so the daily job is idempotent.';

-- Finds users whose streak is alive but expires at the end of today, skipping
-- anyone already reminded. Partial on the column being null is not useful
-- (it is set for most users most days), so this is a plain composite.
CREATE INDEX IF NOT EXISTS profiles_streak_reminder_idx
  ON profiles (streak_reminder_sent_on);

COMMIT;
