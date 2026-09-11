import { Inject, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
import { decide, nextTier, type PolicyOutcome } from '../domain/proof-policy.js';
import {
  applyConfidenceFloor,
  type LocationSignals,
  type ProofAnalysis,
  type ProofAnalyzer,
  type ProofTier,
} from '../domain/proof-verification.types.js';
import { PROOF_ANALYZER } from '../infrastructure/proof-analyzer.token.js';
import { ProofVerificationRepository } from '../infrastructure/proof-verification.repository.js';
import { SubmissionsRepository } from '../infrastructure/submissions.repository.js';
import { ProofProvenanceService } from './proof-provenance.service.js';

/// The AI proof verification cascade (#47).
///
/// Order matters, and it is the whole design:
///
///   1. Deterministic provenance. Free, every submission. Settles the
///      recycled, stolen and generated cases without a model, and settles
///      *every* case for quests a photograph cannot verify.
///   2. Cheap triage, only if the quest's contract says content can decide.
///   3. A better model, only where triage could not.
///   4. The most capable model, only before a rejection.
///
/// Most submissions stop at 1 or 2. The rungs differ ~50x in price, so that
/// is the difference between a feature that pays for itself and one that does
/// not.
///
/// Nothing here decides policy. `domain/proof-policy.ts` owns that, so the
/// question "what is the agent allowed to conclude" has exactly one answer in
/// one readable place.
@Injectable()
export class ProofVerificationService {
  private readonly logger = new Logger(ProofVerificationService.name);

  constructor(
    private readonly repository: ProofVerificationRepository,
    private readonly submissions: SubmissionsRepository,
    private readonly provenance: ProofProvenanceService,
    @Inject(PROOF_ANALYZER) private readonly analyzer: ProofAnalyzer,
    private readonly config: ConfigService<Environment, true>,
  ) {}

  /// Analyses one submission. Safe to call more than once for the same id.
  async verify(submissionId: string): Promise<void> {
    if (!this.analyzer.enabled) {
      // Recorded rather than ignored, so enabling the feature later can find
      // everything it never looked at.
      await this.repository.enqueue(submissionId);
      return;
    }

    await this.repository.enqueue(submissionId);
    const subject = await this.repository.claim(
      submissionId,
      this.config.get('AI_VERIFICATION_MAX_ATTEMPTS', { infer: true }),
      this.config.get('AI_VERIFICATION_CLAIM_LEASE_SECONDS', { infer: true }),
    );
    // Null means already analysed, out of attempts, or claimed by another
    // worker whose lease has not expired. All three are correct no-ops —
    // and the last one is only true now that the claim is a lease.
    if (!subject) return;

    if (subject.status !== 'pending') {
      await this.repository.skip(submissionId, `Already reviewed (${subject.status}) before analysis ran`);
      return;
    }

    const startedAt = Date.now();
    try {
      const contract = await this.repository.contractFor(submissionId);
      if (!contract) {
        await this.repository.skip(submissionId, 'No verification contract could be resolved for this quest');
        return;
      }

      const provenance = await this.provenance.inspect(submissionId);
      if (!provenance) {
        await this.repository.skip(submissionId, 'Submission disappeared before provenance could be measured');
        return;
      }

      const signals = await this.collectSignals(submissionId);
      const approveMin = this.config.get('AI_VERIFICATION_APPROVE_MIN_CONFIDENCE', { infer: true });
      const rejectMin = this.config.get('AI_VERIFICATION_REJECT_MIN_CONFIDENCE', { infer: true });

      // Content analysis runs only where content can decide. For the rest,
      // spending a vision call to produce advice the policy must ignore is
      // waste — and inviting an opinion on an unanswerable question is how a
      // confident wrong verdict gets made.
      let analysis: ProofAnalysis | undefined;
      if (contract.verifiability === 'content' && provenance.images.length > 0) {
        analysis = await this.runCascade(
          {
            questTitle: subject.quest_title,
            questDescription: subject.quest_description,
            questCategory: subject.quest_category,
            evidenceRubric: contract.evidenceRubric,
            verifiability: contract.verifiability,
            forensicNotes: provenance.notes,
            caption: subject.caption,
            images: provenance.images,
            unreadableMedia: provenance.unreadableMedia,
            signals,
          },
          approveMin,
        );
      }

      const outcome = decide({
        verifiability: contract.verifiability,
        mayAutoApprove: contract.mayAutoApprove,
        mayAutoReject: contract.mayAutoReject,
        forensics: provenance.report,
        analysis,
        approveMinConfidence: approveMin,
        rejectMinConfidence: rejectMin,
      });

      await this.record(submissionId, outcome, analysis, signals, Date.now() - startedAt);
      await this.act(submissionId, outcome);
    } catch (error) {
      // A failure is never written as a verdict. It stays retryable, and the
      // submission remains in the moderator's ordinary queue meanwhile — the
      // feature going down must not stop anyone from being reviewed.
      const message = error instanceof Error ? error.message : 'Unknown analysis error';
      await this.repository.fail(submissionId, message);
      this.logger.error({ submissionId, err: message }, 'Proof analysis failed');
    }
  }

  /// Walks the rungs until one settles it or the ladder runs out.
  private async runCascade(
    request: Parameters<ProofAnalyzer['analyze']>[0],
    approveMinConfidence: number,
  ): Promise<ProofAnalysis> {
    let tier: ProofTier | null = nextTier(null, approveMinConfidence);
    let analysis: ProofAnalysis | undefined;

    while (tier !== null) {
      const current: ProofTier = tier;
      // The confidence floor is applied per rung, so a low-confidence answer
      // is treated as 'unclear' when deciding where to go next as well as
      // when deciding what to do.
      analysis = applyConfidenceFloor(
        await this.analyzer.analyze(request, current),
        current === 'reject_review'
          ? this.config.get('AI_VERIFICATION_REJECT_MIN_CONFIDENCE', { infer: true })
          : approveMinConfidence,
      );
      this.logger.debug(
        { tier: current, verdict: analysis.verdict, confidence: analysis.confidence, model: analysis.model },
        'Cascade rung completed',
      );
      tier = nextTier(current, approveMinConfidence, analysis);
    }

    // The loop always runs at least once, so this is defined.
    return analysis!;
  }

  /// Stores the outcome. In shadow mode this is all that happens.
  private async record(
    submissionId: string,
    outcome: PolicyOutcome,
    analysis: ProofAnalysis | undefined,
    signals: LocationSignals,
    durationMs: number,
  ): Promise<void> {
    // Exactly the predicate act() uses, so `acted` can never claim an action
    // that did not happen. `acted = false` is what marks a row as honest eval
    // data — the agent did not influence the human decision it is scored
    // against — and a stale true here would quietly poison the eval set that
    // every authority decision downstream is based on.
    const willAct = this.willActOnDecisions();
    await this.repository.complete(
      submissionId,
      {
        // The stored verdict is the *policy's* conclusion, not the model's
        // raw opinion, because that is what was (or would have been) acted
        // on — and therefore what the eval must be scored against.
        tier: analysis?.tier ?? 'triage',
        verdict: outcome.decision === 'approve' ? 'pass' : outcome.decision === 'reject' ? 'fail' : 'unclear',
        confidence: analysis?.confidence ?? null,
        // Unlike the verdict, these two are the model's own output rather than
        // the policy's conclusion, and they are stored raw. The policy has no
        // opinion to substitute: relevance and the observation list are
        // measurements of the media, and the CAMARA agent reads them back as
        // its CV evidence — a policy-adjusted number would be a different
        // thing wearing the same name.
        relevance: analysis?.relevance ?? null,
        observations: analysis?.observations ?? [],
        rationale: analysis?.rationale ?? '',
        escalationReason: outcome.decision === 'escalate' ? outcome.reason : '',
        model: analysis?.model ?? '',
        inputTokens: analysis?.inputTokens ?? null,
        outputTokens: analysis?.outputTokens ?? null,
      },
      signals,
      durationMs,
      { stage: outcome.stage, acted: willAct && outcome.decision !== 'escalate', provider: this.analyzer.provider },
    );
  }

  /// Carries out the decision, unless something more informed will.
  ///
  /// Approval and rejection go through the *same* repository methods a
  /// moderator's click uses, with a null actor. That is deliberate: there is
  /// one approval path, so the XP-awarded-once invariant, the notification,
  /// the audit row and the collab fan-out cannot drift between a human
  /// decision and an automated one. `admin_audit_log.actor_id` is nullable
  /// and `approve`/`reject` already accepted `string | null`, so the schema
  /// anticipated a non-human decider.
  ///
  /// Two independent verifiers fire off `submission.created`, and exactly one
  /// of them may act. This one steps aside for the other when it is running,
  /// because the ranking is not arbitrary: the agent pipeline weighs the
  /// CAMARA location evidence *and* this pass's own findings, read back as CV
  /// evidence. It is strictly better informed about the same submission. Two
  /// deciders would mean either a race to `approve`/`reject` on one row or,
  /// worse, an approval from one and a rejection from the other, with the
  /// user's notification decided by whichever worker happened to be quicker.
  ///
  /// Recording is unaffected: this pass keeps writing its verdict, relevance
  /// and observations either way. That row is the eval slice and it is also
  /// what the agent reads — stopping the write to avoid acting twice would
  /// blind the decider to save it from a conflict.
  private async act(submissionId: string, outcome: PolicyOutcome): Promise<void> {
    if (!this.willActOnDecisions()) {
      this.logger.log(
        { submissionId, decision: outcome.decision, stage: outcome.stage },
        this.config.get('AGENT_SUBMISSION_VERIFICATION_ENABLED', { infer: true })
          ? 'Agent pipeline is the decider for this deployment: proof verdict recorded as evidence, not acted on'
          : 'Shadow mode: decision recorded, not acted on',
      );
      return;
    }
    if (outcome.decision === 'escalate') return;

    const source = { actor: 'ai_proof_verification', stage: outcome.stage, provider: this.analyzer.provider };
    if (outcome.decision === 'approve') {
      await this.submissions.approve(null, submissionId, outcome.reason, source);
    } else {
      await this.submissions.reject(null, submissionId, outcome.reason, source);
    }
    this.logger.log({ submissionId, decision: outcome.decision, stage: outcome.stage }, 'Agent decided a submission');
  }

  /// Whether this pass is the one allowed to carry its decisions out.
  ///
  /// Two things can take that away, and they are different in kind. Shadow
  /// mode says nobody has measured this agent yet. The agent pipeline being
  /// enabled says something better informed will decide instead. Either way
  /// the verdict is still recorded — and in the second case it is recorded
  /// *for* that decider, as the CV evidence it reads.
  private willActOnDecisions(): boolean {
    if (this.config.get('AGENT_SUBMISSION_VERIFICATION_ENABLED', { infer: true })) return false;
    return !this.config.get('AI_VERIFICATION_SHADOW_MODE', { infer: true });
  }

  /// Scores the agent against decisions people already made (#47).
  ///
  /// The authority model says the agent earns the right to act from a
  /// measured precision number. `npm run proof:eval` computes it from stored
  /// verdicts paired with the human decision that followed — and `verify()`
  /// refuses to analyse anything already reviewed, so that pairing can only
  /// ever accumulate going forward. A database full of moderated history is
  /// invisible to it, and a new deployment has to run in shadow mode for
  /// weeks before it can answer "is this good enough yet".
  ///
  /// This reads that history instead. Same forensics, same cascade, same
  /// policy — the verdict it records is the one the agent *would* have
  /// reached, on submissions whose outcome was settled by a person before
  /// this verdict existed.
  ///
  /// Three things it deliberately does not do, each of which would make it
  /// unsafe to point at a production database:
  ///
  ///   * **never acts.** No `act()` call, at any setting. Shadow mode is not
  ///     consulted because acting is not reachable from here.
  ///   * **never claims.** No attempt increment, no state transition, so it
  ///     cannot consume the retries a live submission needs, and it is
  ///     re-runnable.
  ///   * **never alerts.** `completeForEval` writes the verdict without the
  ///     committee notification `complete()` sends on an escalation —
  ///     otherwise scoring a year of history would notify every admin about
  ///     every old submission the agent found ambiguous.
  ///
  /// It costs real vision calls, which is why the caller passes a limit.
  async backfillForEval(limit: number): Promise<{
    scored: number;
    skipped: number;
    failed: number;
  }> {
    if (!this.analyzer.enabled) {
      this.logger.warn('Backfill requested while the analyzer is disabled; nothing to score with');
      return { scored: 0, skipped: 0, failed: 0 };
    }

    const ids = await this.repository.decidedWithoutVerdict(limit);
    let scored = 0;
    let skipped = 0;
    let failed = 0;

    for (const submissionId of ids) {
      const startedAt = Date.now();
      try {
        const subject = await this.repository.evalSubject(submissionId);
        const contract = await this.repository.contractFor(submissionId);
        const provenance = subject && contract ? await this.provenance.inspect(submissionId) : null;
        if (!subject || !contract || !provenance) {
          // A submission whose media has gone, or whose quest has no
          // resolvable contract. Counted rather than recorded: a row written
          // from nothing would be scored as if it meant something.
          skipped += 1;
          continue;
        }

        let analysis: ProofAnalysis | undefined;
        if (contract.verifiability === 'content' && provenance.images.length > 0) {
          analysis = await this.runCascade(
            {
              questTitle: subject.quest_title,
              questDescription: subject.quest_description,
              questCategory: subject.quest_category,
              evidenceRubric: contract.evidenceRubric,
              verifiability: contract.verifiability,
              forensicNotes: provenance.notes,
              caption: subject.caption,
              images: provenance.images,
              unreadableMedia: provenance.unreadableMedia,
              // Historical rows have no network evidence and never will;
              // saying so is what stops the pass inferring presence.
              signals: {},
            },
            this.config.get('AI_VERIFICATION_APPROVE_MIN_CONFIDENCE', { infer: true }),
          );
        }

        const outcome = decide({
          verifiability: contract.verifiability,
          mayAutoApprove: contract.mayAutoApprove,
          mayAutoReject: contract.mayAutoReject,
          forensics: provenance.report,
          analysis,
          approveMinConfidence: this.config.get('AI_VERIFICATION_APPROVE_MIN_CONFIDENCE', { infer: true }),
          rejectMinConfidence: this.config.get('AI_VERIFICATION_REJECT_MIN_CONFIDENCE', { infer: true }),
        });

        await this.repository.completeForEval(
          submissionId,
          analysis ?? {
            tier: 'triage',
            verdict: 'unclear',
            confidence: null,
            relevance: null,
            observations: [],
            rationale: '',
            escalationReason: outcome.reason,
            model: '',
            inputTokens: null,
            outputTokens: null,
          },
          outcome.stage,
          outcome.decision === 'approve' ? 'pass' : outcome.decision === 'reject' ? 'fail' : 'unclear',
          Date.now() - startedAt,
        );
        scored += 1;
      } catch (error) {
        // Never written as a verdict, and never `fail()`ed either: failing
        // the row would mark a live state machine on behalf of a backfill.
        failed += 1;
        this.logger.warn(
          { submissionId, err: error instanceof Error ? error.message : 'Unknown error' },
          'Backfill could not score this submission',
        );
      }
    }

    this.logger.log({ requested: ids.length, scored, skipped, failed }, 'Eval backfill finished');
    return { scored, skipped, failed };
  }

  /// The committee's "unclear" section (#47).
  unclearQueue(limit: number, offset: number) {
    return this.repository.unclearQueue(limit, offset);
  }

  /// Waiting escalations, for the admin sidebar badge.
  unclearCount() {
    return this.repository.unclearCount();
  }

  /// Retries whatever the queue never finished.
  ///
  /// Needed because the outbox consumer is the only trigger: a worker that
  /// dies between claiming and completing would otherwise leave that
  /// submission unanalysed permanently.
  async sweep(): Promise<{ analysed: number }> {
    if (!this.analyzer.enabled) return { analysed: 0 };
    const ids = await this.repository.pending(
      this.config.get('AI_VERIFICATION_SWEEP_BATCH_SIZE', { infer: true }),
      this.config.get('AI_VERIFICATION_MAX_ATTEMPTS', { infer: true }),
    );
    for (const id of ids) await this.verify(id);
    return { analysed: ids.length };
  }

  /// The three CAMARA signals for this submission, if any exist (#53).
  ///
  /// `undefined` per signal rather than `false` when there is no evidence —
  /// "no adapter configured" must never read as "the player was not there".
  /// Until #53 lands `map_location_evidence` has no writer, so in practice
  /// this returns an empty object.
  private async collectSignals(submissionId: string): Promise<LocationSignals> {
    const evidence = await this.repository.evidenceFor(submissionId);
    if (!evidence) return {};
    return {
      locationVerified: evidence.location_verified,
      locationRetrieved: evidence.location_retrieved,
      geofenceVerified: evidence.geofence_verified,
    };
  }
}
