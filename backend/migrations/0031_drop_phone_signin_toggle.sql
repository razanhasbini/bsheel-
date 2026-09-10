BEGIN;

-- Retires the `phone_signin_enabled` switch added in 0028.
--
-- Phone verification is not a feature that can be turned off: every Bsheel
-- account is anchored to a CAMARA-verified number, because that number is
-- the device identifier the location APIs check a submission against. A
-- switch that disables it would leave accounts that no location-based quest
-- can ever be verified for, so the switch itself was the bug.
--
-- 0028 is left in place (migrations are forward-only and immutable once
-- applied); this simply removes the row it seeded. Availability now derives
-- from CAMARA_API_KEY being present on the backend, validated at boot.
DELETE FROM app_config WHERE key = 'phone_signin_enabled';

COMMIT;
