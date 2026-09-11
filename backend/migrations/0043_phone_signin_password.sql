BEGIN;

-- A phone sign-up now sets a password, and that password has to survive the
-- carrier round-trip: the user types it on the signup form, the browser
-- leaves for the operator's consent page, and the account is only created
-- when Nokia confirms the number. The chosen password has nowhere to live
-- in between.
--
-- It is hashed at `phone/start` and only the hash is stored, so a dump of
-- this short-lived table never yields a password. The row is single-use and
-- expires in five minutes like the rest of the sign-in state.
ALTER TABLE phone_signin_states
  ADD COLUMN IF NOT EXISTS password_hash text;

COMMENT ON COLUMN phone_signin_states.password_hash IS
  'Argon2 hash of the password chosen at signup, applied to the account once the carrier verifies the number. Never plaintext.';

-- Phone is now a sign-in credential in its own right (phone + password), so
-- the lookup that used to be a rare admin query is on the hot login path.
-- Partial: soft-deleted rows are never a login target.
CREATE INDEX IF NOT EXISTS users_phone_number_active_idx
  ON users (phone_number)
  WHERE deleted_at IS NULL AND phone_number IS NOT NULL;

COMMIT;
