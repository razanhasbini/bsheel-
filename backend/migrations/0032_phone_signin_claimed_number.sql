BEGIN;

-- Number Verification V1 (CAMARA `POST /number-verification/v0/verify`)
-- answers a yes/no question: "is the number the user CLAIMED the same one
-- this authenticated device is actually using?" So V1 needs the claimed
-- number as input, unlike V2's device-phone-number call which returns the
-- number outright and needs no claim.
--
-- The claim is captured when the flow starts and pinned to the same
-- single-use state row, so the number that gets verified is the number the
-- user typed before the redirect — not something an attacker can swap in on
-- the callback. A phone number is only ever trusted after Nokia returns
-- devicePhoneNumberVerified = true for the value stored here.
--
-- Nullable: rows created before this migration have no claim, and the
-- callback fails those closed rather than silently verifying nothing.
ALTER TABLE phone_signin_states ADD COLUMN IF NOT EXISTS claimed_phone_number text;

COMMENT ON COLUMN phone_signin_states.claimed_phone_number IS
  'E.164 number the user claimed at the start of this attempt; the value Number Verification V1 checks the device against.';

COMMIT;
