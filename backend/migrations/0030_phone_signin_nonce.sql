BEGIN;

-- OpenID nonce for the Number Verification authorization request, stored
-- next to the one-time state it belongs to. Sent on the authorize URL and
-- kept so the value can be checked against an ID token if Nokia's flow
-- returns one — the state row is already single-use, so this is defence in
-- depth against a replayed authorization response rather than the only
-- guard.
--
-- Nullable: rows created before this migration have no nonce, and the
-- callback treats a missing stored nonce as "nothing to compare" rather
-- than failing a sign-in that was already in flight.
ALTER TABLE phone_signin_states ADD COLUMN IF NOT EXISTS nonce text;

COMMENT ON COLUMN phone_signin_states.nonce IS
  'OpenID nonce sent on the authorization request for this attempt.';

COMMIT;
