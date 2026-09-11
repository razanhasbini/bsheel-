import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AgentRunsRepository } from '../src/modules/agent/infrastructure/agent-runs.repository.js';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

/// The recoverable half of "CAMARA was unavailable" (#15).
///
/// "fallback to human or pend them till camara gives results back" — the
/// first half always worked, since every provider failure folds to
/// UNAVAILABLE and finalizeDecision turns that into HUMAN_REVIEW rather than
/// a rejection. This is the second half.
///
/// The whole design rests on one distinction, and most of these cases exist
/// to pin it: **only geofencing is retryable.** Location verification and
/// retrieval ask where the device is *now*, so re-asking about a quest window
/// that has closed answers a different question and recording it as evidence
/// would be inventing proof of presence. Geofencing is a replay of stored
/// webhook events, which really can arrive late.
describe('late CAMARA evidence (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let runs: AgentRunsRepository;
  let moderator: TestUser;
  /// One place for every subscription in this suite. The subscription needs a
  /// real `place_id` and `map_places` starts empty; which place it is does not
  /// matter, since the sweep keys off the assignment rather than the geometry.
  let placeId: string;

  /// A submission with a subscription, an agent run, and one network-evidence
  /// row for `capability` recorded at `observedAt`.
  const withEvidence = async (options: {
    capability: 'GEOFENCING' | 'LOCATION_VERIFICATION' | 'LOCATION_RETRIEVAL';
    outcome: 'SUPPORTED' | 'CONTRADICTED' | 'UNAVAILABLE';
    observedMinutesAgo: number;
  }): Promise<{ submissionId: string; userQuestId: string; subscriptionId: string }> => {
    const author = await harness.createUser({ prefix: 'recov' });
    const submission = await harness.createSubmission(author, { caption: 'awaiting evidence' });
    const userQuestId = (await harness.database.query<{ user_quest_id: string }>(
      'SELECT user_quest_id FROM submissions WHERE id = $1',
      [submission.id],
    )).rows[0].user_quest_id;

    const subscription = (await harness.database.query<{ id: string }>(
      `INSERT INTO geofencing_subscriptions
         (user_quest_id, place_id, callback_secret, status, starts_at, expires_at)
       VALUES ($1, $2, 'secret', 'active',
               now() - interval '2 hours', now() + interval '2 hours')
       RETURNING id`,
      [userQuestId, placeId],
    )).rows[0];

    const run = (await harness.database.query<{ id: string }>(
      `INSERT INTO agent_runs
         (kind, subject_type, subject_id, idempotency_key, status, model,
          prompt_version, policy_version, input_snapshot, started_at, completed_at)
       VALUES ('submission_verification', 'submission', $1, $2, 'succeeded', 'test',
               'v1', 'v1', '{}'::jsonb, now(), now())
       RETURNING id`,
      [submission.id, `recovery:${submission.id}`],
    )).rows[0];

    await harness.database.query(
      `INSERT INTO network_evidence
         (agent_run_id, user_quest_id, submission_id, capability, provider,
          provider_reference, outcome, result, observed_at)
       VALUES ($1, $2, $3, $4, 'nokia-network-as-code', $5, $6, '{}'::jsonb,
               now() - make_interval(mins => $7))`,
      [run.id, userQuestId, submission.id, options.capability,
       `ref-${submission.id}-${options.capability}`, options.outcome, options.observedMinutesAgo],
    );

    return { submissionId: submission.id, userQuestId, subscriptionId: subscription.id };
  };

  /// A geofence event that happened during the quest but reached us `lateBy`
  /// minutes ago — the split between `occurred_at` and `received_at` that
  /// makes this recoverable at all.
  const lateEvent = (subscriptionId: string, receivedMinutesAgo: number) =>
    harness.database.query(
      `INSERT INTO geofencing_events
         (subscription_id, event_type, occurred_at, received_at, provider_event_id)
       VALUES ($1, 'ENTER', now() - interval '90 minutes',
               now() - make_interval(mins => $2), $3)`,
      [subscriptionId, receivedMinutesAgo, `ev-${subscriptionId}-${receivedMinutesAgo}`],
    );

  const candidates = async () =>
    (await runs.submissionsWithLateGeofenceEvidence(200)).map((row) => row.submissionId);

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    runs = new AgentRunsRepository(harness.database);
    moderator = await harness.createUser({ role: 'moderator', prefix: 'recovmod' });
    placeId = (await harness.database.query<{ id: string }>(
      `INSERT INTO map_places (country_code, name, category, latitude, longitude, is_published)
       VALUES ('LB', 'Recovery sweep fixture', 'landmark', 33.8938, 35.5018, true)
       RETURNING id`,
    )).rows[0].id;
  });

  afterAll(async () => {
    await harness?.close();
  });

  it('offers a submission whose geofence event arrived after the agent gave up', async () => {
    const subject = await withEvidence({
      capability: 'GEOFENCING', outcome: 'UNAVAILABLE', observedMinutesAgo: 60,
    });
    await lateEvent(subject.subscriptionId, 5);

    expect(await candidates()).toContain(subject.submissionId);
  });

  it('offers one whose geofence evidence contradicted completion, then an entry landed', async () => {
    const subject = await withEvidence({
      capability: 'GEOFENCING', outcome: 'CONTRADICTED', observedMinutesAgo: 60,
    });
    await lateEvent(subject.subscriptionId, 5);

    expect(await candidates()).toContain(subject.submissionId);
  });

  it('ignores one where the event was already in hand when the agent ran', async () => {
    const subject = await withEvidence({
      capability: 'GEOFENCING', outcome: 'UNAVAILABLE', observedMinutesAgo: 5,
    });
    // Received an hour ago, evidence observed five minutes ago: nothing new.
    await lateEvent(subject.subscriptionId, 60);

    expect(await candidates()).not.toContain(subject.submissionId);
  });

  it('ignores one whose geofence evidence already supported completion', async () => {
    const subject = await withEvidence({
      capability: 'GEOFENCING', outcome: 'SUPPORTED', observedMinutesAgo: 60,
    });
    await lateEvent(subject.subscriptionId, 5);

    expect(await candidates()).not.toContain(subject.submissionId);
  });

  // The distinction the whole feature turns on. These two capabilities ask
  // where the device is NOW. Re-asking tomorrow about a quest that ended
  // yesterday answers a different question, and recording that answer as
  // evidence for the old window would be fabricating proof of presence — so
  // an unavailable location check stays with a human, permanently, even
  // though a geofence event for the same assignment has since arrived.
  it('never retries location verification or retrieval, however much new evidence lands', async () => {
    for (const capability of ['LOCATION_VERIFICATION', 'LOCATION_RETRIEVAL'] as const) {
      const subject = await withEvidence({
        capability, outcome: 'UNAVAILABLE', observedMinutesAgo: 60,
      });
      await lateEvent(subject.subscriptionId, 5);

      expect(await candidates(), capability).not.toContain(subject.submissionId);
    }
  });

  // Once a person has decided, late evidence is a matter for an appeal, not
  // a silent re-run that could overturn their call.
  it('stops offering it once a human has decided', async () => {
    const subject = await withEvidence({
      capability: 'GEOFENCING', outcome: 'UNAVAILABLE', observedMinutesAgo: 60,
    });
    await lateEvent(subject.subscriptionId, 5);
    expect(await candidates()).toContain(subject.submissionId);

    await harness.post(`/submissions/${subject.submissionId}/approve`, moderator).send({}).expect(204);

    expect(await candidates()).not.toContain(subject.submissionId);
  });

  it('reports the newest event, so the idempotency key moves only when evidence does', async () => {
    const subject = await withEvidence({
      capability: 'GEOFENCING', outcome: 'UNAVAILABLE', observedMinutesAgo: 60,
    });
    await lateEvent(subject.subscriptionId, 30);
    const first = (await runs.submissionsWithLateGeofenceEvidence(200))
      .find((row) => row.submissionId === subject.submissionId);
    expect(first?.latestEventId).toBeTruthy();

    // A second, newer event moves the generation; the same event would not.
    await lateEvent(subject.subscriptionId, 2);
    const second = (await runs.submissionsWithLateGeofenceEvidence(200))
      .find((row) => row.submissionId === subject.submissionId);
    expect(second?.latestEventId).not.toBe(first?.latestEventId);
  });
});
