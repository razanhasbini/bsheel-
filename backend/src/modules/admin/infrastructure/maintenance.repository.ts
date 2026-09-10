import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import { maintenanceModeKey } from '../domain/maintenance.js';

/**
 * The single read behind the maintenance gate.
 *
 * Separate from `AdminOperationsRepository` on purpose: this one query runs on
 * the request path for every caller, so it must not drag the whole admin
 * facade (and its four collaborators) into the guard's dependency graph.
 */
@Injectable()
export class MaintenanceRepository {
  constructor(private readonly database: DatabaseService) {}

  /**
   * Reads `maintenance_mode`.
   *
   * The value is a jsonb string — `'"true"'` — because every public config row
   * is stored that way so the client's scalar normalisation yields one shape
   * for all of them (see migration 0014). `#>> '{}'` unwraps a jsonb scalar to
   * text, which is what makes `'"true"'` and a bare `true` both compare equal
   * to `'true'` here; a plain `= '"true"'::jsonb` would only match the former.
   *
   * A missing row is `false`. Absent means off — matching the mobile client,
   * which treats an absent key the same way.
   */
  async isMaintenanceModeEnabled(): Promise<boolean> {
    const result = await this.database.query<{ enabled: boolean }>(
      `SELECT lower(value #>> '{}') = 'true' AS enabled
         FROM app_config WHERE key = $1`,
      [maintenanceModeKey],
    );
    return result.rows[0]?.enabled === true;
  }
}
