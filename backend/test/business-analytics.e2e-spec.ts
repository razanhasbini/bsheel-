import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { MIN_REPORTABLE_COHORT } from '../src/modules/business/domain/business-analytics.js';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

/// The business analytics dashboard (#50).
///
/// Two properties are what this suite is for, and everything else is
/// arithmetic around them:
///
/// **Scope.** A business's figures cover its own places and nothing else.
/// The place set comes from membership, and no request parameter can widen
/// it — there is no place id anywhere in the API.
///
/// **Exposure.** A business sees aggregate counts of people, and the only
/// media it ever sees is proof the author published to the feed themselves.
/// `media_url` is an object key and POST /media/sign does not re-check who
/// may view the submission, so the key is the access: a query that returned
/// private proof would be handing over the bytes, not a reference.
const tag = randomUUID().replaceAll('-', '').slice(0, 10);
const named = (name: string) => `${name} ${tag}`;

describe('business analytics (e2e)', { timeout: 300_000 }, () => {
  let harness: E2eHarness;
  let admin: TestUser;
  let moderator: TestUser;
  let owner: TestUser;
  let stranger: TestUser;

  const createPlace = async (name: string): Promise<string> => {
    const result = await harness.database.query<{ id: string }>(
      `INSERT INTO map_places (country_code, name, category, latitude, longitude, is_published)
       VALUES ('LB', $1, 'landmark', 33.8938, 35.5018, true)
       RETURNING id`,
      [named(name)],
    );
    return result.rows[0].id;
  };

  const createBusiness = async (name: string): Promise<string> => {
    const response = await harness
      .post('/admin/businesses', admin)
      .send({ name: named(name), ownerUserId: owner.id })
      .expect(201);
    return response.body.data.id;
  };

  const claim = (businessId: string, placeId: string) =>
    harness.post(`/admin/businesses/${businessId}/places`, admin).send({ placeId }).expect(204);

  /// A quest offered at a place. `quest_destinations` has one row per quest,
  /// so each quest belongs to exactly one place.
  const questAt = async (placeId: string, title: string): Promise<string> => {
    const quest = await harness.createQuest({ title: named(title) });
    await harness.database.query(
      'INSERT INTO quest_destinations (quest_id, place_id) VALUES ($1, $2)',
      [quest.id, placeId],
    );
    return quest.id;
  };

  /// A fresh author every time: one assigned quest per user is a database
  /// constraint, and rerolls are capped at five per 24h, so reusing an
  /// author would make later cases fail for reasons unrelated to analytics.
  const submit = async (
    questId: string,
    options: { showInFeed?: boolean; outcome?: 'approved' | 'rejected' | 'pending' } = {},
  ): Promise<{ submissionId: string; userId: string }> => {
    const author = await harness.createUser({ prefix: 'bizan' });
    const submission = await harness.createSubmission(author, {
      questId,
      showInFeed: options.showInFeed ?? true,
      caption: named('proof'),
    });
    if (options.outcome === 'approved') {
      await harness.post(`/submissions/${submission.id}/approve`, moderator).send({}).expect(204);
    } else if (options.outcome === 'rejected') {
      await harness
        .post(`/submissions/${submission.id}/reject`, moderator)
        .send({ reviewNote: 'not this time' })
        .expect(204);
    }
    return { submissionId: submission.id, userId: author.id };
  };

  /// Someone who took the quest and never submitted — the population that
  /// makes a completion rate mean anything.
  const startOnly = async (questId: string): Promise<void> => {
    const author = await harness.createUser({ prefix: 'bizstart' });
    await harness.assignQuest(author, questId);
  };

  const summaryOf = async (businessId: string, user: TestUser = owner) =>
    (await harness.get(`/businesses/${businessId}/analytics/summary`, user).expect(200)).body.data;

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    admin = await harness.createUser({ role: 'super_admin', prefix: 'anadmin' });
    moderator = await harness.createUser({ role: 'moderator', prefix: 'anmod' });
    owner = await harness.createUser({ prefix: 'anowner' });
    stranger = await harness.createUser({ prefix: 'anstranger' });
  });

  afterAll(async () => {
    await harness?.close();
  });

  describe('scope', () => {
    it('counts activity at its own places and none at anyone elses', async () => {
      const mine = await createBusiness('Scoped Mine');
      const theirs = await createBusiness('Scoped Theirs');
      const myPlace = await createPlace('My Place');
      const theirPlace = await createPlace('Their Place');
      await claim(mine, myPlace);
      await claim(theirs, theirPlace);

      const myQuest = await questAt(myPlace, 'My Quest');
      const theirQuest = await questAt(theirPlace, 'Their Quest');
      await submit(myQuest, { outcome: 'approved' });
      await submit(theirQuest, { outcome: 'approved' });
      await submit(theirQuest, { outcome: 'approved' });

      const summary = await summaryOf(mine);
      expect(summary.completions).toBe(1);
      expect(summary.visitors).toBe(1);
      expect(summary.places).toBe(1);

      // And the neighbour's two completions are not hiding in a breakdown.
      const places = await harness.get(`/businesses/${mine}/analytics/places`, owner).expect(200);
      expect(places.body.data).toHaveLength(1);
      expect(places.body.data[0].placeId).toBe(myPlace);

      const quests = await harness.get(`/businesses/${mine}/analytics/quests`, owner).expect(200);
      expect(quests.body.data.map((row: { questId: string }) => row.questId)).toEqual([myQuest]);
    });

    it('reports zeroes for a business with no places rather than failing', async () => {
      const empty = await createBusiness('No Places Yet');

      const summary = await summaryOf(empty);
      expect(summary).toMatchObject({ places: 0, completions: 0, visitors: 0, saves: 0 });
      expect(summary.firstActivityAt).toBeNull();
    });
  });

  describe('what counts as a completion', () => {
    let businessId: string;
    let questId: string;

    beforeAll(async () => {
      businessId = await createBusiness('Counting Rules');
      const placeId = await createPlace('Counting Place');
      await claim(businessId, placeId);
      questId = await questAt(placeId, 'Counting Quest');

      await submit(questId, { outcome: 'approved' });
      await submit(questId, { outcome: 'rejected' });
      await submit(questId); // left pending
    });

    it('counts only approved proof, and reports the rest separately', async () => {
      const summary = await summaryOf(businessId);
      expect(summary.completions).toBe(1);
      expect(summary.rejected).toBe(1);
      expect(summary.awaitingReview).toBe(1);
    });

    // A business's totals must not keep counting proof the product has
    // erased, or the dashboard disagrees with the feed forever.
    it('stops counting proof a moderator removed', async () => {
      const before = await summaryOf(businessId);
      const extra = await submit(questId, { outcome: 'approved' });
      expect((await summaryOf(businessId)).completions).toBe(before.completions + 1);

      await harness.database.query(
        'UPDATE submissions SET moderation_removed_at = now() WHERE id = $1',
        [extra.submissionId],
      );

      expect((await summaryOf(businessId)).completions).toBe(before.completions);
    });

    it('stops counting proof its author deleted', async () => {
      const before = await summaryOf(businessId);
      const extra = await submit(questId, { outcome: 'approved' });
      expect((await summaryOf(businessId)).completions).toBe(before.completions + 1);

      await harness.database.query(
        `UPDATE submissions SET deleted_at = now(), visibility = 'deleted' WHERE id = $1`,
        [extra.submissionId],
      );

      expect((await summaryOf(businessId)).completions).toBe(before.completions);
    });
  });

  /// The part that would be a privacy incident rather than a wrong number.
  describe('published proof, and only published proof', () => {
    let businessId: string;
    let questId: string;
    let publicProofId: string;
    let privateProofId: string;
    let pendingProofId: string;

    beforeAll(async () => {
      businessId = await createBusiness('Proof Business');
      const placeId = await createPlace('Proof Place');
      await claim(businessId, placeId);
      questId = await questAt(placeId, 'Proof Quest');

      publicProofId = (await submit(questId, { showInFeed: true, outcome: 'approved' })).submissionId;
      // Approved, so it counts as a completion — but the author chose not to
      // publish it, so its bytes are not the business's to see.
      privateProofId = (await submit(questId, { showInFeed: false, outcome: 'approved' })).submissionId;
      pendingProofId = (await submit(questId, { showInFeed: true })).submissionId;
    });

    const proofIds = async (): Promise<string[]> => {
      const response = await harness
        .get(`/businesses/${businessId}/analytics/proof`, owner)
        .expect(200);
      return response.body.data.items.map((row: { submissionId: string }) => row.submissionId);
    };

    it('returns proof the author published', async () => {
      expect(await proofIds()).toContain(publicProofId);
    });

    // The case worth the whole file. show_in_feed is the author's own opt-in
    // to publication; without it this endpoint would hand a business an
    // object key POST /media/sign turns straight into the image.
    it('never returns approved proof the author kept off the feed', async () => {
      expect(await proofIds()).not.toContain(privateProofId);
    });

    it('never returns proof that has not been reviewed yet', async () => {
      expect(await proofIds()).not.toContain(pendingProofId);
    });

    it('counts the unpublished proof as a completion even though it hides the media', async () => {
      // Both facts at once: the visit happened and is counted; the bytes
      // stay private. Conflating those would either undercount real visits
      // or leak proof.
      const summary = await summaryOf(businessId);
      expect(summary.completions).toBe(2);
      expect(summary.publicProof).toBe(1);
    });

    it('drops proof from the list the moment its author deletes it', async () => {
      const extra = await submit(questId, { showInFeed: true, outcome: 'approved' });
      expect(await proofIds()).toContain(extra.submissionId);

      await harness.database.query(
        `UPDATE submissions SET deleted_at = now(), visibility = 'deleted' WHERE id = $1`,
        [extra.submissionId],
      );

      expect(await proofIds()).not.toContain(extra.submissionId);
    });

    it('pages with a keyset cursor and never repeats a row', async () => {
      for (let i = 0; i < 3; i += 1) await submit(questId, { showInFeed: true, outcome: 'approved' });

      const first = await harness
        .get(`/businesses/${businessId}/analytics/proof?limit=2`, owner)
        .expect(200);
      expect(first.body.data.items).toHaveLength(2);
      expect(first.body.data.nextCursor).not.toBeNull();

      const { beforeSubmittedAt, beforeId } = first.body.data.nextCursor;
      const second = await harness
        .get(
          `/businesses/${businessId}/analytics/proof?limit=2`
          + `&beforeSubmittedAt=${encodeURIComponent(beforeSubmittedAt)}&beforeId=${beforeId}`,
          owner,
        )
        .expect(200);

      const firstIds = first.body.data.items.map((r: { submissionId: string }) => r.submissionId);
      const secondIds = second.body.data.items.map((r: { submissionId: string }) => r.submissionId);
      expect(secondIds.some((id: string) => firstIds.includes(id))).toBe(false);
    });

    it('refuses half a cursor rather than silently restarting', async () => {
      const response = await harness
        .get(`/businesses/${businessId}/analytics/proof?beforeId=${publicProofId}`, owner)
        .expect(400);
      expect(response.body.error.code).toBe('INCOMPLETE_CURSOR');
    });
  });

  describe('quest performance', () => {
    it('counts everyone who started, not only those who finished', async () => {
      const businessId = await createBusiness('Funnel Business');
      const placeId = await createPlace('Funnel Place');
      await claim(businessId, placeId);
      const questId = await questAt(placeId, 'Funnel Quest');

      await submit(questId, { outcome: 'approved' });
      await startOnly(questId);
      await startOnly(questId);

      const response = await harness
        .get(`/businesses/${businessId}/analytics/quests`, owner)
        .expect(200);
      const row = response.body.data.find((r: { questId: string }) => r.questId === questId);

      // Three people took it, one finished. Counting submissions as starts
      // would report 100% follow-through and hide the two who gave up.
      expect(row.starts).toBe(3);
      expect(row.completions).toBe(1);
      expect(row.completionRate).toBeCloseTo(1 / 3, 3);
    });

    // 0% would rank an untested quest as the worst performer in the list,
    // which is a recommendation to change something nobody has tried.
    it('reports no completion rate for a quest nobody has started', async () => {
      const businessId = await createBusiness('Untested Business');
      const placeId = await createPlace('Untested Place');
      await claim(businessId, placeId);
      const questId = await questAt(placeId, 'Untested Quest');

      const response = await harness
        .get(`/businesses/${businessId}/analytics/quests`, owner)
        .expect(200);
      const row = response.body.data.find((r: { questId: string }) => r.questId === questId);

      expect(row.starts).toBe(0);
      expect(row.completionRate).toBeNull();
    });

    it('lists a quest at the business place even before anyone touches it', async () => {
      const businessId = await createBusiness('Offered Business');
      const placeId = await createPlace('Offered Place');
      await claim(businessId, placeId);
      const questId = await questAt(placeId, 'Offered Quest');

      const response = await harness
        .get(`/businesses/${businessId}/analytics/quests`, owner)
        .expect(200);
      expect(response.body.data.map((r: { questId: string }) => r.questId)).toContain(questId);
    });
  });

  describe('the daily series', () => {
    it('returns every day in the window, including the quiet ones', async () => {
      const businessId = await createBusiness('Series Business');
      const placeId = await createPlace('Series Place');
      await claim(businessId, placeId);
      const questId = await questAt(placeId, 'Series Quest');
      await submit(questId, { outcome: 'approved' });

      const response = await harness
        .get(`/businesses/${businessId}/analytics/daily?days=7`, owner)
        .expect(200);

      // Exactly seven points. Grouping the submissions alone would return
      // one, and a chart drawn from that reads as steady traffic.
      expect(response.body.data).toHaveLength(7);
      const total = response.body.data.reduce(
        (sum: number, point: { completions: number }) => sum + point.completions,
        0,
      );
      expect(total).toBe(1);
      expect(response.body.data.at(-1).completions).toBe(1);
    });

    it('bounds the window rather than building an arbitrary series', async () => {
      const businessId = await createBusiness('Bounded Series');
      await harness.get(`/businesses/${businessId}/analytics/daily?days=100000`, owner).expect(400);
      await harness.get(`/businesses/${businessId}/analytics/daily?days=0`, owner).expect(400);
    });
  });

  describe('small cohorts', () => {
    it('flags a cohort too small to report and publishes the threshold', async () => {
      const businessId = await createBusiness('Small Cohort');
      const placeId = await createPlace('Small Cohort Place');
      await claim(businessId, placeId);
      const questId = await questAt(placeId, 'Small Cohort Quest');
      await submit(questId, { outcome: 'approved' });

      const summary = await summaryOf(businessId);
      expect(summary.minReportableCohort).toBe(MIN_REPORTABLE_COHORT);

      // One visitor plus one public feed post at the same place is two facts
      // that together name somebody.
      const quests = await harness
        .get(`/businesses/${businessId}/analytics/quests`, owner)
        .expect(200);
      const row = quests.body.data.find((r: { questId: string }) => r.questId === questId);
      expect(row.cohortSuppressed).toBe(true);
    });

    it('does not flag a place with no visitors at all', async () => {
      const businessId = await createBusiness('Quiet Cohort');
      const placeId = await createPlace('Quiet Cohort Place');
      await claim(businessId, placeId);

      const places = await harness.get(`/businesses/${businessId}/analytics/places`, owner).expect(200);
      const row = places.body.data.find((r: { placeId: string }) => r.placeId === placeId);
      // Zero is not a small cohort — it identifies nobody.
      expect(row.visitors).toBe(0);
      expect(row.cohortSuppressed).toBe(false);
    });
  });

  describe('who can read it', () => {
    let businessId: string;

    beforeAll(async () => {
      businessId = await createBusiness('Guarded Analytics');
      const placeId = await createPlace('Guarded Place');
      await claim(businessId, placeId);
      const questId = await questAt(placeId, 'Guarded Quest');
      await submit(questId, { outcome: 'approved' });
    });

    const routes = ['summary', 'daily', 'quests', 'places', 'proof'];

    it('refuses a stranger on every route, with a 404', async () => {
      for (const route of routes) {
        await harness.get(`/businesses/${businessId}/analytics/${route}`, stranger).expect(404);
      }
    });

    // The separation that matters: moderating the platform is not the same
    // authority as reading a business's visitors.
    it('refuses a super admin who is not a member, on every route', async () => {
      for (const route of routes) {
        await harness.get(`/businesses/${businessId}/analytics/${route}`, admin).expect(404);
      }
    });

    it('refuses every route once the business is suspended', async () => {
      const suspended = await createBusiness('Suspended Analytics');
      await harness.get(`/businesses/${suspended}/analytics/summary`, owner).expect(200);

      await harness.patch(`/admin/businesses/${suspended}`, admin).send({ status: 'suspended' }).expect(200);

      for (const route of routes) {
        const response = await harness
          .get(`/businesses/${suspended}/analytics/${route}`, owner)
          .expect(403);
        expect(response.body.error.code).toBe('BUSINESS_SUSPENDED');
      }
    });

    it('lets a manager read it without being able to manage the business', async () => {
      const manager = await harness.createUser({ prefix: 'anmgr' });
      await harness
        .post(`/businesses/${businessId}/members`, owner)
        .send({ userId: manager.id, role: 'manager' })
        .expect(204);

      await harness.get(`/businesses/${businessId}/analytics/summary`, manager).expect(200);
      await harness
        .post(`/businesses/${businessId}/members`, manager)
        .send({ userId: stranger.id, role: 'manager' })
        .expect(403);
    });
  });
});
