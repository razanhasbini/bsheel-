import { Injectable, Logger } from '@nestjs/common';
import { MaintenanceRepository } from '../infrastructure/maintenance.repository.js';
import { maintenanceCacheTtlMs } from '../domain/maintenance.js';

/**
 * Answers "is the API closed right now?" cheaply enough to ask on every
 * request.
 *
 * PostgreSQL stays authoritative — this only caches its answer for
 * `maintenanceCacheTtlMs`, which also means several API processes converge on
 * a flip within one TTL without any cross-process invalidation. A write from
 * this process clears its own cache immediately so the operator who flips the
 * switch sees it take effect on their very next request rather than up to five
 * seconds later.
 */
@Injectable()
export class MaintenanceModeService {
  private readonly logger = new Logger(MaintenanceModeService.name);
  private cached: { enabled: boolean; readAt: number } | null = null;
  private inFlight: Promise<boolean> | null = null;

  constructor(private readonly repository: MaintenanceRepository) {}

  async isEnabled(now: number = Date.now()): Promise<boolean> {
    const cached = this.cached;
    if (cached && now - cached.readAt < maintenanceCacheTtlMs) {
      return cached.enabled;
    }
    // One reader per refresh. Without this, the first request after a TTL
    // expiry on a busy process fans out into one SELECT per concurrent
    // request — the exact stampede the cache exists to prevent.
    this.inFlight ??= this.refresh(now);
    try {
      return await this.inFlight;
    } finally {
      this.inFlight = null;
    }
  }

  /**
   * Drops the cache, so the next read hits PostgreSQL.
   *
   * Called when `app_config` is written. Keyless on purpose: `setConfig` does
   * not know which keys anyone caches, and re-reading one row is cheaper than
   * threading key awareness through it.
   */
  invalidate(): void {
    this.cached = null;
  }

  /**
   * Reads the flag, and **fails open** if the database will not answer.
   *
   * Failing closed would turn a transient connection blip into a total
   * outage — every request 503 with a maintenance message that no operator
   * chose and none can clear, because clearing it needs the same database.
   * A genuinely dead database already fails every request on its own merits,
   * and `/health/ready` already reports it. The last known value is preferred
   * over `false` so an actual maintenance window survives a blip.
   */
  private async refresh(now: number): Promise<boolean> {
    try {
      const enabled = await this.repository.isMaintenanceModeEnabled();
      this.cached = { enabled, readAt: now };
      return enabled;
    } catch (error) {
      const previous = this.cached?.enabled ?? false;
      this.logger.warn(
        { error },
        `Could not read maintenance_mode; serving traffic as maintenance=${previous}`,
      );
      // Re-stamp so a database that is down does not get one SELECT per
      // request from the gate on top of everything else it is failing.
      this.cached = { enabled: previous, readAt: now };
      return previous;
    }
  }
}
