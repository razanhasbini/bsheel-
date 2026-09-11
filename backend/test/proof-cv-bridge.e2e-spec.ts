import { ConfigService } from '@nestjs/config';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { LocalCvEvidenceProvider } from '../src/integrations/computer-vision/local-cv-evidence.provider.js';
import { AgentContextService } from '../src/modules/agent/application/agent-context.service.js';
import type { CvEvidenceAnalysisInput } from '../src/modules/agent/domain/cv-evidence.port.js';
import { AgentContextRepository } from '../src/modules/agent/infrastructure/agent-context.repository.js';
import { ProofVerificationRepository } from '../src/modules/submissions/infrastructure/proof-verification.repository.js';
import { E2eHarness } from './support/e2e-harness.js';

/// The bridge between the two verifiers (#47 + #53), against a real database.
///
/// The mapping itself is unit-tested in cv-evidence-bridge.spec.ts. What needs
/// a database is everything the mapping trusts: that `relevance` comes back a
/// number and not the string '0.420' that `numeric(4,3)` actually sends over
/// the wire, that the observation list survives a jsonb round trip, and that
/// the agent's context carries the quest's verification contract resolved
/// through the same view the vision cascade reads.
describe('the vision pass as CV evidence (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let repository: ProofVerificationRepository;
  let provider: LocalCvEvidenceProvider;
  let contexts: AgentContextService;

  /// Stands in for the worker: writes what the cascade would have written.
  ///
  /// `verdict` and `completed_at` follow the state rather than being passed
  /// in, because `submission_verifications_verdict_state_check` enforces the
  /// pairing — a non-complete row carrying a verdict is rejected, which is
  /// the schema being right and is worth not working around in a fixture.
  const recordFinding = async (
    submissionId: string,
    options: { relevance?: number | null; observations?: unknown[]; state?: string } = {},
  ): Promise<void> => {
    const state = options.state ?? 'complete';
    const complete = state === 'complete';
    await harness.database.query(
      `INSERT INTO submission_verifications
         (submission_id, state, verdict, confidence, relevance, content_evidence,
          rationale, model, stage, completed_at)
       VALUES ($1, $2, $5::proof_verdict, 0.910, $3, $4::jsonb,
               'fixture rationale', 'gpt-5.6-luna', 'triage',
               CASE WHEN $5::proof_verdict IS NULL THEN NULL ELSE now() END)
       ON CONFLICT (submission_id) DO UPDATE
         SET state = EXCLUDED.state, verdict = EXCLUDED.verdict, confidence = EXCLUDED.confidence,
             relevance = EXCLUDED.relevance, content_evidence = EXCLUDED.content_evidence,
             model = EXCLUDED.model, stage = EXCLUDED.stage,
             completed_at = EXCLUDED.completed_at`,
      [
        submissionId,
        state,
        options.relevance === undefined ? 0.42 : options.relevance,
        options.observations
          ? JSON.stringify({ observations: options.observations })
          : null,
        complete ? 'pass' : null,
      ],
    );
  };

  const analyse = (
    submissionId: string,
    verifiability: CvEvidenceAnalysisInput['task']['verifiability'],
  ) =>
    provider.analyze({
      runId: '33333333-3333-4333-8333-333333333333',
      submissionId,
      media: [],
      requirements: { actions: [], objects: [], landmarks: [] },
      task: {
        title: 'Fixture quest',
        description: 'Fixture description',
        category: 'adventure',
        evidenceRubric: 'Expect the place or the moment.',
        verifiability,
      },
      maxKeyFrames: 12,
      idempotencyKey: `${submissionId}:cv:test`,
    });

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    repository = harness.app.get(ProofVerificationRepository);
    // AgentModule — and with it ComputerVisionModule and AgentContextService —
    // is wired onto WorkerModule, not the API app this harness boots, because
    // the agent runs on the worker. Both classes take only constructor
    // injection, so they are built here against the harness's real database
    // rather than booting a second application to reach them. What is being
    // tested is the SQL and the mapping; the DI selection has its own
    // assertions in cv-evidence-bridge.spec.ts.
    provider = new LocalCvEvidenceProvider(repository);
    contexts = new AgentContextService(
      new AgentContextRepository(harness.database),
      harness.app.get(ConfigService),
    );
  });

  afterAll(async () => {
    await harness?.close();
  });

  // The trap this test exists for: node-postgres hands `numeric` back as a
  // string to avoid losing precision, so a threshold comparison against the
  // raw column value silently compares a number with '0.420'. `0.42 < 0.35`
  // is false and `'0.420' < 0.35` is also false — the bug would not throw, it
  // would just never fire the relevance gate.
  it('reads relevance back as a number, not the string the driver sends', async () => {
    const user = await harness.createUser({ prefix: 'cvnum' });
    const submission = await harness.createSubmission(user, { caption: 'relevance round trip' });
    await recordFinding(submission.id, { relevance: 0.42 });

    const finding = await repository.contentEvidenceFor(submission.id);
    expect(typeof finding?.relevance).toBe('number');
    expect(finding?.relevance).toBeCloseTo(0.42, 3);
    expect(typeof finding?.confidence).toBe('number');
  });

  it('round-trips the observation list through jsonb', async () => {
    const user = await harness.createUser({ prefix: 'cvobs' });
    const submission = await harness.createSubmission(user, { caption: 'observations' });
    await recordFinding(submission.id, {
      observations: [
        { kind: 'action', label: 'sunrise over water', present: true, confidence: 0.88 },
        { kind: 'object', label: 'a clock face', present: false, confidence: 0.6 },
      ],
    });

    const finding = await repository.contentEvidenceFor(submission.id);
    expect(finding?.observations).toHaveLength(2);
    expect(finding?.observations[1]).toEqual({
      kind: 'object',
      label: 'a clock face',
      present: false,
      confidence: 0.6,
    });
  });

  it('hands the agent AVAILABLE evidence with relevance and typed detections', async () => {
    const user = await harness.createUser({ prefix: 'cvok' });
    const submission = await harness.createSubmission(user, { caption: 'available' });
    await recordFinding(submission.id, {
      relevance: 0.77,
      observations: [{ kind: 'landmark', label: 'a pier', present: true, confidence: 0.8 }],
    });

    const evidence = await analyse(submission.id, 'content');
    expect(evidence.status).toBe('AVAILABLE');
    expect(evidence.relevance).toBeCloseTo(0.77, 3);
    expect(evidence.detections).toEqual([
      { type: 'LANDMARK', label: 'a pier', present: true, confidence: 0.8, timestampsMs: [] },
    ]);
  });

  // The stored number exists; the contract says it is not admissible. A
  // photograph cannot show "spend an hour with no phone", so passing a 0.02
  // downstream would invite exactly the confident rejection of an honest
  // player that the verification contract was introduced to prevent.
  it('withholds a stored relevance when the quest contract forbids using it', async () => {
    const user = await harness.createUser({ prefix: 'cvnone' });
    const submission = await harness.createSubmission(user, { caption: 'unverifiable' });
    await recordFinding(submission.id, { relevance: 0.02 });

    const evidence = await analyse(submission.id, 'none');
    expect(evidence.status).toBe('AVAILABLE');
    expect(evidence.relevance).toBeUndefined();
    expect(evidence.warnings.join(' ')).toContain('never treat the absence of visible proof as evidence');
  });

  // Fail-closed, and the reason the whole pipeline was escalating everything
  // before this bridge existed: no finding means nobody looked at the media,
  // which finalizeDecision turns into HUMAN_REVIEW rather than a guess.
  it('is UNAVAILABLE for a submission the cascade has not finished', async () => {
    const user = await harness.createUser({ prefix: 'cvpend' });
    const submission = await harness.createSubmission(user, { caption: 'not analysed' });

    // createSubmission's own outbox consumer is not running in this suite, so
    // the row is whatever `enqueue` left: state 'queued', no finding.
    const evidence = await analyse(submission.id, 'content');
    expect(evidence.status).toBe('UNAVAILABLE');
    expect(evidence.relevance).toBeUndefined();
    expect(evidence.detections).toEqual([]);
  });

  // Same guard, against a real row: a pass that finished with nothing to say
  // about the media is not evidence, whatever its state column reads.
  it('is UNAVAILABLE when a completed pass assessed nothing', async () => {
    const user = await harness.createUser({ prefix: 'cvempty' });
    const submission = await harness.createSubmission(user, { caption: 'completed but empty' });
    await recordFinding(submission.id, { relevance: null });

    expect((await analyse(submission.id, 'content')).status).toBe('UNAVAILABLE');
    // The same row is fine for a quest no photograph could have shown.
    expect((await analyse(submission.id, 'provenance_only')).status).toBe('AVAILABLE');
  });

  it('reports a failed pass as FAILED, distinctly from one that never ran', async () => {
    const user = await harness.createUser({ prefix: 'cvfail' });
    const submission = await harness.createSubmission(user, { caption: 'failed pass' });
    await recordFinding(submission.id, { state: 'failed', relevance: null });

    expect((await analyse(submission.id, 'content')).status).toBe('FAILED');
  });

  /// The agent's own context must carry the quest's contract, or the deciding
  /// agent is back to judging every quest as though a photograph could settle
  /// it — and `finalizeDecision` is back to ignoring the authority that
  /// migration 0034 deliberately withheld.
  describe('the agent context carries the verification contract', () => {
    it('resolves the category default and the per-quest authority override', async () => {
      const user = await harness.createUser({ prefix: 'cvctx' });
      const quest = await harness.createQuest({ category: 'learning' });
      const submission = await harness.createSubmission(user, { questId: quest.id, caption: 'contract' });

      const context = await contexts.forSubmissionVerification(submission.id);
      // 'learning' is seeded provenance_only: what was learned is not visible
      // in a photograph.
      expect(context?.quest.verification.verifiability).toBe('provenance_only');
      // The harness writes a fail-closed per-quest override.
      expect(context?.quest.verification.mayAutoApprove).toBe(false);
      expect(context?.quest.verification.mayAutoReject).toBe(false);
      expect(context?.quest.verification.evidenceRubric.length).toBeGreaterThan(0);
    });

    // The override above only proves anything if the default differs, so
    // assert the pair. 'learning' is seeded may_auto_approve = true, which is
    // what an inheriting quest resolves to — so false on the quest above is
    // the override being honoured rather than a coincidence.
    it('shows the override differing from the default it overrides', async () => {
      const user = await harness.createUser({ prefix: 'cvinherit' });
      const quest = await harness.createQuest({ category: 'learning', verificationAuthority: 'inherit' });
      const submission = await harness.createSubmission(user, { questId: quest.id, caption: 'inherited' });

      const context = await contexts.forSubmissionVerification(submission.id);
      expect(context?.quest.verification.mayAutoApprove).toBe(true);
      // Rejection authority is withheld at the category level too, so it is
      // false either way — and that is the point of the seeding.
      expect(context?.quest.verification.mayAutoReject).toBe(false);
    });

    it('resolves a content-verifiable category as such', async () => {
      const user = await harness.createUser({ prefix: 'cvctxc' });
      const quest = await harness.createQuest({ category: 'adventure' });
      const submission = await harness.createSubmission(user, { questId: quest.id, caption: 'content quest' });

      const context = await contexts.forSubmissionVerification(submission.id);
      expect(context?.quest.verification.verifiability).toBe('content');
    });

    // Every category is seeded with may_auto_reject = false on purpose:
    // authority to tell a player their proof is fake is earned from a measured
    // precision number, not granted by enabling a feature.
    it('grants no rejection authority anywhere in the seeded catalogue', async () => {
      const rows = await harness.database.query<{ category: string; may_auto_reject: boolean }>(
        'SELECT category, may_auto_reject FROM quest_verification_defaults',
      );
      expect(rows.rows.length).toBeGreaterThan(0);
      expect(rows.rows.every((row) => row.may_auto_reject === false)).toBe(true);
    });
  });

  // Named, so the assertion pins the relevance range check rather than
  // passing on any error at all — a typo in the fixture SQL would otherwise
  // satisfy it.
  it('refuses a relevance outside 0..1 at the database', async () => {
    const user = await harness.createUser({ prefix: 'cvchk' });
    const submission = await harness.createSubmission(user, { caption: 'out of range' });
    await expect(recordFinding(submission.id, { relevance: 1.5 })).rejects.toThrow(
      /submission_verifications_relevance_check/,
    );
  });
});
