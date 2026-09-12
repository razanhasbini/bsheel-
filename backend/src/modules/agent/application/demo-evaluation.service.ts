import { ForbiddenException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectQueue } from '@nestjs/bullmq';
import type { Queue } from 'bullmq';
import type { Environment } from '../../../config/environment.js';
import { CAMARA_PERSONAS, DEMO_PERSONA_IDS, personaById } from '../../../integrations/camara/camara-personas.js';
import { AgentEvidenceRepository, type VerificationDossier } from '../infrastructure/agent-evidence.repository.js';
import type { DurationBreakdown, XpBreakdown } from '../domain/verification-policy.js';
import { GeofenceHarnessService, type GeofenceDelivery } from './geofence-harness.service.js';

/**
 * What a demo evaluation hands back: the run that happened, plus what the
 * product *would* have done with it.
 */
export interface DemoEvaluation {
  /** The persisted run — the same rows the Admin Agent Evidence page reads. */
  readonly dossier: VerificationDossier;
  /**
   * Why the simulator's own signals disagree, when they do.
   *
   * Not an excuse and not a correction — an explanation the reader needs to
   * judge what they are seeing. Computed here so the mobile panel and the
   * admin console say the same thing.
   */
  readonly simulatorNote: string | null;
  /**
   * What would follow if this decision were the authoritative one. Computed
   * from the same arithmetic the real award uses, and applied to nothing.
   */
  readonly expectedEffect: {
    readonly applied: false;
    readonly xp: XpBreakdown | null;
    /** How the completion window would have been sized. */
    readonly duration: DurationBreakdown | null;
    readonly questCompleted: boolean;
    readonly explorationPlace: string | null;
    readonly summary: readonly string[];
  };
}

/** What queuing a demo evaluation hands straight back to the caller. */
export interface DemoEvaluationReceipt {
  /** Identifies this run; the app polls until a dossier carries a decision. */
  readonly evidenceGeneration: string;
  readonly persona: { readonly id: string; readonly phoneNumber: string; readonly label: string };
  /** Present when the scenario asked for a geofence event to be delivered first. */
  readonly geofence: GeofenceDelivery | null;
}

/**
 * The hackathon demo: evaluate one submission under a chosen Nokia simulator
 * device, and change nothing.
 *
 * Every part of the run is the real one. The persona reaches
 * `NetworkDeviceResolver` and nothing else, so CAMARA is genuinely called
 * about a genuine Nokia test device; the CV analysis is the one already
 * stored for this submission (no second vision pass); the agent and the
 * deterministic finalizer are the ones that decide real submissions.
 *
 * What makes it non-authoritative is what this service does NOT do: it never
 * hands the outcome to `approve`/`reject`. That is the whole mechanism, and
 * it is a consequence of where the architecture already put things — the
 * decision is applied by the verification *processor*, not by the service
 * that computes it. So there is no parallel engine here to drift from the
 * real one, and no reset to write, because nothing was moved.
 *
 * The run itself IS persisted, marked `is_demo`, so an operator can audit it
 * in the same history as everything else. Analytics cannot see it: a
 * completion is counted from `submissions` and `user_quests`, which this
 * never writes to.
 */
@Injectable()
export class DemoEvaluationService {
  private readonly logger = new Logger(DemoEvaluationService.name);

  constructor(
    private readonly config: ConfigService<Environment, true>,
    private readonly evidence: AgentEvidenceRepository,
    // The same queue the outbox feeds. The agent, the OpenAI client and the
    // CAMARA adapters all live in the WORKER process — this one only queues
    // the work and reads what the worker left behind, which is why the
    // mobile modal polls rather than waiting on a request.
    @InjectQueue('submission-verification') private readonly queue: Queue,
    private readonly harness: GeofenceHarnessService,
  ) {}

  /** The personas a demo may choose, with their measured behaviour and citation. */
  personas() {
    return CAMARA_PERSONAS.filter((persona) => DEMO_PERSONA_IDS.includes(persona.id)).map((persona) => ({
      id: persona.id,
      phoneNumber: persona.phoneNumber,
      label: persona.label,
      behaviour: persona.behaviour,
      expectedLocationOutcome: persona.expectedLocationOutcome,
      source: persona.source,
    }));
  }

  /** Whether this deployment offers the demo at all, and to whom. */
  isEnabled(): boolean {
    return this.config.get('CAMARA_DEMO_PERSONAS_ENABLED', { infer: true });
  }

  /**
   * Who may run a demo evaluation on this deployment.
   *
   * The deployment switch is the real gate: production refuses it at boot, so
   * this can only ever be true on a demo build. `CAMARA_DEMO_USER_IDS` is an
   * OPTIONAL narrowing on top — set it to pin the demo to specific accounts,
   * leave it empty and every signed-in user of the demo build may use it on
   * their own submissions.
   *
   * Empty-means-everyone is the right default here because the thing being
   * authorised is an evaluation that changes nothing. Ownership is enforced
   * separately and always: whoever is asking, they only ever get their own
   * proof.
   */
  isAllowed(userId: string): boolean {
    if (!this.isEnabled()) return false;
    const raw = this.config.get('CAMARA_DEMO_USER_IDS', { infer: true }) ?? '';
    const allowed = raw.split(',').map((id) => id.trim()).filter(Boolean);
    return allowed.length === 0 || allowed.includes(userId);
  }

  /**
   * Whether to offer the demo for one specific submission.
   *
   * Location is the whole point of it: the four Nokia personas differ only in
   * what the network says about where the device was, so on a quest with no
   * destination they would all produce the same answer and the panel would be
   * theatre. Those quests already verify correctly from the media alone, and
   * the app is told not to offer anything.
   */
  async offerFor(input: { submissionId: string; actorUserId: string }): Promise<{
    eligible: boolean;
    locationBased: boolean;
    personas: ReturnType<DemoEvaluationService['personas']>;
    notice: string;
  }> {
    const eligible =
      this.isAllowed(input.actorUserId) &&
      (await this.evidence.isOwnedBy(input.submissionId, input.actorUserId));
    const locationBased =
      eligible && (await this.evidence.assignmentForGeofence(input.submissionId)) !== null;
    return {
      eligible,
      locationBased,
      personas: eligible && locationBased ? this.personas() : [],
      notice: 'TEMPORARY — FOR HACKATHON REQUIREMENTS. Evaluations are not applied.',
    };
  }

  async evaluate(input: {
    readonly submissionId: string;
    readonly personaId: string;
    readonly actorUserId: string;
    /**
     * Optionally deliver a geofence CloudEvent before evaluating.
     *
     * Separate from the persona on purpose. A persona decides what Nokia
     * says about the device's position; a geofence event decides whether the
     * network ever reported crossing the boundary. They are different
     * signals, and collapsing them would mean the scenario, not the policy,
     * deciding the outcome — the exact thing this demo must not do.
     */
    readonly geofenceEvent?: 'AREA_ENTERED' | 'AREA_LEFT' | null;
  }): Promise<DemoEvaluationReceipt> {
    if (!this.isAllowed(input.actorUserId)) {
      // 403 and not 404: the caller is authenticated and the submission is
      // theirs — what they lack is demo authority, and saying so is not a
      // disclosure.
      throw new ForbiddenException({
        code: 'DEMO_NOT_PERMITTED',
        message: 'This account is not enabled for CAMARA demo evaluations',
      });
    }
    // Whose proof, not just who is asking. The allowlist authorises the
    // account; it does not hand that account everybody else's submissions.
    if (!(await this.evidence.isOwnedBy(input.submissionId, input.actorUserId))) {
      throw new NotFoundException({ code: 'SUBMISSION_NOT_FOUND', message: 'Submission not found' });
    }
    const persona = personaById(input.personaId);
    if (!persona || !DEMO_PERSONA_IDS.includes(persona.id)) {
      throw new ForbiddenException({
        code: 'UNKNOWN_CAMARA_PERSONA',
        message: 'That is not a selectable Nokia simulator persona',
      });
    }

    // Delivered BEFORE the evaluation is queued, so the evidence is already
    // in place when the agent reads it. It goes over real HTTP to the real
    // webhook — see GeofenceHarnessService for why that matters.
    let geofence: GeofenceDelivery | null = null;
    const assignment = await this.evidence.assignmentForGeofence(input.submissionId);
    if (assignment) {
      // Every scenario starts from the same place. Geofence events persist,
      // so without this the entry delivered for the supportive case is still
      // there when a judge picks the contradicting one — and the agent is
      // asked to reconcile "the network says never here" with "an entry was
      // recorded". It escalates, correctly, and the demo looks broken.
      //
      // Only our own fabrications are cleared; a Nokia-delivered event is a
      // fact about the network and survives.
      await this.harness.clearPreviousEvents(assignment.id);
      if (input.geofenceEvent) {
        geofence = await this.harness.deliver({
          userQuest: assignment,
          type: input.geofenceEvent,
        });
      }
    }

    // A distinct generation per persona per second: each selection is its
    // own run rather than colliding with the last one's idempotency key,
    // which is what lets a judge press all four and get four recorded
    // evaluations to compare.
    const evidenceGeneration = `demo-${persona.id}-${Math.floor(Date.now() / 1000)}`;
    await this.queue.add(
      'submission.verify',
      { submissionId: input.submissionId, evidenceGeneration, personaId: persona.id, demo: true },
      {
        // BullMQ rejects ':' in a custom id.
        jobId: `submission-${input.submissionId}-verification-ev-${evidenceGeneration}`,
        attempts: 2,
        backoff: { type: 'exponential', delay: 5_000 },
        removeOnComplete: { age: 86_400, count: 10_000 },
        removeOnFail: { age: 604_800, count: 50_000 },
      },
    );
    this.logger.log(
      { submissionId: input.submissionId, persona: persona.id, actor: input.actorUserId },
      'Queued a demo evaluation; its decision will be recorded and not applied',
    );
    return {
      evidenceGeneration,
      persona: { id: persona.id, phoneNumber: persona.phoneNumber, label: persona.label },
      geofence,
    };
  }

  /**
   * What the worker recorded for a demo run, once it has finished.
   *
   * The app polls this while it shows its progress states. It reads the same
   * rows the Admin Agent Evidence page reads — there is one dossier, not a
   * judge-friendly copy of one, so the two surfaces cannot disagree about
   * what happened.
   */
  async result(input: { submissionId: string; actorUserId: string }): Promise<DemoEvaluation | null> {
    if (!this.isAllowed(input.actorUserId)) {
      throw new ForbiddenException({
        code: 'DEMO_NOT_PERMITTED',
        message: 'This account is not enabled for CAMARA demo evaluations',
      });
    }
    if (!(await this.evidence.isOwnedBy(input.submissionId, input.actorUserId))) {
      throw new NotFoundException({ code: 'SUBMISSION_NOT_FOUND', message: 'Submission not found' });
    }
    const dossier = await this.evidence.forSubmission(input.submissionId);
    if (!dossier) return null;
    // Still running, or the latest run is not the demo we queued.
    if (!dossier.isDemo || !dossier.decision) return null;
    return {
      dossier,
      simulatorNote: this.simulatorNote(dossier),
      expectedEffect: this.expectedEffect(dossier),
    };
  }

  /**
   * Explains a contradiction that belongs to Nokia's simulator, not to us.
   *
   * The two location APIs answer different questions from different sources
   * in the sandbox: Location Verification is hardcoded PER PHONE NUMBER and
   * ignores the area it is asked about, while Location Retrieval returns one
   * FIXED position — Budapest — for every simulator device. On any quest
   * whose destination is not that position the two cannot agree, however the
   * persona is chosen.
   *
   * The agent is right to flag it, and a judge should be told why rather than
   * left to assume the system is confused. The calibrated range exists so the
   * supportive case has somewhere the three signals can all be true at once.
   */
  private simulatorNote(dossier: VerificationDossier): string | null {
    if (dossier.deviceSource !== 'NOKIA_SIMULATOR') return null;
    const verification = dossier.network.find((n) => n.capability === 'LOCATION_VERIFICATION');
    const retrieval = dossier.network.find((n) => n.capability === 'LOCATION_RETRIEVAL');
    if (!verification || !retrieval) return null;
    if (verification.outcome === retrieval.outcome) return null;
    return 'Nokia\'s simulator answers Location Verification per phone number and '
      + 'ignores the area it is asked about, while Location Retrieval returns one fixed '
      + 'position for every simulator device. On a quest whose destination is not that '
      + 'position the two signals cannot agree — the agent is correctly reporting the '
      + 'inconsistency rather than picking a side. The calibrated demo range is the quest '
      + 'where all three network signals can support the same destination.';
  }

  /**
   * What an approval would be worth, itemised — and nothing else.
   *
   * The XP comes from `explainXp`, the same arithmetic `deterministicXp`
   * uses for a real award, so the figure on a judge's screen is the figure
   * the product would pay. Deliberately NOT stored: `submissions.
   * recommended_xp` is read by a later real approval, and a demo must not
   * move it.
   */
  /**
   * What an approval would be worth — and nothing else.
   *
   * Read from what the run persisted rather than recomputed here: the XP
   * breakdown is written by the worker using `explainXp`, the same
   * arithmetic `deterministicXp` uses for a real award, so the figure on a
   * judge's screen is the figure the product would actually pay. Nothing is
   * stored against the submission: `submissions.recommended_xp` is read by
   * a later REAL approval, and a demo must not move it.
   */
  private expectedEffect(dossier: VerificationDossier): DemoEvaluation['expectedEffect'] {
    if (dossier.decision !== 'APPROVED') {
      return {
        applied: false,
        xp: null,
        duration: dossier.expectedDuration,
        questCompleted: false,
        explorationPlace: null,
        summary:
          dossier.decision === 'REJECTED'
            ? ['The submission would be rejected, and the player could appeal once.']
            : ['The submission would wait for a moderator. Nothing would be awarded yet.'],
      };
    }
    const xp = dossier.expectedXp;
    return {
      applied: false,
      xp,
      duration: dossier.expectedDuration,
      questCompleted: true,
      explorationPlace: dossier.placeName,
      summary: [
        ...(xp ? [`${xp.total} XP would be awarded.`] : []),
        'The quest would be marked completed.',
        ...(dossier.placeName ? [`${dossier.placeName} would count towards exploration progress.`] : []),
      ],
    };
  }
}
