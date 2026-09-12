import { Inject, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
import { CV_EVIDENCE_PROVIDER, NETWORK_EVIDENCE_PROVIDER } from '../domain/agent.tokens.js';
import { NETWORK_DEVICE_RESOLVER, type NetworkDeviceResolver } from '../domain/network-device.port.js';
import type { CvEvidenceProvider } from '../domain/cv-evidence.port.js';
import type { LocationEvidenceQuery, NetworkEvidenceProvider } from '../domain/network-evidence.port.js';
import { VerificationDecisionSchema, type AgentContext, type CvEvidence, type NetworkEvidence, type VerificationDecision } from '../domain/agent.schemas.js';
import { explainDuration, explainXp, finalizeDecision, mandatoryEvidenceStatus, type DurationBreakdown, type XpBreakdown } from '../domain/verification-policy.js';
import { AgentContextService } from './agent-context.service.js';
import { XpRecommendationService } from './xp-recommendation.service.js';
import { AgentContextRepository } from '../infrastructure/agent-context.repository.js';
import { AgentRunsRepository } from '../infrastructure/agent-runs.repository.js';
import { AgentRuntimeConfigRepository } from '../infrastructure/agent-runtime-config.repository.js';
import { GeofencingRepository } from '../infrastructure/geofencing.repository.js';
import { ObjectStorageService } from '../../media/infrastructure/object-storage.service.js';
import { OpenAiAgentRunner } from '../infrastructure/openai/openai-agent.runner.js';
import { buildSubmissionVerificationAgent } from '../infrastructure/openai/submission-verification.agent.js';
import { buildAdditionalNetworkEvidenceTool } from '../infrastructure/openai/tools/additional-network-evidence.tool.js';
import { buildCvFrameTool } from '../infrastructure/openai/tools/cv-frame.tool.js';

export interface SubmissionVerificationOutcome {
  readonly runId: string;
  readonly decision: VerificationDecision;
  readonly skipped?: 'DISABLED' | 'ALREADY_RUN';
  /**
   * On a demo run only: what an approval would have awarded, itemised.
   *
   * Deliberately not stored against the submission — see `verify` — so the
   * processor persists it on the run, where it is visible and inert.
   */
  readonly expectedXp?: XpBreakdown | null;
  /** On a demo run: how the completion window would have been sized. */
  readonly expectedDuration?: DurationBreakdown | null;
}

/**
 * Orchestrates one submission's verification: gather mandatory CAMARA +
 * CV evidence, optionally run the OpenAI agent, and apply deterministic
 * policy over whatever it recommends. This never writes to submissions or
 * user_quests, never awards XP, and never holds CAMARA/OpenAI credentials
 * itself (those live behind the injected ports/runner). Existing services
 * (SubmissionsService today; this module's own recommendation services
 * later) remain the only things authorised to act on the result.
 */
/**
 * How one verification run differs from the default.
 *
 * Both fields exist for the hackathon demo and both default to off, so an
 * ordinary submission takes exactly the path it always did.
 */
export interface VerifyOptions {
  /**
   * A Nokia simulator persona for THIS run only.
   *
   * It reaches the resolver and nothing else: the CAMARA adapter is never
   * told, `users.phone_number` is never written, and the resolver refuses it
   * unless the deployment is entitled — so a payload carrying one on a live
   * box changes nothing.
   */
  readonly personaId?: string | null;
  /**
   * Evaluate without applying.
   *
   * The run is real — real Nokia call, the stored CV analysis, the same
   * agent, the same deterministic policy — and is recorded so an operator
   * can audit it. What it does not do is act: the caller must not hand the
   * outcome to approve/reject, and this method skips the one write that
   * would outlive it (`submissions.recommended_xp`).
   */
  readonly demo?: boolean;
}

@Injectable()
export class SubmissionVerificationService {
  private readonly logger = new Logger(SubmissionVerificationService.name);

  constructor(
    private readonly config: ConfigService<Environment, true>,
    private readonly contextService: AgentContextService,
    private readonly contextRepository: AgentContextRepository,
    private readonly agentRuns: AgentRunsRepository,
    private readonly runtimeConfig: AgentRuntimeConfigRepository,
    private readonly geofencing: GeofencingRepository,
    private readonly xpRecommendation: XpRecommendationService,
    private readonly runner: OpenAiAgentRunner,
    private readonly storage: ObjectStorageService,
    @Inject(CV_EVIDENCE_PROVIDER) private readonly cvProvider: CvEvidenceProvider,
    @Inject(NETWORK_EVIDENCE_PROVIDER) private readonly networkProvider: NetworkEvidenceProvider,
    @Inject(NETWORK_DEVICE_RESOLVER) private readonly deviceResolver: NetworkDeviceResolver,
  ) {}

  /// Re-verifies submissions whose geofence evidence arrived after the agent
  /// had already given up on it (#15).
  ///
  /// "fallback to human OR pend them till camara gives results back" — the
  /// first half has always worked, since every provider failure folds to
  /// UNAVAILABLE and finalizeDecision turns that into HUMAN_REVIEW rather
  /// than a rejection. This is the second half, for the one capability where
  /// "gives results back" is a coherent idea: see
  /// `submissionsWithLateGeofenceEvidence` for why location verification and
  /// retrieval are deliberately not retried.
  async findRecoveredEvidence(limit: number): Promise<readonly {
    submissionId: string;
    evidenceGeneration: string;
  }[]> {
    if (!this.config.get('AGENT_SUBMISSION_VERIFICATION_ENABLED', { infer: true })) return [];
    const pending = await this.agentRuns.submissionsWithLateGeofenceEvidence(limit);
    // The event id is the evidence generation: one re-verification per batch
    // of new events, and a redelivered event produces the same key and so
    // re-runs nothing.
    return pending.map(({ submissionId, latestEventId }) => ({
      submissionId,
      evidenceGeneration: latestEventId,
    }));
  }

  /// `evidenceGeneration` re-opens the idempotency key for one more run.
  ///
  /// Without it a submission gets exactly one verification ever, which is
  /// right while the evidence is fixed and wrong once new evidence lands. It
  /// is a discriminator, not a bypass: the same generation still collapses
  /// to one run, so a redelivered webhook cannot spend a second set of
  /// CAMARA and model calls.
  async verify(
    submissionId: string,
    evidenceGeneration?: string,
    options: VerifyOptions = {},
  ): Promise<SubmissionVerificationOutcome | null> {
    if (!this.config.get('AGENT_SUBMISSION_VERIFICATION_ENABLED', { infer: true })) {
      return { runId: '', decision: this.humanReviewFallback('Automated submission verification is disabled for this deployment.'), skipped: 'DISABLED' };
    }
    if (!(await this.runtimeConfig.isSubmissionVerificationEnabled())) {
      return { runId: '', decision: this.humanReviewFallback('Automated submission verification is paused from the admin dashboard.'), skipped: 'DISABLED' };
    }

    const context = await this.contextService.forSubmissionVerification(submissionId);
    if (!context || !context.submission || !context.assignment) {
      this.logger.warn({ submissionId }, 'No agent context available for submission; nothing to verify');
      return null;
    }

    // Resolved before the run is claimed, for two reasons: the run row has
    // to record which device it asked about, and an unusable persona should
    // fail before a claim, a Nokia call or a model call is spent on it.
    const device = await this.deviceResolver.resolve({
      userId: context.user.id,
      personaId: options.personaId,
    });

    const promptVersion = this.config.get('OPENAI_AGENT_PROMPT_VERSION', { infer: true });
    const idempotencyKey = evidenceGeneration
      ? `submission:${submissionId}:verification:${promptVersion}:ev:${evidenceGeneration}`
      : `submission:${submissionId}:verification:${promptVersion}`;

    // `start()` is the claim, and it is the ONLY check. There used to be a
    // `findByIdempotencyKey` read here that short-circuited on anything not
    // 'failed' — two predicates for one question, and they disagreed in the
    // case that matters: a run left 'running' by a killed worker made this
    // return ALREADY_RUN forever, so the submission could never be
    // evaluated and the log line said "already evaluated" about a run that
    // never finished. One atomic statement cannot disagree with itself.
    const run = await this.agentRuns.start(
      {
        kind: 'submission_verification',
        subjectType: 'submission',
        subjectId: submissionId,
        idempotencyKey,
        model: this.runner.isEnabled() ? (this.config.get('OPENAI_AGENT_MODEL', { infer: true }) ?? 'unset') : 'disabled',
        promptVersion,
        policyVersion: 'v1',
        inputSnapshot: context,
        isDemo: options.demo === true,
        demoPersona: options.demo ? (device.persona?.id ?? null) : null,
        deviceSource: device.source,
      },
      this.config.get('AGENT_RUN_LEASE_SECONDS', { infer: true }),
    );
    if (!run) {
      // The key is held: this submission already has a finished run, or
      // another worker holds a claim that has not expired. Either way there
      // is nothing for this job to do, and nothing for it to act on.
      return { runId: '', decision: this.humanReviewFallback('Already evaluated or in flight.'), skipped: 'ALREADY_RUN' };
    }

    let expectedXp: XpBreakdown | null = null;
    let expectedDuration: DurationBreakdown | null = null;
    try {
      // Fetched once and threaded through — the CAMARA-verified device
      // identifier (issue #1), not part of AgentContext itself so it never
      // reaches the model (AgentContextSchema.user deliberately carries
      // only an id).
      const phoneNumber = device.identifier;
      const geofence = await this.loadGeofence(context);
      const [networkEvidence, cvEvidence] = await Promise.all([
        this.gatherBaselineNetworkEvidence(context, phoneNumber, geofence),
        this.gatherCvEvidence(context, submissionId),
      ]);
      for (const evidence of networkEvidence) {
        // The source travels with the evidence, so a dossier can never be
        // read as a claim about a real subscriber when a simulator device
        // was asked. It is metadata for people, not for the model: the
        // agent is not shown it, and a test pins that it cannot move a
        // verdict.
        await this.agentRuns.recordNetworkEvidence(
          run.id,
          context.assignment.userQuestId,
          submissionId,
          evidence,
          {
            source: device.source,
            personaId: device.persona?.id,
            personaNumber: device.persona?.phoneNumber,
            isDemo: options.demo === true,
          },
        );
      }
      await this.agentRuns.recordCvEvidence(run.id, submissionId, cvEvidence);

      const isLocationBased = Boolean(context.quest.destination);
      const mandatoryStatus = isLocationBased ? mandatoryEvidenceStatus(networkEvidence) : 'SUPPORTED';

      const modelDecision = this.runner.isEnabled()
        ? await this.runModel(context, networkEvidence, cvEvidence, run.id, phoneNumber)
        : this.humanReviewFallback('The AI agent is disabled; this submission needs a human moderator.');

      const finalized = finalizeDecision({
        modelDecision,
        isLocationBased,
        mandatoryStatus,
        cvAvailable: cvEvidence.status === 'AVAILABLE',
        cvRelevance: cvEvidence.relevance ?? null,
        cvBlocksApproval: cvEvidence.integrity?.blocksAutomatedApproval ?? false,
        contract: context.quest.verification,
        minRelevance: this.config.get('AI_VERIFICATION_MIN_RELEVANCE', { infer: true }),
        bounds: context.policy,
      });
      // The one write in this method that outlives the run: it sets
      // `submissions.recommended_xp`, which a later REAL approval reads to
      // decide the award (`COALESCE(s.recommended_xp, q.xp_reward)`). A demo
      // evaluation must not move that number — the whole point is that it
      // changes nothing authoritative — so it is skipped rather than
      // recomputed and discarded.
      if (options.demo) {
        // Both curves, itemised: what this completion would be worth and how
        // long the player would have been given. They answer the same
        // question from two directions — how much this particular attempt
        // cost this particular person — and a judge should see the working.
        //
        // Computed, never stored against the submission: `recommended_xp` is
        // read by a later REAL approval, and a demo must not move it.
        const shape = await this.rewardShape(context);
        expectedXp = shape ? explainXp(shape, context.policy) : null;
        expectedDuration = shape ? explainDuration(shape, context.policy) : null;
      } else {
        await this.recommendXp(context, submissionId);
      }
      // Deliberately NOT marked succeeded here. The caller applies the
      // decision, and a run is only finished once that has happened.
      //
      // Marking it here left a window — one await wide — where a worker that
      // died took the decision with it: the run said 'succeeded', nothing had
      // been applied, and `start()` will not reclaim a succeeded run, so the
      // retry short-circuited and the submission waited on a human forever
      // with no record of why. Leaving it 'running' means the lease reclaims
      // it, which is exactly what the lease is for.
      return { runId: run.id, decision: finalized, expectedXp, expectedDuration };
    } catch (error) {
      this.logger.error({ submissionId, runId: run.id, errorName: error instanceof Error ? error.name : 'UnknownError' }, 'Submission verification run failed');
      await this.agentRuns.fail(run.id, 'AGENT_RUN_FAILED', error instanceof Error ? error.message : 'Unknown error');
      return { runId: run.id, decision: this.humanReviewFallback('The verification run failed; this submission needs a human moderator.') };
    }
  }

  private async gatherBaselineNetworkEvidence(
    context: AgentContext,
    phoneNumber: string | null,
    geofence: LocationEvidenceQuery['geofence'],
  ): Promise<readonly NetworkEvidence[]> {
    if (!context.quest.destination) return [];
    return this.networkProvider.getBaselineEvidence(this.locationQuery(context, phoneNumber, geofence));
  }

  /**
   * Geofence entry/exit events the provider pushed while this quest was
   * running, loaded from our own tables and bounded to the quest's window
   * — assignment through submission. Presence before the quest started or
   * after proof was submitted is not evidence for that proof.
   */
  private async loadGeofence(context: AgentContext): Promise<LocationEvidenceQuery['geofence']> {
    if (!context.quest.destination || !context.assignment) return null;
    const subscription = await this.geofencing.findByUserQuest(context.assignment.userQuestId);
    if (!subscription) return { status: 'missing', events: [], origin: 'NOKIA' };
    if (subscription.status !== 'active') {
      return { status: 'failed', events: [], origin: subscription.origin };
    }

    const windowStart = new Date(context.assignment.assignedAt);
    const windowEnd = new Date(context.assignment.submittedAt ?? new Date().toISOString());
    const events = await this.geofencing.eventsInWindow(
      context.assignment.userQuestId,
      windowStart,
      windowEnd,
    );
    return {
      status: 'active',
      origin: subscription.origin,
      events: events.map((event) => ({
        type: event.type,
        occurredAt: event.occurredAt.toISOString(),
        origin: event.origin,
      })),
    };
  }

  /**
   * Per-user XP for this completion, keyed off how far they actually had
   * to travel (measured at assignment time). Stored on the submission;
   * approval prefers it over the quest's flat xp_reward when present, and
   * the backend still awards it exactly once.
   */
  /**
   * The inputs both reward curves read: how far this player travelled, and
   * what the quest is.
   *
   * Built once and handed to `explainXp` and `explainDuration` — the same
   * functions `deterministicXp` and `deterministicQuestMinutes` are built on
   * — so a demo panel's arithmetic is the product's arithmetic rather than a
   * second copy free to drift.
   */
  private async rewardShape(context: AgentContext) {
    if (!context.assignment) return null;
    const distanceMeters = await this.contextRepository.findAssignmentDistance(
      context.assignment.userQuestId,
    );
    return {
      distanceMeters,
      hasDestination: Boolean(context.quest.destination),
      category: context.quest.category,
      difficulty: context.quest.difficulty,
      participantCount: context.collaboration.participantCount,
    };
  }

  private async recommendXp(context: AgentContext, submissionId: string): Promise<void> {
    if (!context.assignment) return;
    // Measured once at assignment time and stored on the row — by now the
    // assignment has moved to 'submitted', and re-measuring would answer a
    // different question (where they are now, not how far they came).
    const distanceMeters = await this.contextRepository.findAssignmentDistance(
      context.assignment.userQuestId,
    );

    const recommendation = await this.xpRecommendation.recommend({
      context,
      distanceMeters,
      bounds: context.policy,
    });
    await this.contextRepository.storeRecommendedXp(submissionId, recommendation.recommendedXp);
    this.logger.log(
      { submissionId, distanceMeters, recommendedXp: recommendation.recommendedXp },
      'Per-user XP recommendation stored for this submission',
    );
  }

  private async gatherCvEvidence(context: AgentContext, submissionId: string): Promise<CvEvidence> {
    const mediaRows = await this.contextService.mediaForSubmission(submissionId);
    const media = await Promise.all(
      mediaRows.map(async (row) => ({
        mediaObjectId: row.media_object_id,
        contentType: row.content_type,
        downloadUrl: await this.storage.presignDownload(row.object_key),
      })),
    );
    return this.cvProvider.analyze({
      runId: context.runId,
      submissionId,
      media,
      requirements: {
        actions: context.quest.requirements?.actions ?? [],
        objects: context.quest.requirements?.objects ?? [],
        landmarks: [],
        locationDescription: context.quest.destination ? context.quest.title : undefined,
      },
      // The requirements above are hand-authored and empty on nearly every
      // quest, so on their own they give a provider nothing to match the media
      // against — which is how "is this relevant to the quest?" degenerated
      // into "is a file attached?". The task block is always populated, and
      // carries the contract that says whether relevance is even a fair
      // question for this quest.
      task: {
        title: context.quest.title,
        description: context.quest.description,
        category: context.quest.category,
        evidenceRubric: context.quest.verification.evidenceRubric,
        verifiability: context.quest.verification.verifiability,
      },
      maxKeyFrames: 12,
      idempotencyKey: `${submissionId}:cv:${context.runId}`,
    });
  }

  private async runModel(
    context: AgentContext,
    networkEvidence: readonly NetworkEvidence[],
    cvEvidence: CvEvidence,
    runId: string,
    phoneNumber: string | null,
  ): Promise<VerificationDecision> {
    const model = this.config.get('OPENAI_AGENT_MODEL', { infer: true });
    if (!model) return this.humanReviewFallback('OPENAI_AGENT_MODEL is not configured.');

    const allowedAdditional = this.networkProvider.supportedAdditionalCapabilities;
    // Only offer a tool that can actually answer. The frame tool was
    // registered unconditionally while no CV provider implements `getFrame`
    // — and the local one deliberately returns no key frames to ask about —
    // so the model carried a tool in its schema on every call whose only
    // possible reply was "unavailable", and could spend a turn discovering
    // that. This mirrors how the additional-evidence tool below is already
    // gated on the provider offering something.
    const tools = [
      ...(this.cvProvider.getFrame ? [buildCvFrameTool(this.cvProvider)] : []),
      ...(context.quest.destination && allowedAdditional.length > 0
        ? [buildAdditionalNetworkEvidenceTool(this.networkProvider, this.locationQuery(context, phoneNumber), allowedAdditional)]
        : []),
    ];

    try {
      const agent = buildSubmissionVerificationAgent({
        model,
        tools,
        verifiability: context.quest.verification.verifiability,
        evidenceRubric: context.quest.verification.evidenceRubric,
      });
      const raw = await this.runner.run<unknown>(agent, JSON.stringify({ context, networkEvidence, cvEvidence }));
      const parsed = VerificationDecisionSchema.safeParse(raw);
      if (!parsed.success) {
        this.logger.warn({ runId, issues: parsed.error.issues }, 'Model output failed schema validation');
        return this.humanReviewFallback('The agent response did not match the expected structure.');
      }
      return parsed.data;
    } catch (error) {
      this.logger.warn({ runId, errorName: error instanceof Error ? error.name : 'UnknownError' }, 'Model call failed');
      return this.humanReviewFallback('The verification model call failed.');
    }
  }

  private locationQuery(
    context: AgentContext,
    phoneNumber: string | null,
    geofence: LocationEvidenceQuery['geofence'] = null,
  ): LocationEvidenceQuery {
    if (!context.quest.destination || !context.assignment || !context.submission) {
      throw new Error('locationQuery called without a destination/assignment/submission in context');
    }
    return {
      runId: context.runId,
      userId: context.user.id,
      phoneNumber,
      userQuestId: context.assignment.userQuestId,
      submissionId: context.submission.id,
      place: {
        placeId: context.quest.destination.placeId,
        latitude: context.quest.destination.coordinates.latitude,
        longitude: context.quest.destination.coordinates.longitude,
        radiusMeters: context.quest.destination.radiusMeters,
      },
      windowStart: context.assignment.assignedAt,
      windowEnd: context.assignment.submittedAt ?? new Date().toISOString(),
      geofence,
    };
  }

  private humanReviewFallback(reason: string): VerificationDecision {
    return {
      decision: 'HUMAN_REVIEW',
      confidence: 0,
      reasons: [reason],
      evidenceAssessment: {
        cv: 'MISSING',
        locationVerification: 'MISSING',
        locationRetrieval: 'MISSING',
        geofencing: 'MISSING',
        timing: 'MISSING',
      },
      additionalCapabilitiesUsed: [],
      conflicts: [],
      humanReviewReason: reason,
    };
  }
}
