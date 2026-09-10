BEGIN;

-- Tell the truth about what `maintenance_mode` does.
--
-- Migration 0014 seeded the row with "Show the full-screen maintenance
-- blocker in the mobile app", and that was the whole of it: nothing in the
-- backend read the key. An operator could turn maintenance on, watch the
-- admin console confirm it, and the API went on accepting every write from
-- anyone on an older build, a web client, or curl. The blocker was a picture
-- of a closed shop with the door unlocked.
--
-- The API now refuses ordinary traffic with 503 SERVICE_UNDER_MAINTENANCE
-- while this is "true" (see src/common/maintenance/maintenance.guard.ts).
-- `description` is what `GET /admin/config` hands the console, so leaving the
-- old text in place would understate a switch that now stops the service.
--
-- Data only — no schema change, so the generated database types are
-- unaffected.
UPDATE app_config
   SET description = 'Closes the API. While "true" the backend answers 503 '
                     'SERVICE_UNDER_MAINTENANCE to every non-admin request, '
                     'and the mobile app shows the full-screen maintenance '
                     'blocker. Admins, sign-in, GET /config and the health '
                     'probes keep working, so you can always switch it back '
                     'off.',
       updated_at = now()
 WHERE key = 'maintenance_mode';

UPDATE app_config
   SET description = 'Optional custom copy for the maintenance screen. Empty '
                     'falls back to the built-in text. Cosmetic only — the '
                     'API refusal carries its own fixed message.',
       updated_at = now()
 WHERE key = 'maintenance_message';

COMMIT;
