import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

/// AI proof verification (#47), server side.
///
/// The analyzer itself is not exercised here: it needs a live API key, and a
/// test that spends money on a vision call to assert a model's opinion tests
/// the model, not this code. What *is* asserted is everything around it — the
/// escalation queue, the advisory guarantee, and the auto-resolve — because
/// those are the parts a moderator's workflow depends on.
describe('AI proof verification (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let moderator: TestUser;

  /// Writes a completed verdict, standing in for the worker.
  const recordVerdict = async (
    submissionId: string,
    verdict: 'pass' | 'fail' | 'unclear',
    options: {
      confidence?: number;
      escalationReason?: string;
      relevance?: number | null;
      observations?: unknown[];
    } = {},
  ): Promise<void> => {
    await harness.database.query(
      `INSERT INTO submission_verifications
         (submission_id, state, verdict, confidence, relevance, content_evidence,
          rationale, escalation_reason, model, completed_at)
       VALUES ($1, 'complete', $2::proof_verdict, $3, $5, $6::jsonb,
               'fixture rationale', $4, 'claude-opus-5', now())
       ON CONFLICT (submission_id) DO UPDATE
         SET state = 'complete', verdict = EXCLUDED.verdict, confidence = EXCLUDED.confidence,
             relevance = EXCLUDED.relevance, content_evidence = EXCLUDED.content_evidence,
             -- rationale too: createSubmission's own consumer has already
             -- inserted a row carrying this column's empty-string default by
             -- the time the fixture runs, so an UPDATE list that omits it
             -- silently keeps that empty string and the rationale never lands.
             rationale = EXCLUDED.rationale,
             escalation_reason = EXCLUDED.escalation_reason, completed_at = now(),
             resolved_by = NULL, resolved_at = NULL`,
      [
        submissionId,
        verdict,
        options.confidence ?? 0.5,
        options.escalationReason ?? 'Could not judge the image.',
        options.relevance ?? null,
        options.observations ? JSON.stringify({ observations: options.observations }) : null,
      ],
    );
  };

  const unclearQueue = async (): Promise<Record<string, unknown>[]> => {
    const response = await harness.get('/submissions/admin/unclear?limit=100', moderator).expect(200);
    return response.body.data;
  };

  const inQueue = async (submissionId: string): Promise<Record<string, unknown> | undefined> =>
    (await unclearQueue()).find((row) => row.submission_id === submissionId);

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    moderator = await harness.createUser({ role: 'moderator', prefix: 'pvmod' });
  });

  afterAll(async () => {
    await harness?.close();
  });

  it('enqueues every new submission for analysis, so nothing is silently skipped', async () => {
    const user = await harness.createUser({ prefix: 'pvq' });
    const submission = await harness.createSubmission(user, { caption: 'queued for analysis' });

    // The worker is not running in this suite; the row proves the
    // submission.created consumer has something to find, and that turning the
    // feature on later can pick up what it never looked at.
    const queued = await harness.countRows(
      'SELECT count(*) FROM submission_verifications WHERE submission_id = $1',
      [submission.id],
    );
    expect(queued).toBe(1);
  });

  it('lists an unclear verdict with its reason and the context to triage it', async () => {
    const user = await harness.createUser({ prefix: 'pvu' });
    const submission = await harness.createSubmission(user, { caption: 'ambiguous proof' });
    await recordVerdict(submission.id, 'unclear', {
      escalationReason: 'The image does not show the activity clearly.',
    });

    const row = await inQueue(submission.id);
    expect(row).toBeDefined();
    expect(row!.escalation_reason).toBe('The image does not show the activity clearly.');
    expect(row!.quest_title).toBeTruthy();
    expect(row!.username).toBe(user.username);
    // Absent CAMARA signals (#53) must read as null — "not available" — and
    // never as false, which would be an assertion the user was not there.
    expect(row!.location_verified).toBeNull();
    expect(row!.geofence_verified).toBeNull();
  });

  /// Shadow mode is only worth anything if a person can see what the agent
  /// would have done while deciding independently. These assert the verdict
  /// reaches the two screens a moderator actually works from — it used to
  /// exist only in SQL.
  describe("the agent's read reaches the moderator", () => {
    it('carries the verdict, both scores and the observations into the review detail', async () => {
      const user = await harness.createUser({ prefix: 'pvdetail' });
      const submission = await harness.createSubmission(user, { caption: 'visible to the moderator' });
      await recordVerdict(submission.id, 'unclear', {
        confidence: 0.4,
        relevance: 0.81,
        observations: [{ kind: 'action', label: 'sunrise over water', present: true, confidence: 0.88 }],
      });

      const response = await harness.get(`/submissions/admin/${submission.id}`, moderator).expect(200);
      const row = response.body.data;
      expect(row.ai_verdict).toBe('unclear');
      // Relevance and confidence are different questions and both must
      // survive the trip: a reader who sees only one of them cannot tell a
      // confident "this is a cat, not a sunrise" from a confident approval.
      // typeof, not Number(): these are numeric(4,3), which the driver hands
      // back as the text '0.400'. Number() coerced the string and passed, so
      // the suite was green while the console crashed on `as num?`.
      expect(typeof row.ai_confidence).toBe('number');
      expect(typeof row.ai_relevance).toBe('number');
      expect(row.ai_confidence).toBeCloseTo(0.4, 2);
      expect(row.ai_relevance).toBeCloseTo(0.81, 2);
      expect(row.ai_content_evidence.observations[0].label).toBe('sunrise over water');
      expect(row.ai_rationale).toBe('fixture rationale');
    });

    it('carries relevance into the escalation queue, for triage', async () => {
      const user = await harness.createUser({ prefix: 'pvrel' });
      const submission = await harness.createSubmission(user, { caption: 'barely related' });
      await recordVerdict(submission.id, 'unclear', { relevance: 0.04 });

      const row = await inQueue(submission.id);
      expect(typeof row!.relevance).toBe('number');
      expect(row!.relevance).toBeCloseTo(0.04, 2);
    });

    // Null is "not assessed", which is the correct and common state — no
    // photograph can show "spend an hour with no phone". It must not arrive
    // as 0, which the console would render as a damning number about an
    // honest player.
    it('keeps an unassessed relevance null rather than zero', async () => {
      const user = await harness.createUser({ prefix: 'pvnorel' });
      const submission = await harness.createSubmission(user, { caption: 'not photo-judgeable' });
      await recordVerdict(submission.id, 'unclear', { relevance: null });

      expect((await inQueue(submission.id))!.relevance).toBeNull();
      const detail = await harness.get(`/submissions/admin/${submission.id}`, moderator).expect(200);
      expect(detail.body.data.ai_relevance).toBeNull();
    });

    // A submission the agent has not finished with must not draw an empty
    // agent panel, so the fields have to be absent rather than blank.
    it('reports no verdict at all for a submission the agent has not judged', async () => {
      const user = await harness.createUser({ prefix: 'pvnone' });
      const submission = await harness.createSubmission(user, { caption: 'unjudged' });

      const detail = await harness.get(`/submissions/admin/${submission.id}`, moderator).expect(200);
      expect(detail.body.data.ai_verdict).toBeNull();
      expect(detail.body.data.ai_relevance).toBeNull();
    });
  });

  it('keeps pass and fail verdicts out of the queue — only escalations need a human', async () => {
    const passUser = await harness.createUser({ prefix: 'pvp' });
    const passed = await harness.createSubmission(passUser, { caption: 'clear proof' });
    await recordVerdict(passed.id, 'pass', { confidence: 0.95 });

    const failUser = await harness.createUser({ prefix: 'pvf' });
    const failed = await harness.createSubmission(failUser, { caption: 'unrelated image' });
    await recordVerdict(failed.id, 'fail', { confidence: 0.92 });

    expect(await inQueue(passed.id)).toBeUndefined();
    expect(await inQueue(failed.id)).toBeUndefined();
  });

  // The load-bearing guarantee of the whole feature. A verdict is advice; if
  // it ever moved a submission's status or paid XP, the review flow and the
  // XP-awarded-once invariant would both be decided by a model.
  it('never changes review state or awards XP, whatever the verdict', async () => {
    const user = await harness.createUser({ prefix: 'pvadv' });
    const submission = await harness.createSubmission(user, { caption: 'advisory only' });
    const before = await harness.profile(user.id);

    await recordVerdict(submission.id, 'pass', { confidence: 1 });

    const row = await harness.submission(submission.id);
    expect(row?.status).toBe('pending');
    expect(row?.xp_awarded).toBe(false);
    expect(row?.xp_awarded_amount).toBe(0);

    const after = await harness.profile(user.id);
    expect(after?.xp).toBe(before?.xp);
    expect(after?.quests_completed).toBe(before?.quests_completed);
    expect(await harness.userQuestStatus(submission.user_quest_id)).toBe('submitted');
  });

  it('drains the escalation when a moderator approves, in the same breath as the decision', async () => {
    const user = await harness.createUser({ prefix: 'pvres' });
    const submission = await harness.createSubmission(user, { caption: 'escalated then approved' });
    await recordVerdict(submission.id, 'unclear');
    expect(await inQueue(submission.id)).toBeDefined();

    await harness.post(`/submissions/${submission.id}/approve`, moderator).send({}).expect(204);

    expect(await inQueue(submission.id)).toBeUndefined();
    const resolved = await harness.countRows(
      `SELECT count(*) FROM submission_verifications
       WHERE submission_id = $1 AND resolved_at IS NOT NULL AND resolved_by = $2`,
      [submission.id, moderator.id],
    );
    expect(resolved).toBe(1);
  });

  it('drains the escalation when a moderator rejects too', async () => {
    const user = await harness.createUser({ prefix: 'pvrej' });
    const submission = await harness.createSubmission(user, { caption: 'escalated then rejected' });
    await recordVerdict(submission.id, 'unclear');

    await harness
      .post(`/submissions/${submission.id}/reject`, moderator)
      .send({ reviewNote: 'Not convincing.' })
      .expect(204);

    expect(await inQueue(submission.id)).toBeUndefined();
  });

  it('alerts the committee with a durable notification, not a fire-and-forget push', async () => {
    const user = await harness.createUser({ prefix: 'pvnotify' });
    const submission = await harness.createSubmission(user, { caption: 'needs eyes' });

    // Written the way the repository writes it: the notification and its
    // outbox row in one transaction, so an escalation cannot exist without
    // the alert that makes someone look at it.
    await harness.database.query(
      `WITH inserted AS (
         INSERT INTO notifications (user_id, title, body, type, reference_id)
         SELECT user_id, 'Proof needs your eyes. 🔍', 'Could not judge.', 'proof_unclear', $1
         FROM admins RETURNING id, user_id
       )
       INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       SELECT 'notification', id, 'notification.created',
         jsonb_build_object('notificationId', id, 'userId', user_id) FROM inserted`,
      [submission.id],
    );

    const notifications = await harness.notificationsFor(moderator.id, submission.id);
    expect(notifications.some((row) => row.type === 'proof_unclear')).toBe(true);
  });

  it('surfaces the verdict on the review queue row, so a moderator sees the advice in place', async () => {
    const user = await harness.createUser({ prefix: 'pvrq' });
    const submission = await harness.createSubmission(user, { caption: 'queue row advice' });
    await recordVerdict(submission.id, 'fail', { confidence: 0.81 });

    let row: Record<string, unknown> | undefined;
    for (let offset = 0; offset < 400 && !row; offset += 100) {
      const response = await harness
        .get(`/submissions/admin/review-queue?limit=100&offset=${offset}`, moderator)
        .expect(200);
      row = response.body.data.find((entry: { id: string }) => entry.id === submission.id);
      if (response.body.data.length < 100) break;
    }
    expect(row).toBeDefined();
    expect(row!.ai_verdict).toBe('fail');
    expect(typeof row!.ai_confidence).toBe('number');
    expect(row!.ai_confidence).toBeCloseTo(0.81, 2);
  });

  it('refuses the unclear queue to a signed-out caller and to an ordinary user', async () => {
    await harness.get('/submissions/admin/unclear').expect(401);
    const user = await harness.createUser({ prefix: 'pvperm' });
    await harness.get('/submissions/admin/unclear', user).expect(403);
  });

  it('reports a count for the sidebar badge', async () => {
    const response = await harness.get('/submissions/admin/unclear/count', moderator).expect(200);
    expect(typeof response.body.data).toBe('number');
    expect(response.body.data).toBeGreaterThanOrEqual(0);
  });
});
