BEGIN;

-- Optional email captured on the phone-first signup form.
--
-- Phone is the mandatory credential (migration 0027 made users.email
-- nullable for exactly this); an email is a convenience the user may add so
-- the account has a contact address and a recovery path. It is carried on
-- the single-use state row so it survives the CAMARA redirect, and it is
-- only written to the account once the phone number itself verifies —
-- an unverified attempt must not be able to claim an address.
--
-- No uniqueness here: the users table already owns that rule, and a
-- collision is resolved at account-creation time by simply not setting the
-- address rather than failing a sign-in that is otherwise legitimate.
ALTER TABLE phone_signin_states ADD COLUMN IF NOT EXISTS claimed_email citext;

COMMENT ON COLUMN phone_signin_states.claimed_email IS
  'Optional email offered at signup; applied to the account only after the phone number verifies, and only if still free.';

COMMIT;
