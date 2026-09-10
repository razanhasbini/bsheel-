/**
 * Maintenance mode: the rules, in one place.
 *
 * `maintenance_mode` is an `app_config` row an operator flips from the admin
 * console. It was purely cosmetic until now — the mobile app painted a
 * full-screen blocker from it and the API kept serving every request, so an
 * operator who "closed" the app for a database migration was still taking
 * writes from anyone on an older build, a web client, or curl.
 */

/** The `app_config` key. */
export const maintenanceModeKey = 'maintenance_mode';

/**
 * The error code a refused request carries.
 *
 * Machine-readable on purpose: `mapDbError` in `packages/app_core` matches on
 * it, so a refusal reads as "we are down for maintenance" rather than the
 * generic "failed to <action>, please try again" that invites a retry into a
 * wall.
 */
export const maintenanceErrorCode = 'SERVICE_UNDER_MAINTENANCE';

export const maintenanceErrorMessage =
  'Bsheel is under maintenance. Please try again shortly.';

/**
 * `Retry-After`, in seconds. Deliberately short: a maintenance window here is
 * minutes, and a long value tells caches and clients to stay away well after
 * the flag is back off.
 */
export const maintenanceRetryAfterSeconds = 60;

/**
 * How long a cached read of the flag is trusted.
 *
 * Five seconds, matching the mobile client's `GET /config` poll interval, so
 * the server and the app agree about the state of the world within one tick.
 * A per-request `SELECT` would put a database round trip in front of every
 * request to buy nothing.
 */
export const maintenanceCacheTtlMs = 5_000;

/** The roles that keep working while maintenance mode is on. */
export const rolesExemptFromMaintenance = ['moderator', 'super_admin'] as const;
