import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
import { ObjectStorageService } from '../../media/infrastructure/object-storage.service.js';
import {
  applyConfidenceFloor,
  isSupportedImageType,
  type LocationSignals,
  type ProofImage,
} from '../domain/proof-verification.types.js';
import { ClaudeProofAnalyzer } from '../infrastructure/claude-proof-analyzer.js';
import { ProofVerificationRepository } from '../infrastructure/proof-verification.repository.js';

/// Runs AI proof verification for one submission (#47).
///
/// The verdict is advisory throughout: this service writes to
/// `submission_verifications` and notifies admins, and touches neither
/// `submissions.status` nor XP. A moderator still decides every submission.
///
/// It is signal-agnostic on purpose. The three CAMARA signals (#53) are read
/// from evidence if present and passed through as `undefined` when they are
/// not, so the adapter landing later changes what `collectSignals` returns
/// and nothing else.
@Injectable()
export class ProofVerificationService {
  private readonly logger = new Logger(ProofVerificationService.name);

  constructor(
    private readonly repository: ProofVerificationRepository,
    private readonly analyzer: ClaudeProofAnalyzer,
    private readonly storage: ObjectStorageService,
    private readonly config: ConfigService<Environment, true>,
  ) {}

  /// Analyses one submission. Safe to call more than once for the same id.
  async verify(submissionId: string): Promise<void> {
    if (!this.analyzer.enabled) {
      // Recorded rather than ignored, so turning the feature on later can
      // find everything it never looked at.
      await this.repository.enqueue(submissionId);
      return;
    }

    await this.repository.enqueue(submissionId);
    const subject = await this.repository.claim(
      submissionId,
      this.config.get('AI_VERIFICATION_MAX_ATTEMPTS', { infer: true }),
    );
    // Null means already analysed, out of attempts, or claimed by another
    // worker. All three are correct no-ops.
    if (!subject) return;

    if (subject.status !== 'pending') {
      await this.repository.skip(submissionId, `Already reviewed (${subject.status}) before analysis ran`);
      return;
    }

    const startedAt = Date.now();
    try {
      const { images, unreadable } = await this.loadMedia(subject.media_url);
      const signals = await this.collectSignals(subject.submission_id);

      // Nothing to look at — a video-only submission, or media too large to
      // read. Escalating is honest; a verdict here would be invented.
      if (images.length === 0) {
        await this.repository.complete(
          submissionId,
          {
            verdict: 'unclear',
            confidence: null,
            rationale: '',
            escalationReason: unreadable.length > 0
              ? `No analysable image in this submission (${unreadable.join(', ')}). A human decision is required.`
              : 'No analysable image in this submission. A human decision is required.',
            model: '',
            inputTokens: null,
            outputTokens: null,
          },
          signals,
          Date.now() - startedAt,
        );
        return;
      }

      const analysis = applyConfidenceFloor(
        await this.analyzer.analyze({
          questTitle: subject.quest_title,
          questDescription: subject.quest_description,
          questCategory: subject.quest_category,
          caption: subject.caption,
          images,
          unreadableMedia: unreadable,
          signals,
        }),
        this.config.get('AI_VERIFICATION_MIN_CONFIDENCE', { infer: true }),
      );

      await this.repository.complete(submissionId, analysis, signals, Date.now() - startedAt);
      this.logger.log(
        { submissionId, verdict: analysis.verdict, confidence: analysis.confidence },
        'Proof analysed',
      );
    } catch (error) {
      // A failure is never written as a verdict. It is left retryable, and
      // the submission stays in the moderator's ordinary queue meanwhile —
      // the feature going down must not stop anyone being reviewed.
      const message = error instanceof Error ? error.message : 'Unknown analysis error';
      await this.repository.fail(submissionId, message);
      this.logger.error({ submissionId, err: message }, 'Proof analysis failed');
    }
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

  /// Reads the submission's images, reporting what it could not read.
  ///
  /// `media_url` holds one to ten private object keys, already validated on
  /// the way in. Video and oversized objects are named rather than dropped,
  /// so the verdict can say which part of the proof went unexamined.
  private async loadMedia(
    mediaUrl: string,
  ): Promise<{ images: ProofImage[]; unreadable: string[] }> {
    const keys = this.parseMediaKeys(mediaUrl);
    const maxImages = this.config.get('AI_VERIFICATION_MAX_IMAGES', { infer: true });
    const maxBytes = this.config.get('AI_VERIFICATION_MAX_IMAGE_BYTES', { infer: true });
    const images: ProofImage[] = [];
    const unreadable: string[] = [];

    for (const key of keys) {
      if (images.length >= maxImages) {
        unreadable.push(`${keys.length - maxImages} further file(s) beyond the per-submission image cap`);
        break;
      }
      const object = await this.storage.read(key, maxBytes);
      if (!object) {
        unreadable.push('a file too large to analyse');
        continue;
      }
      if (!isSupportedImageType(object.contentType)) {
        // Today this is video, which the Messages API does not accept as
        // input. Frame extraction is follow-up work; until then the honest
        // outcome is an escalation, which is #47's own fallback path.
        unreadable.push(object.contentType || 'a file of unknown type');
        continue;
      }
      images.push({
        mediaType: object.contentType.split(';')[0].trim().toLowerCase() as ProofImage['mediaType'],
        base64: object.body.toString('base64'),
      });
    }
    return { images, unreadable };
  }

  /// The three CAMARA signals for this submission, if any exist.
  ///
  /// Returns `undefined` per signal rather than `false` when there is no
  /// evidence — the distinction migration 0022 and #53 both insist on, since
  /// "no adapter configured" must not read as "the user was not there".
  /// Until #53 lands `map_location_evidence` has no writer, so this returns
  /// an empty object in practice.
  private async collectSignals(submissionId: string): Promise<LocationSignals> {
    const evidence = await this.repository.evidenceFor(submissionId);
    if (!evidence) return {};
    return {
      locationVerified: evidence.location_verified,
      locationRetrieved: evidence.location_retrieved,
      geofenceVerified: evidence.geofence_verified,
    };
  }

  private parseMediaKeys(raw: string): string[] {
    try {
      const parsed: unknown = raw.trim().startsWith('[') ? JSON.parse(raw) : [raw];
      if (!Array.isArray(parsed)) return [];
      return parsed.filter((value): value is string => typeof value === 'string' && value.trim().length > 0);
    } catch {
      return [];
    }
  }
}
