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

  /// Creates a business and subscribes it to analytics.
  ///
  /// The subscription is not implied by existing (#50's whitelist), so
  /// without this every case here would get ANALYTICS_NOT_SUBSCRIBED. The
  /// entitlement itself is tested in its own block below, with a business
  /// deliberately left unsubscribed.
  const createBusiness = async (name: string, subscribe = true): Promise<string> => {
    const response = await harness
      .post('/admin/businesses', admin)
      .send({ name: named(name), ownerUserId: owner.id })
      .expect(201);
    const id = response.body.data.id;
    if (subscribe) {
      await harness
        .patch(`/admin/businesses/${id}`, admin)
        .send({ analyticsSubscribed: true })
        .expect(200);
    }
    return id;
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


  /// Removes the places this run created.
  ///
  /// Not tidiness — correctness for other suites. `GET /map/places` is
  /// capped at 100 rows, so every place left behind here pushes somebody
  /// else's fixture off the first page. Against a long-lived database the
  /// map suite eventually stops finding its own place and fails for a
  /// reason that has nothing to do with the map. CI never sees it, because
  /// CI gets a fresh database; a developer's machine does.
  const removeFixturePlaces = async (): Promise<void> => {
    if (!harness) return;
    const scoped = 'SELECT id FROM map_places WHERE name LIKE $1';
    const pattern = `%${tag}`;
    for (const table of [
      'business_places',
      'quest_destinations',
      'saved_map_places',
      'geofencing_subscriptions',
      'map_location_evidence',
    ]) {
      await harness.database.query(
        `DELETE FROM ${table} WHERE place_id IN (${scoped})`,
        [pattern],
      );
    }
    await harness.database.query('DELETE FROM map_places WHERE name LIKE $1', [pattern]);
  };

  afterAll(async () => {
    await removeFixturePlaces();
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

  /// #50's "dynamic whitelist ... every business subscribed with bsheel
  /// analytics". Before this existed, `businesses.status` was standing in
  /// for entitlement, so every business that existed got the full dashboard.
  describe('the analytics subscription', () => {
    const routes = ['summary', 'daily', 'quests', 'places', 'countries', 'proof'];

    it('refuses every route for a business that is not subscribed', async () => {
      const unsubscribed = await createBusiness('Not Subscribed', false);
      const placeId = await createPlace('Unsubscribed Place');
      await claim(unsubscribed, placeId);

      for (const route of routes) {
        const response = await harness
          .get(`/businesses/${unsubscribed}/analytics/${route}`, owner)
          .expect(403);
        expect(response.body.error.code, route).toBe('ANALYTICS_NOT_SUBSCRIBED');
      }
    });

    // The member must still reach their own account while unsubscribed, or
    // the app cannot tell them what they are missing or who they are.
    it('leaves the rest of the business API reachable without a subscription', async () => {
      const unsubscribed = await createBusiness('Still Reachable', false);

      await harness.get(`/businesses/${unsubscribed}`, owner).expect(200);
      await harness.get(`/businesses/${unsubscribed}/places`, owner).expect(200);
      const mine = await harness.get('/businesses/me', owner).expect(200);
      expect(mine.body.data.map((row: { id: string }) => row.id)).toContain(unsubscribed);
    });

    it('opens on subscribe and closes again on revoke', async () => {
      const business = await createBusiness('Toggled Subscription', false);
      await harness.get(`/businesses/${business}/analytics/summary`, owner).expect(403);

      await harness
        .patch(`/admin/businesses/${business}`, admin)
        .send({ analyticsSubscribed: true })
        .expect(200);
      await harness.get(`/businesses/${business}/analytics/summary`, owner).expect(200);

      await harness
        .patch(`/admin/businesses/${business}`, admin)
        .send({ analyticsSubscribed: false })
        .expect(200);
      await harness.get(`/businesses/${business}/analytics/summary`, owner).expect(403);
    });

    // Entitlement and moderation are different acts. Changing the status of
    // a subscribed business must not silently cancel its subscription.
    it('keeps the subscription across a suspension', async () => {
      const business = await createBusiness('Suspended But Paid');

      await harness.patch(`/admin/businesses/${business}`, admin).send({ status: 'suspended' }).expect(200);
      const suspended = await harness
        .get(`/businesses/${business}/analytics/summary`, owner)
        .expect(403);
      // Suspension is the reason, not a lapsed subscription.
      expect(suspended.body.error.code).toBe('BUSINESS_SUSPENDED');

      await harness.patch(`/admin/businesses/${business}`, admin).send({ status: 'active' }).expect(200);
      await harness.get(`/businesses/${business}/analytics/summary`, owner).expect(200);
    });

    // Re-granting must not reset the start date a billing period would be
    // measured from.
    it('does not move the subscription date when granted twice', async () => {
      const business = await createBusiness('Regranted');
      const first = await harness.database.query<{ at: Date }>(
        'SELECT analytics_subscribed_at AS at FROM businesses WHERE id = $1',
        [business],
      );

      await harness
        .patch(`/admin/businesses/${business}`, admin)
        .send({ analyticsSubscribed: true })
        .expect(200);

      const second = await harness.database.query<{ at: Date }>(
        'SELECT analytics_subscribed_at AS at FROM businesses WHERE id = $1',
        [business],
      );
      expect(second.rows[0].at.toISOString()).toBe(first.rows[0].at.toISOString());
    });

    it('is not granted merely by existing', async () => {
      const fresh = await createBusiness('Default Off', false);
      const row = await harness.database.query<{ at: Date | null }>(
        'SELECT analytics_subscribed_at AS at FROM businesses WHERE id = $1',
        [fresh],
      );
      expect(row.rows[0].at).toBeNull();
    });
  });

  /// #50's "country touristic analytics". The care here is all about not
  /// reporting a number the business would misread.
  describe('where visitors come from', () => {
    /// A visitor who declared a country, optionally consenting to its use.
    const visitorFrom = async (
      questId: string,
      countryCode: string | null,
      consented: boolean,
    ): Promise<void> => {
      const author = await harness.createUser({ prefix: 'anorigin' });
      if (countryCode) {
        await harness.patch('/profiles/me', author).send({ countryCode }).expect(200);
      }
      if (consented) {
        await harness.patch('/profiles/me/analytics-consent', author).send({ consented: true }).expect(200);
      }
      const submission = await harness.createSubmission(author, {
        questId,
        caption: named('origin proof'),
      });
      await harness.post(`/submissions/${submission.id}/approve`, moderator).send({}).expect(204);
    };

    const originsOf = async (businessId: string) =>
      (await harness.get(`/businesses/${businessId}/analytics/countries`, owner).expect(200)).body.data;

    it('reports a country once enough visitors have declared it', async () => {
      const business = await createBusiness('Origins Reported');
      const placeId = await createPlace('Origins Place');
      await claim(business, placeId);
      const questId = await questAt(placeId, 'Origins Quest');

      for (let i = 0; i < MIN_REPORTABLE_COHORT; i += 1) await visitorFrom(questId, 'LB', true);

      const origins = await originsOf(business);
      expect(origins.visitors).toBe(MIN_REPORTABLE_COHORT);
      expect(origins.disclosed).toBe(MIN_REPORTABLE_COHORT);
      expect(origins.countries).toHaveLength(1);
      expect(origins.countries[0]).toMatchObject({
        countryCode: 'LB',
        visitors: MIN_REPORTABLE_COHORT,
        shareOfDisclosed: 1,
      });
    });

    // The case that protects a person. One visitor from a country, plus one
    // public feed post at the same place, names them.
    it('never names a country with too few visitors to hide in', async () => {
      const business = await createBusiness('Origins Suppressed');
      const placeId = await createPlace('Suppressed Origins Place');
      await claim(business, placeId);
      const questId = await questAt(placeId, 'Suppressed Origins Quest');

      await visitorFrom(questId, 'QA', true);
      await visitorFrom(questId, 'AE', true);

      const origins = await originsOf(business);
      expect(origins.countries).toEqual([]);
      // Collapsed rather than dropped, so the figures still reconcile
      // against `disclosed` instead of quietly failing to add up.
      expect(origins.suppressedCountries).toBe(2);
      expect(origins.suppressedVisitors).toBe(2);
      expect(origins.disclosed).toBe(2);
    });

    // Completing a quest at a place is not consent to be counted by its
    // owner. The person came for the quest.
    it('treats a declared country without analytics consent as undisclosed', async () => {
      const business = await createBusiness('Origins Unconsented');
      const placeId = await createPlace('Unconsented Place');
      await claim(business, placeId);
      const questId = await questAt(placeId, 'Unconsented Quest');

      for (let i = 0; i < MIN_REPORTABLE_COHORT; i += 1) await visitorFrom(questId, 'LB', false);

      const origins = await originsOf(business);
      expect(origins.visitors).toBe(MIN_REPORTABLE_COHORT);
      expect(origins.disclosed).toBe(0);
      expect(origins.undisclosed).toBe(MIN_REPORTABLE_COHORT);
      expect(origins.countries).toEqual([]);
    });

    /// The honesty property. A business shown "Lebanon 100%" over five
    /// disclosed visitors, when forty people came, would be reading a
    /// tenth of its traffic as all of it.
    it('states how much of its visitor base it cannot account for', async () => {
      const business = await createBusiness('Origins Partial');
      const placeId = await createPlace('Partial Origins Place');
      await claim(business, placeId);
      const questId = await questAt(placeId, 'Partial Origins Quest');

      for (let i = 0; i < MIN_REPORTABLE_COHORT; i += 1) await visitorFrom(questId, 'LB', true);
      await visitorFrom(questId, null, false);
      await visitorFrom(questId, null, false);

      const origins = await originsOf(business);
      expect(origins.visitors).toBe(MIN_REPORTABLE_COHORT + 2);
      expect(origins.disclosed).toBe(MIN_REPORTABLE_COHORT);
      expect(origins.undisclosed).toBe(2);
      // Never apportioned across the buckets to make them look complete.
      expect(origins.countries[0].visitors).toBe(MIN_REPORTABLE_COHORT);
    });

    it('reports nobody for a business with no visitors', async () => {
      const business = await createBusiness('Origins Empty');

      const origins = await originsOf(business);
      expect(origins).toMatchObject({
        visitors: 0,
        disclosed: 0,
        undisclosed: 0,
        suppressedCountries: 0,
        suppressedVisitors: 0,
      });
      expect(origins.countries).toEqual([]);
    });

    it('counts a repeat visitor once, from one country', async () => {
      const business = await createBusiness('Origins Repeat');
      const placeId = await createPlace('Repeat Origins Place');
      await claim(business, placeId);
      const questId = await questAt(placeId, 'Repeat Origins Quest');
      const second = await questAt(placeId, 'Repeat Origins Quest Two');

      const author = await harness.createUser({ prefix: 'anrepeat' });
      await harness.patch('/profiles/me', author).send({ countryCode: 'LB' }).expect(200);
      await harness.patch('/profiles/me/analytics-consent', author).send({ consented: true }).expect(200);
      for (const quest of [questId, second]) {
        const submission = await harness.createSubmission(author, { questId: quest });
        await harness.post(`/submissions/${submission.id}/approve`, moderator).send({}).expect(204);
      }

      const origins = await originsOf(business);
      // Two completions, one person.
      expect(origins.visitors).toBe(1);
      expect((await summaryOf(business)).completions).toBe(2);
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

    const routes = ['summary', 'daily', 'quests', 'places', 'countries', 'proof'];

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
