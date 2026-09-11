import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

/// `businesses.slug` is globally unique, and a slug derived from a fixed
/// display name is the same slug on every run — so a suite using constant
/// names passes once against an empty database and 409s forever after.
/// Every name created here carries this run's tag.
const tag = randomUUID().replaceAll('-', '').slice(0, 10);
const named = (name: string) => `${name} ${tag}`;

/// Business / destination accounts (#14).
///
/// Most of this suite is about one thing: a business may read its own
/// places and nothing else. That boundary is the whole feature — the
/// analytics dashboard (#50) sits directly on top of it — so the cases that
/// matter are the refusals, not the happy path.
describe('business accounts (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let admin: TestUser;
  let owner: TestUser;
  let manager: TestUser;
  let stranger: TestUser;

  /// A published place, since a business claims real locations.
  const createPlace = async (name: string): Promise<string> => {
    const result = await harness.database.query<{ id: string }>(
      `INSERT INTO map_places (country_code, name, category, latitude, longitude, is_published)
       VALUES ('LB', $1, 'landmark', 33.8938, 35.5018, true)
       RETURNING id`,
      [named(name)],
    );
    return result.rows[0].id;
  };

  const createBusiness = async (options: {
    name: string;
    ownerUserId: string;
    slug?: string;
  }): Promise<string> => {
    const response = await harness
      .post('/admin/businesses', admin)
      .send({
        name: named(options.name),
        ownerUserId: options.ownerUserId,
        ...(options.slug ? { slug: `${options.slug}-${tag}` } : {}),
      })
      .expect(201);
    return response.body.data.id;
  };

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    admin = await harness.createUser({ role: 'super_admin', prefix: 'bizadmin' });
    owner = await harness.createUser({ prefix: 'bizowner' });
    manager = await harness.createUser({ prefix: 'bizmgr' });
    stranger = await harness.createUser({ prefix: 'bizstranger' });
  });

  afterAll(async () => {
    await harness?.close();
  });

  describe('creating one', () => {
    it('creates a business with its first owner and an audit trail', async () => {
      const id = await createBusiness({ name: 'Beirut Souks', ownerUserId: owner.id });

      // The owner exists from the first moment: a business with no owner is
      // unreachable, because only an owner may appoint members.
      expect(
        await harness.countRows(
          `SELECT count(*) FROM business_members
           WHERE business_id = $1 AND user_id = $2 AND role = 'owner'`,
          [id, owner.id],
        ),
      ).toBe(1);
      expect(
        await harness.countRows(
          `SELECT count(*) FROM admin_audit_log
           WHERE target_type = 'business' AND target_id = $1 AND action = 'business.create'`,
          [id],
        ),
      ).toBe(1);
    });

    it('derives a URL handle from the name when none is given', async () => {
      const response = await harness
        .post('/admin/businesses', admin)
        .send({ name: named('Café Younes'), ownerUserId: owner.id })
        .expect(201);

      // Accents folded rather than dropped: "Café" must not become "caf".
      expect(response.body.data.slug).toBe(`cafe-younes-${tag}`);
    });

    it('refuses a handle that is already taken', async () => {
      await createBusiness({ name: 'Taken Handle', ownerUserId: owner.id, slug: 'taken-handle' });

      const response = await harness
        .post('/admin/businesses', admin)
        .send({ name: named('Another One'), ownerUserId: owner.id, slug: `taken-handle-${tag}` })
        .expect(409);

      expect(response.body.error.code).toBe('BUSINESS_SLUG_TAKEN');
    });

    it('refuses a name no handle can be derived from, rather than failing a constraint', async () => {
      const response = await harness
        .post('/admin/businesses', admin)
        .send({ name: '中文名称', ownerUserId: owner.id })
        .expect(400);

      expect(response.body.error.code).toBe('BUSINESS_SLUG_REQUIRED');
    });

    // Creating a business is not self-serve on purpose: a place is a real
    // location whose visitor analytics the owner gets to read, and there is
    // no ownership proof in the system to check a claim against.
    it('is closed to an ordinary user', async () => {
      await harness
        .post('/admin/businesses', owner)
        .send({ name: named('Self Serve'), ownerUserId: owner.id })
        .expect(403);
    });
  });

  describe('claiming places', () => {
    it('links a place and reports it to the members', async () => {
      const id = await createBusiness({ name: 'Linked Business', ownerUserId: owner.id });
      const placeId = await createPlace('Linked Place');

      await harness.post(`/admin/businesses/${id}/places`, admin).send({ placeId }).expect(204);

      const response = await harness.get(`/businesses/${id}/places`, owner).expect(200);
      expect(response.body.data.placeIds).toEqual([placeId]);
    });

    // The case that would leak one business's visitors to another. The
    // UNIQUE constraint on place_id is the real guard; this proves it
    // surfaces as a refusal rather than a 500.
    it('refuses a place another business already owns', async () => {
      const first = await createBusiness({ name: 'First Claimant', ownerUserId: owner.id });
      const second = await createBusiness({ name: 'Second Claimant', ownerUserId: owner.id });
      const placeId = await createPlace('Contested Place');

      await harness.post(`/admin/businesses/${first}/places`, admin).send({ placeId }).expect(204);
      const response = await harness
        .post(`/admin/businesses/${second}/places`, admin)
        .send({ placeId })
        .expect(409);

      expect(response.body.error.code).toBe('PLACE_ALREADY_CLAIMED');
      const places = await harness.get(`/businesses/${second}/places`, owner).expect(200);
      expect(places.body.data.placeIds).toEqual([]);
    });

    it('is idempotent when the same business claims the same place twice', async () => {
      const id = await createBusiness({ name: 'Repeat Claimant', ownerUserId: owner.id });
      const placeId = await createPlace('Repeat Place');

      await harness.post(`/admin/businesses/${id}/places`, admin).send({ placeId }).expect(204);
      await harness.post(`/admin/businesses/${id}/places`, admin).send({ placeId }).expect(204);

      expect(
        await harness.countRows('SELECT count(*) FROM business_places WHERE business_id = $1', [id]),
      ).toBe(1);
    });

    it('releases a place on unlink, so it can be claimed by someone else', async () => {
      const first = await createBusiness({ name: 'Releasing Business', ownerUserId: owner.id });
      const second = await createBusiness({ name: 'Receiving Business', ownerUserId: owner.id });
      const placeId = await createPlace('Transferred Place');

      await harness.post(`/admin/businesses/${first}/places`, admin).send({ placeId }).expect(204);
      await harness.delete(`/admin/businesses/${first}/places/${placeId}`, admin).expect(204);
      await harness.post(`/admin/businesses/${second}/places`, admin).send({ placeId }).expect(204);

      const places = await harness.get(`/businesses/${second}/places`, owner).expect(200);
      expect(places.body.data.placeIds).toEqual([placeId]);
    });
  });

  describe('who can see a business', () => {
    let businessId: string;

    beforeAll(async () => {
      businessId = await createBusiness({ name: 'Visibility Business', ownerUserId: owner.id });
      await harness
        .post(`/admin/businesses/${businessId}/members`, admin)
        .send({ userId: manager.id, role: 'manager' })
        .expect(204);
    });

    it('shows it to its members', async () => {
      for (const member of [owner, manager]) {
        const response = await harness.get(`/businesses/${businessId}`, member).expect(200);
        expect(response.body.data.name).toBe(named('Visibility Business'));
      }
    });

    // 404 rather than 403, deliberately. A 403 confirms the business exists,
    // which turns walking the id space into a directory of who is on the
    // platform and where.
    it('tells a stranger it does not exist rather than that they lack permission', async () => {
      const response = await harness.get(`/businesses/${businessId}`, stranger).expect(404);
      expect(response.body.error.code).toBe('BUSINESS_NOT_FOUND');
    });

    // The separation that keeps "can moderate the platform" from silently
    // becoming "can read every business's visitor data". An admin manages
    // businesses through the admin routes, which are audited.
    it('refuses a super admin who is not a member, on the member routes', async () => {
      await harness.get(`/businesses/${businessId}`, admin).expect(404);
      await harness.get(`/businesses/${businessId}/places`, admin).expect(404);
    });

    it('lists a members own businesses, and nobody elses', async () => {
      const mine = await harness.get('/businesses/me', manager).expect(200);
      expect(mine.body.data.map((row: { id: string }) => row.id)).toContain(businessId);

      const theirs = await harness.get('/businesses/me', stranger).expect(200);
      expect(theirs.body.data).toEqual([]);
    });
  });

  describe('suspension', () => {
    it('stops the dashboard for every member, owners included', async () => {
      const businessId = await createBusiness({ name: 'Suspended Business', ownerUserId: owner.id });
      await harness.get(`/businesses/${businessId}`, owner).expect(200);

      await harness
        .patch(`/admin/businesses/${businessId}`, admin)
        .send({ status: 'suspended' })
        .expect(200);

      const response = await harness.get(`/businesses/${businessId}`, owner).expect(403);
      expect(response.body.error.code).toBe('BUSINESS_SUSPENDED');
    });

    // Suspension is not deletion. Losing the place links would destroy the
    // record of what was claimed, which is exactly what a dispute needs.
    it('keeps the place links so the claim survives the dispute', async () => {
      const businessId = await createBusiness({ name: 'Disputed Business', ownerUserId: owner.id });
      const placeId = await createPlace('Disputed Place');
      await harness.post(`/admin/businesses/${businessId}/places`, admin).send({ placeId }).expect(204);

      await harness
        .patch(`/admin/businesses/${businessId}`, admin)
        .send({ status: 'suspended' })
        .expect(200);

      expect(
        await harness.countRows('SELECT count(*) FROM business_places WHERE business_id = $1', [businessId]),
      ).toBe(1);
    });

    it('restores access when the suspension is lifted', async () => {
      const businessId = await createBusiness({ name: 'Restored Business', ownerUserId: owner.id });
      await harness.patch(`/admin/businesses/${businessId}`, admin).send({ status: 'suspended' }).expect(200);
      await harness.get(`/businesses/${businessId}`, owner).expect(403);

      await harness.patch(`/admin/businesses/${businessId}`, admin).send({ status: 'active' }).expect(200);
      await harness.get(`/businesses/${businessId}`, owner).expect(200);
    });
  });

  describe('membership', () => {
    it('takes effect immediately on removal, without waiting for a token to expire', async () => {
      const businessId = await createBusiness({ name: 'Revoking Business', ownerUserId: owner.id });
      await harness
        .post(`/admin/businesses/${businessId}/members`, admin)
        .send({ userId: manager.id, role: 'manager' })
        .expect(204);
      await harness.get(`/businesses/${businessId}`, manager).expect(200);

      await harness.delete(`/admin/businesses/${businessId}/members/${manager.id}`, admin).expect(204);

      // Same access token as the successful call above. Membership is read
      // per request, so a removed member loses access now rather than in an
      // hour — which is the whole reason it is not a token claim.
      await harness.get(`/businesses/${businessId}`, manager).expect(404);
    });

    // Removing the last owner would leave a business only an admin could
    // ever manage again, since appointing members is owner-only.
    it('refuses to remove the last owner', async () => {
      const businessId = await createBusiness({ name: 'Lone Owner Business', ownerUserId: owner.id });

      const response = await harness
        .delete(`/admin/businesses/${businessId}/members/${owner.id}`, admin)
        .expect(409);

      expect(response.body.error.code).toBe('LAST_BUSINESS_OWNER');
    });

    it('allows removing an owner once another owner exists', async () => {
      const businessId = await createBusiness({ name: 'Two Owner Business', ownerUserId: owner.id });
      await harness
        .post(`/admin/businesses/${businessId}/members`, admin)
        .send({ userId: manager.id, role: 'owner' })
        .expect(204);

      await harness.delete(`/admin/businesses/${businessId}/members/${owner.id}`, admin).expect(204);

      expect(
        await harness.countRows(
          `SELECT count(*) FROM business_members WHERE business_id = $1 AND role = 'owner'`,
          [businessId],
        ),
      ).toBe(1);
    });

    /// An owner runs their own team; claiming places stays with an admin.
    describe('managed by the owner rather than an admin', () => {
      it('lets an owner appoint a manager', async () => {
        const businessId = await createBusiness({ name: 'Owner Managed', ownerUserId: owner.id });
        const staff = await harness.createUser({ prefix: 'bizstaff' });

        await harness
          .post(`/businesses/${businessId}/members`, owner)
          .send({ userId: staff.id, role: 'manager' })
          .expect(204);

        await harness.get(`/businesses/${businessId}`, staff).expect(200);
      });

      // The escalation this rule exists to stop: a manager who could appoint
      // members could appoint itself an owner.
      it('refuses a manager appointing anyone, including itself', async () => {
        const businessId = await createBusiness({ name: 'No Escalation', ownerUserId: owner.id });
        await harness
          .post(`/businesses/${businessId}/members`, owner)
          .send({ userId: manager.id, role: 'manager' })
          .expect(204);

        const promotion = await harness
          .post(`/businesses/${businessId}/members`, manager)
          .send({ userId: manager.id, role: 'owner' })
          .expect(403);
        expect(promotion.body.error.code).toBe('BUSINESS_OWNER_REQUIRED');

        const outsider = await harness.createUser({ prefix: 'bizoutsider' });
        await harness
          .post(`/businesses/${businessId}/members`, manager)
          .send({ userId: outsider.id, role: 'manager' })
          .expect(403);

        // And the membership table is unchanged by either attempt.
        expect(
          await harness.countRows(
            `SELECT count(*) FROM business_members WHERE business_id = $1 AND role = 'owner'`,
            [businessId],
          ),
        ).toBe(1);
      });

      it('refuses a stranger with a 404, not a permission error', async () => {
        const businessId = await createBusiness({ name: 'Closed To Strangers', ownerUserId: owner.id });

        await harness
          .post(`/businesses/${businessId}/members`, stranger)
          .send({ userId: stranger.id, role: 'owner' })
          .expect(404);
      });

      it('holds the last-owner rule against an owner removing themselves', async () => {
        const businessId = await createBusiness({ name: 'Self Removal', ownerUserId: owner.id });

        const response = await harness
          .delete(`/businesses/${businessId}/members/${owner.id}`, owner)
          .expect(409);

        expect(response.body.error.code).toBe('LAST_BUSINESS_OWNER');
      });

      // Claiming a place is a claim about the real world, so it stays with
      // an admin however much authority the owner has over their own team.
      it('never lets an owner claim a place', async () => {
        const businessId = await createBusiness({ name: 'Cannot Self Claim', ownerUserId: owner.id });
        const placeId = await createPlace('Unclaimable Place');

        await harness
          .post(`/admin/businesses/${businessId}/places`, owner)
          .send({ placeId })
          .expect(403);

        expect(
          await harness.countRows('SELECT count(*) FROM business_places WHERE place_id = $1', [placeId]),
        ).toBe(0);
      });
    });

    it('refuses a member who is not an existing user', async () => {
      const businessId = await createBusiness({ name: 'Ghost Member Business', ownerUserId: owner.id });

      await harness
        .post(`/admin/businesses/${businessId}/members`, admin)
        .send({ userId: '00000000-0000-4000-8000-000000000000', role: 'manager' })
        .expect(404);
    });
  });

  /// Being a business changes nothing about being a player. The issue asked
  /// for "the entire app stays the same except their profile", and this is
  /// the half of that claim the backend is responsible for.
  it('leaves the rest of the app identical for a business member', async () => {
    const member = await harness.createUser({ prefix: 'bizplayer' });
    const before = await harness.get('/profiles/me', member).expect(200);

    await createBusiness({ name: 'Player Business', ownerUserId: member.id });

    const after = await harness.get('/profiles/me', member).expect(200);
    expect(after.body.data).toEqual(before.body.data);
    // Still an ordinary user everywhere authority is checked.
    await harness.get('/admin/businesses', member).expect(403);
  });
});
