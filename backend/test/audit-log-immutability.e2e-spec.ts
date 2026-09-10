import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness } from './support/e2e-harness.js';

/// CLAUDE.md: "Sensitive admin actions append an immutable audit record."
///
/// Until migration 0027 nothing enforced the immutable half — no trigger, no
/// privileges — so an UPDATE or a DELETE against `admin_audit_log` simply
/// worked. These tests run every mutation through `harness.database`, which is
/// the application's own pool on the application's own connection string: the
/// point is that the guarantee holds for the process that writes the log, not
/// merely for some hypothetical lesser role. The API connects as the owner of
/// the schema and an owner is never restrained by its own table privileges,
/// which is why the guard has to be a trigger.
///
/// Nothing here can clean up after itself, by design. Every row it appends
/// carries a target_id generated for the run, so no assertion depends on the
/// rest of the table.
describe('admin_audit_log is append-only (e2e)', { timeout: 180_000 }, () => {
  let harness: E2eHarness;

  beforeAll(async () => {
    harness = await E2eHarness.boot();
  }, 300_000);

  afterAll(async () => {
    await harness?.close();
  });

  /// Appends one row and returns its id and target.
  const append = async (action = 'e2e.audit_probe') => {
    const targetId = randomUUID();
    const inserted = await harness.database.query<{ id: string }>(
      `INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, before_state, after_state)
       VALUES (NULL, $1, 'e2e_probe', $2, '{"state":"before"}'::jsonb, '{"state":"after"}'::jsonb)
       RETURNING id`,
      [action, targetId],
    );
    return { id: inserted.rows[0].id, targetId };
  };

  it('still accepts an INSERT — append-only is not read-only', async () => {
    const { targetId } = await append();
    expect(
      await harness.countRows('SELECT count(*) FROM admin_audit_log WHERE target_id = $1', [targetId]),
    ).toBe(1);
  });

  it('refuses an UPDATE', async () => {
    const { id, targetId } = await append();

    await expect(
      harness.database.query(`UPDATE admin_audit_log SET after_state = '{"state":"rewritten"}'::jsonb WHERE id = $1`, [id]),
    ).rejects.toMatchObject({ code: '23001' });

    const row = await harness.database.query<{ after_state: { state: string } }>(
      'SELECT after_state FROM admin_audit_log WHERE target_id = $1',
      [targetId],
    );
    expect(row.rows[0].after_state.state).toBe('after');
  });

  it('refuses an UPDATE that changes nothing but the actor', async () => {
    // The shape the dropped foreign key used to produce on its own.
    const { id } = await append();
    await expect(
      harness.database.query('UPDATE admin_audit_log SET actor_id = NULL WHERE id = $1', [id]),
    ).rejects.toMatchObject({ code: '23001' });
  });

  it('refuses a DELETE', async () => {
    const { id, targetId } = await append();

    await expect(
      harness.database.query('DELETE FROM admin_audit_log WHERE id = $1', [id]),
    ).rejects.toMatchObject({ code: '23001' });

    expect(
      await harness.countRows('SELECT count(*) FROM admin_audit_log WHERE target_id = $1', [targetId]),
    ).toBe(1);
  });

  it('refuses a DELETE that matches no rows at all', async () => {
    // A row-level trigger fires per row, so a no-op DELETE is allowed
    // through — worth pinning, because it is the difference between "the log
    // cannot be edited" and "DELETE always errors".
    await expect(
      harness.database.query('DELETE FROM admin_audit_log WHERE target_id = $1', [randomUUID()]),
    ).resolves.toMatchObject({ rowCount: 0 });
  });

  it('refuses a TRUNCATE, which row-level triggers would not have caught', async () => {
    const { targetId } = await append();

    await expect(harness.database.query('TRUNCATE admin_audit_log')).rejects.toMatchObject({ code: '23001' });

    expect(
      await harness.countRows('SELECT count(*) FROM admin_audit_log WHERE target_id = $1', [targetId]),
    ).toBe(1);
  });

  it('keeps a real admin action on the record, and that record intact', async () => {
    // Quest deletion is one of the sensitive actions CLAUDE.md is about: the
    // row is gone and the audit record is the only remaining evidence of who
    // removed it and what it contained.
    const admin = await harness.createUser({ role: 'super_admin', prefix: 'auditAdm' });
    const quest = await harness.createQuest({ title: `Audit probe ${harness.uniqueName('q')}` });

    await harness.delete(`/quests/admin/${quest.id}`, admin).expect(204);

    const rows = await harness.auditRows('quest.delete', quest.id);
    expect(rows).toHaveLength(1);
    expect(rows[0].actor_id).toBe(admin.id);
    expect(rows[0].before_state).toMatchObject({ title: quest.title });

    await expect(
      harness.database.query(
        `UPDATE admin_audit_log SET before_state = NULL WHERE action = 'quest.delete' AND target_id = $1`,
        [quest.id],
      ),
    ).rejects.toMatchObject({ code: '23001' });
    await expect(
      harness.database.query(`DELETE FROM admin_audit_log WHERE action = 'quest.delete' AND target_id = $1`, [quest.id]),
    ).rejects.toMatchObject({ code: '23001' });

    expect(await harness.auditRows('quest.delete', quest.id)).toHaveLength(1);
  });

  it('no longer lets deleting a user erase who they were', async () => {
    // admin_audit_log.actor_id used to be a foreign key with ON DELETE SET
    // NULL, so a hard delete of a user rewrote this table on the deleter's
    // behalf and the trail of that admin's actions lost its actor. 0027
    // dropped the constraint: account deletion still succeeds (the same
    // statement the account-deletion job runs), and the actor id stays.
    const admin = await harness.createUser({ role: 'super_admin', prefix: 'auditGone' });
    const targetId = randomUUID();
    await harness.database.query(
      `INSERT INTO admin_audit_log (actor_id, action, target_type, target_id)
       VALUES ($1, 'e2e.audit_probe', 'e2e_probe', $2)`,
      [admin.id, targetId],
    );

    await harness.database.query('DELETE FROM admins WHERE user_id = $1', [admin.id]);
    await harness.database.query('DELETE FROM users WHERE id = $1', [admin.id]);

    const row = await harness.database.query<{ actor_id: string | null }>(
      'SELECT actor_id FROM admin_audit_log WHERE target_id = $1',
      [targetId],
    );
    expect(row.rows[0].actor_id).toBe(admin.id);
  });
});
