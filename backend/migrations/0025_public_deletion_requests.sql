BEGIN;

-- Account-deletion requests submitted from the public, unauthenticated page.
--
-- The store-compliance page at admin.bsheel.app/delete-account is one of only
-- three routes reachable without a session, and its submit button made no
-- network call at all while telling the visitor "your request has been
-- received". A GDPR/CCPA erasure request was being dropped with a success
-- receipt on screen.
--
-- Deliberately NOT account_delete_requests: that table is keyed to a user id
-- and drives the authenticated flow, which actually erases data. This one
-- cannot, and must not — an unauthenticated endpoint that deletes an account
-- by email address would let anyone erase anyone. Rows here are a queue for an
-- operator to verify identity and then run the real flow.
CREATE TABLE public_deletion_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email citext NOT NULL,
  -- Whatever the visitor typed, for context. Not trusted, not acted on.
  note text CHECK (note IS NULL OR char_length(note) <= 2000),
  -- Set when an operator has verified the requester and started erasure.
  handled_at timestamptz,
  handled_by uuid REFERENCES users(id) ON DELETE SET NULL,
  -- Populated only when the address matches an account at request time, so the
  -- operator can see whether there is anything to erase without a lookup.
  matched_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- One open request per address. A visitor who submits twice should not create
-- a second row for the operator to work through; the repository upserts.
CREATE UNIQUE INDEX public_deletion_requests_open_email_idx
  ON public_deletion_requests (email)
  WHERE handled_at IS NULL;

-- The operator queue: oldest unhandled first.
CREATE INDEX public_deletion_requests_pending_idx
  ON public_deletion_requests (created_at)
  WHERE handled_at IS NULL;

COMMIT;
