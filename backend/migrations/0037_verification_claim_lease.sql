BEGIN;

-- A lease on the vision pass, so two workers cannot pay for the same
-- photograph twice (#47).
--
-- `claim()` was never a lease. It is an UPDATE that increments `attempts`
-- and sets `state = 'queued'` where the state is already 'queued' or
-- 'failed' — which means the state a row sits in *while being analysed* is
-- indistinguishable from the state it sits in while waiting. Two callers
-- therefore both succeed: the second one's UPDATE blocks on the row lock,
-- then reads a row still marked 'queued' (the first has not finished) and
-- claims it as well.
--
-- Two callers is the normal case, not a rare one. The `submission.created`
-- consumer runs the pass inline, and the catch-up sweep walks everything
-- still 'queued' or 'failed' every 15 minutes. A pass that takes longer than
-- the sweep's next tick — a video with several sampled frames going to the
-- deep rung — is claimed a second time while the first is still running.
--
-- What that costs: two grammar-constrained vision calls on the same bytes,
-- at the top of a ladder whose rungs differ ~50x in price, and two
-- `complete()` writes racing to be the stored verdict. Nothing is corrupted
-- — last write wins and both are opinions about the same image — but it is
-- the most expensive thing this feature does, done twice for no reason.
--
-- `claimed_at` is the missing fact. A row whose claim is younger than the
-- lease is being worked on by someone; anything older is presumed abandoned
-- and may be taken, which is what keeps a worker killed mid-analysis from
-- stranding the submission forever.
--
-- Deliberately a timestamp rather than a new 'analysing' state. The state
-- column is in a CHECK constraint that four code paths and a partial index
-- already read, and a lease needs an expiry anyway — a state alone cannot
-- say "claimed, but so long ago that nobody is coming back".

ALTER TABLE submission_verifications
  ADD COLUMN IF NOT EXISTS claimed_at timestamptz;

COMMENT ON COLUMN submission_verifications.claimed_at IS
  'When a worker last took this row for analysis (#47). A claim younger than '
  'AI_VERIFICATION_CLAIM_LEASE_SECONDS means someone is working on it; older '
  'is presumed abandoned and reclaimable. Null means never claimed. This is '
  'what stops the inline consumer and the catch-up sweep paying for the same '
  'vision call twice.';

-- No index change. `submission_verifications_pending_idx` from 0033 already
-- covers exactly `(queued_at) WHERE state IN ('queued','failed')`, which is
-- still the sweep's driving predicate; the lease is an extra filter on rows
-- that index already returns, and the query has to touch the heap for
-- `attempts` regardless. Adding `claimed_at` as an INCLUDE would be churn
-- justified by a guess rather than a measurement.

COMMIT;
