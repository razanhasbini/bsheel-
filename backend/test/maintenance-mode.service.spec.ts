import { describe, expect, it, vi } from 'vitest';
import { MaintenanceModeService } from '../src/modules/admin/application/maintenance-mode.service.js';
import type { MaintenanceRepository } from '../src/modules/admin/infrastructure/maintenance.repository.js';
import { maintenanceCacheTtlMs } from '../src/modules/admin/domain/maintenance.js';

function serviceOver(reads: (() => Promise<boolean>)[]) {
  let call = 0;
  const isMaintenanceModeEnabled = vi.fn(() => {
    const read = reads[Math.min(call, reads.length - 1)];
    call += 1;
    return read();
  });
  const service = new MaintenanceModeService({
    isMaintenanceModeEnabled,
  } as unknown as MaintenanceRepository);
  return { service, isMaintenanceModeEnabled };
}

const on = () => Promise.resolve(true);
const off = () => Promise.resolve(false);
const broken = () => Promise.reject(new Error('connection terminated'));

/**
 * The maintenance flag is consulted on every single request, so how it is
 * cached and what it does when PostgreSQL will not answer are both decisions
 * with teeth. Neither is reachable from an e2e test: one is about how many
 * queries do *not* happen, the other needs the database to fail on demand.
 */
describe('MaintenanceModeService', () => {
  it('reads once and serves the cache until the TTL expires', async () => {
    const { service, isMaintenanceModeEnabled } = serviceOver([on]);

    expect(await service.isEnabled(1_000)).toBe(true);
    expect(await service.isEnabled(1_000 + maintenanceCacheTtlMs - 1)).toBe(true);
    // A `SELECT` in front of every request would buy nothing: the flag
    // changes a few times a year.
    expect(isMaintenanceModeEnabled).toHaveBeenCalledTimes(1);

    expect(await service.isEnabled(1_000 + maintenanceCacheTtlMs)).toBe(true);
    expect(isMaintenanceModeEnabled).toHaveBeenCalledTimes(2);
  });

  it('re-reads immediately after an invalidation', async () => {
    const { service, isMaintenanceModeEnabled } = serviceOver([on, off]);

    expect(await service.isEnabled(1_000)).toBe(true);
    service.invalidate();

    // This is what makes the console's switch feel instant instead of taking
    // up to the TTL to bite.
    expect(await service.isEnabled(1_000)).toBe(false);
    expect(isMaintenanceModeEnabled).toHaveBeenCalledTimes(2);
  });

  it('collapses concurrent refreshes into a single read', async () => {
    const { service, isMaintenanceModeEnabled } = serviceOver([on]);

    const answers = await Promise.all([
      service.isEnabled(1_000),
      service.isEnabled(1_000),
      service.isEnabled(1_000),
    ]);

    expect(answers).toEqual([true, true, true]);
    // Without the in-flight latch, the first request after a TTL expiry on a
    // busy process fans out into one query per concurrent request — the exact
    // stampede the cache exists to prevent.
    expect(isMaintenanceModeEnabled).toHaveBeenCalledTimes(1);
  });

  it('fails open when the database will not answer', async () => {
    const { service } = serviceOver([broken]);

    // Failing closed would turn a transient connection blip into a total
    // outage: every request refused with a maintenance message no operator
    // chose, and none able to clear it because clearing it needs the same
    // database.
    expect(await service.isEnabled(1_000)).toBe(false);
  });

  it('keeps an active maintenance window across a database blip', async () => {
    const { service } = serviceOver([on, broken]);

    expect(await service.isEnabled(1_000)).toBe(true);
    // The last known value beats a blind `false`, so a real window does not
    // briefly reopen the API the moment a query fails.
    expect(await service.isEnabled(1_000 + maintenanceCacheTtlMs)).toBe(true);
  });

  it('does not re-query on every request while the database is failing', async () => {
    const { service, isMaintenanceModeEnabled } = serviceOver([broken]);

    await service.isEnabled(1_000);
    await service.isEnabled(1_000 + 1);
    await service.isEnabled(1_000 + 2);

    // A database that is down should not also be taking one gate query per
    // request on top of everything else it is failing.
    expect(isMaintenanceModeEnabled).toHaveBeenCalledTimes(1);
  });
});
