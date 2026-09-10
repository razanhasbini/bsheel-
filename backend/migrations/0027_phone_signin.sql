BEGIN;

-- Phone-first sign-in via CAMARA Number Verification (issue #1). Until this
-- migration, users.email was NOT NULL — every account needed an email. A
-- user who signs in with only a verified phone number has no email at all,
-- so the identity model widens: an account now needs email OR a verified
-- phone number, not both.

ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_number citext;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_verified_at timestamptz;

-- citext already case/format-normalizes for uniqueness the way email does;
-- E.164 formatting is enforced at the application layer (CAMARA always
-- returns E.164), same division of labor as email's existing citext column.
ALTER TABLE users ADD CONSTRAINT users_phone_number_unique UNIQUE (phone_number);

ALTER TABLE users DROP CONSTRAINT IF EXISTS password_or_external_identity;
ALTER TABLE users ADD CONSTRAINT users_has_a_credential CHECK (
  password_hash IS NOT NULL OR email_verified_at IS NOT NULL OR phone_verified_at IS NOT NULL
);
ALTER TABLE users ADD CONSTRAINT users_email_or_phone_present CHECK (
  email IS NOT NULL OR phone_number IS NOT NULL
);
ALTER TABLE users ADD CONSTRAINT users_phone_requires_verification CHECK (
  phone_number IS NULL OR phone_verified_at IS NOT NULL
);

ALTER TABLE auth_identities DROP CONSTRAINT IF EXISTS auth_identities_provider_check;
ALTER TABLE auth_identities ADD CONSTRAINT auth_identities_provider_check
  CHECK (provider IN ('password', 'google', 'apple', 'phone'));

-- Server-side state for the CAMARA Number Verification 3-legged flow. A row
-- is created when the redirect starts and consumed exactly once at the
-- callback; a second, short-lived handoff_code then hands the result to the
-- mobile app over a normal authenticated POST rather than embedding tokens
-- in a redirect URL.
CREATE TABLE phone_signin_states (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  state              text NOT NULL,
  intent             text NOT NULL CHECK (intent IN ('sign_in', 'link')),
  -- Required when intent = 'link' (linking to the already-signed-in caller);
  -- null for 'sign_in', where the account isn't known until the callback.
  user_id            uuid REFERENCES users(id) ON DELETE CASCADE,
  age_verified       boolean NOT NULL DEFAULT false,
  redirect_uri       text NOT NULL,
  status             text NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'completed', 'consumed', 'failed')),
  handoff_code       text,
  result_user_id     uuid REFERENCES users(id) ON DELETE CASCADE,
  expires_at         timestamptz NOT NULL,
  handoff_expires_at timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now()
);
-- Partial uniqueness: only one *pending* row may own a given state/handoff
-- value at a time, so a completed or failed row never blocks a fresh retry
-- from reusing the same random value (astronomically unlikely, but free to
-- guard against rather than assume away).
CREATE UNIQUE INDEX phone_signin_states_state_idx
  ON phone_signin_states (state) WHERE status = 'pending';
CREATE UNIQUE INDEX phone_signin_states_handoff_idx
  ON phone_signin_states (handoff_code) WHERE status = 'completed';
CREATE INDEX phone_signin_states_expiry_idx ON phone_signin_states (expires_at);

COMMENT ON COLUMN users.phone_number IS 'E.164. Present only once phone_verified_at is set by a completed CAMARA Number Verification flow.';
COMMENT ON TABLE phone_signin_states IS 'Server-side state for the CAMARA Number Verification redirect flow (issue #1). One row per attempt; the handoff_code hands the result to the mobile app without ever putting tokens in a URL.';

COMMIT;
