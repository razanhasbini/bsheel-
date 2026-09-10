import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { DatabaseService } from '../src/infrastructure/database/database.service.js';
import { MaintenanceRepository } from '../src/modules/admin/infrastructure/maintenance.repository.js';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

/**
 * Maintenance mode used to be a picture of a closed shop with the door
 * unlocked: the admin console wrote `maintenance_mode = "true"`, the mobile
 * app painted a full-screen blocker, and the API answered every request as
 * normal. Anyone on an older build, a web client or curl kept writing.
 *
 * These tests hold the whole switch to account, including the three things
 * that have to survive it — the health probes, `GET /config` and sign-in —
 * because each one is a way for the operator to lock themselves out of the
 * off switch and need a redeploy to get back in.
 *
 * ## Why the flag is read from a spec-private key
 *
 * `maintenance_mode` is one row in one shared database, and e2e files run in
 * parallel. Turning the real flag on would 503 every other suite's ordinary
 * user traffic for as long as this file held it. So this app reads a
 * spec-private `app_config` key instead, and every flip below still goes
 * through the operator's real route — `PUT /admin/config/:key`. The chain
 * under test stays real: HTTP, the admin service, the `app_config` row, the
 * cache invalidation, and the guard's read of it. Only the key differs.
 */
describe('maintenance mode (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let database: DatabaseService | undefined;
  let user: TestUser;
  let moderator: TestUser;
  let superAdmin: TestUser;

  /// Must satisfy ConfigKeyParam: lowercase first character, then
  /// [a-z0-9_.-] only.
  const configKey = `e2e_maintenance_${randomUUID().replaceAll('-', '')}`;

  /// The same read as MaintenanceRepository, deliberately duplicated rather
  /// than parameterised — production code should carry no seam that exists
  /// only for a test. The stored value has the identical shape (a jsonb
  /// string, written by the same endpoint), so the `#>> '{}'` unwrap this
  /// suite exercises is the one that ships.
  const maintenanceRepositoryDouble = {
    async isMaintenanceModeEnabled(): Promise<boolean> {
      const result = await database!.query<{ enabled: boolean }>(
        `SELECT lower(value #>> '{}') = 'true' AS enabled
           FROM app_config WHERE key = $1`,
        [configKey],
      );
      return result.rows[0]?.enabled === true;
    },
  };

  beforeAll(async () => {
    harness = await E2eHarness.boot({
      overrides: [
        { provide: MaintenanceRepository, useValue: maintenanceRepositoryDouble },
      ],
    });
    database = harness.app.get(DatabaseService);

    user = await harness.createUser({ prefix: 'm0' });
    moderator = await harness.createUser({ role: 'moderator', prefix: 'm1' });
    superAdmin = await harness.createUser({ role: 'super_admin', prefix: 'm2' });
  }, 300_000);

  afterAll(async () => {
    await harness?.database.query('DELETE FROM app_config WHERE key = $1', [configKey]);
    await harness?.close();
  });

  /// Flips the switch the way an operator does.
  ///
  /// No sleep: `AdminService.setConfig` drops the maintenance cache after the
  /// write, so the next request re-reads the row. That the assertions below
  /// pass immediately is itself the proof that the invalidation works — a
  /// missing `invalidate()` would leave this suite failing for up to the
  /// cache TTL.
  async function setMaintenance(enabled: boolean): Promise<void> {
    await harness
      .put(`/admin/config/${configKey}`, superAdmin)
      .send({ value: String(enabled), isPublic: false })
      .expect(200);
  }

  beforeEach(async () => {
    await setMaintenance(false);
  });

  it('serves ordinary user traffic while the flag is off', async () => {
    await harness.get('/profiles/me', user).expect(200);
  });

  describe('while maintenance mode is on', () => {
    beforeEach(async () => {
      await setMaintenance(true);
    });

    it('refuses ordinary user traffic with a machine-readable 503', async () => {
      const response = await harness.get('/profiles/me', user).expect(503);

      expect(response.body.success).toBe(false);
      expect(response.body.error.code).toBe('SERVICE_UNDER_MAINTENANCE');
      // A client has to be able to tell "closed on purpose" from "broken".
      expect(response.headers['retry-after']).toBe('60');
    });

    it('refuses writes, and refuses them before the handler runs', async () => {
      const quest = await harness.createQuest();

      await harness.post('/quests/assign', user).send({ questId: quest.id }).expect(503);

      expect(
        await harness.countRows(
          'SELECT count(*) FROM user_quests WHERE user_id = $1 AND quest_id = $2',
          [user.id, quest.id],
        ),
      ).toBe(0);
    });

    it('keeps answering the health probes', async () => {
      // Block these and the orchestrator kills the container as unhealthy,
      // turning a maintenance window into a real outage.
      await harness.get('/health/live').expect(200);
      const ready = await harness.get('/health/ready').expect(200);
      expect(ready.body.data.dependencies.postgres).toBe('up');
    });

    it('keeps serving GET /config, which is how a client learns why', async () => {
      // The mobile app polls this every five seconds and paints its
      // maintenance screen from it. Refuse it and the app shows generic
      // failures instead, and the console cannot read the flag to clear it.
      const response = await harness.get('/config').expect(200);
      const keys = response.body.data.map((row: { key: string }) => row.key);
      expect(keys).toContain('maintenance_mode');
    });

    it('keeps registration and sign-in open, because identity precedes authorisation', async () => {
      // Blocking /auth would lock the operator out of the console that holds
      // the off switch: a role cannot be checked before a token exists.
      const during = await harness.createUser({ prefix: 'm3' });
      expect(during.accessToken).toBeTruthy();

      // ...and the account it just issued a token to is still ordinary
      // traffic, so the gate is about the caller's role, not their token.
      await harness.get('/profiles/me', during).expect(503);
    });

    it('lets a moderator keep moderating', async () => {
      await harness.get('/admin/reports', moderator).expect(200);
    });

    it('lets a super admin read the config and switch it back off', async () => {
      await harness.get('/admin/config', superAdmin).expect(200);

      await setMaintenance(false);

      // The whole point: the mode is recoverable from the console, with no
      // redeploy and no shell.
      await harness.get('/profiles/me', user).expect(200);
    });
  });
});
