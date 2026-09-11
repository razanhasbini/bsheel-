BEGIN;

-- Where a user signed up from, so "EXPLORE …" can name their own country.
--
-- Derived from the phone number rather than asked for, because the phone is
-- already mandatory and already carrier-verified: the dialling code is a
-- fact the network confirmed, where a signup dropdown would be a claim. It
-- also means no new question on a form that is deliberately two fields.
--
-- Nullable on purpose. A number whose dialling code we do not map — and the
-- +999 simulator range, which belongs to no country at all — leaves this
-- null, and discovery falls back to wherever the catalogue is richest rather
-- than guessing a country at the user.
ALTER TABLE users ADD COLUMN IF NOT EXISTS signup_country_code char(2)
  REFERENCES map_countries(code) ON DELETE SET NULL;

COMMENT ON COLUMN users.signup_country_code IS
  'Resolved from the verified phone dialling code at signup. Null when the '
  'code maps to no seeded country, including the +999 simulator range.';

CREATE INDEX IF NOT EXISTS users_signup_country_idx ON users (signup_country_code)
  WHERE signup_country_code IS NOT NULL;

COMMIT;
