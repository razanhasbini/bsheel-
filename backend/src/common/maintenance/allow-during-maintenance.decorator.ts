import { SetMetadata } from '@nestjs/common';

export const ALLOW_DURING_MAINTENANCE_KEY = 'allowDuringMaintenance';

/**
 * Marks a route that must keep answering while maintenance mode is on.
 *
 * Only for routes that need a session *and* must survive a maintenance
 * window. Everything reachable without one is already exempt — see
 * `MaintenanceGuard` for why.
 */
export const AllowDuringMaintenance = () =>
  SetMetadata(ALLOW_DURING_MAINTENANCE_KEY, true);
