import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
import { buildForensicsReport, type ForensicsReport } from '../domain/proof-forensics.js';
import { isSupportedImageType, type ProofImage } from '../domain/proof-verification.types.js';
import { MediaForensicsService } from '../infrastructure/media-forensics.service.js';
import { ProofVerificationRepository } from '../infrastructure/proof-verification.repository.js';

export interface ProvenanceOutcome {
  readonly report: ForensicsReport;
  /// Images ready for a vision call, if one is needed. Loading them here
  /// avoids reading every object twice — forensics has to decode the bytes
  /// anyway, so the base64 comes free.
  readonly images: readonly ProofImage[];
  /// What could not be examined, named so a verdict never implies the whole
  /// submission was judged.
  readonly unreadableMedia: readonly string[];
  /// One line per finding, for the analyzer's context.
  readonly notes: readonly string[];
}

/// Measures a submission's proof and interprets it against the attempt (#47).
///
/// Runs on every submission, costs nothing, and involves no model. For the
/// third of Bsheel's catalogue that content analysis cannot serve this is the
/// entire signal; everywhere else it is still the strongest one, because a
/// photograph captured before the quest was assigned is recycled whatever it
/// depicts.
@Injectable()
export class ProofProvenanceService {
  private readonly logger = new Logger(ProofProvenanceService.name);

  constructor(
    private readonly repository: ProofVerificationRepository,
    private readonly forensics: MediaForensicsService,
    private readonly config: ConfigService<Environment, true>,
  ) {}

  async inspect(submissionId: string): Promise<ProvenanceOutcome | null> {
    const subject = await this.repository.forensicsSubject(submissionId);
    if (!subject) return null;

    const maxBytes = this.config.get('AI_VERIFICATION_MAX_IMAGE_BYTES', { infer: true });
    const maxImages = this.config.get('AI_VERIFICATION_MAX_IMAGES', { infer: true });
    const threshold = this.config.get('AI_VERIFICATION_NEAR_DUPLICATE_DISTANCE', { infer: true });

    const keys = this.parseMediaKeys(subject.mediaUrl);
    const images: ProofImage[] = [];
    const unreadableMedia: string[] = [];

    // The first readable image is the one the report is built from. Proof is
    // one frame in the overwhelming majority of cases, and a report that
    // averaged several files would be harder for a moderator to act on than
    // one that names a specific file's problem.
    let primary: Awaited<ReturnType<MediaForensicsService['measure']>> = null;

    for (const key of keys) {
      if (images.length >= maxImages) {
        unreadableMedia.push(`${keys.length - maxImages} further file(s) beyond the per-submission image cap`);
        break;
      }
      const facts = await this.forensics.measure(key, maxBytes);
      if (!facts) {
        // Video reaches here only when ffmpeg is unavailable or the clip
        // would not decode; otherwise it is measured from sampled frames.
        unreadableMedia.push('a file that could not be decoded (oversized, corrupt, or video without ffmpeg available)');
        continue;
      }
      if (!isSupportedImageType(`image/${facts.image.format}`)) {
        unreadableMedia.push(`an image in an unsupported format (${facts.image.format})`);
        continue;
      }

      primary ??= facts;
      // A video contributes several frames; a still contributes one. Both
      // came back with the measurement, so neither costs a second read.
      const mediaType = `image/${facts.image.format === 'jpg' ? 'jpeg' : facts.image.format}` as ProofImage['mediaType'];
      for (const frame of facts.frames) {
        if (images.length >= maxImages) break;
        images.push({ mediaType, base64: frame.toString('base64') });
      }

      await this.repository.recordObjectFacts({
        objectKey: key,
        capturedAt: facts.exif.capturedAt,
        width: facts.image.width,
        height: facts.image.height,
        perceptualHash: facts.perceptualHash,
        contentMd5: facts.contentHash,
        report: { exif: { ...facts.exif }, image: { ...facts.image } },
      });
    }

    if (!primary) {
      // Nothing measurable. The report still has to exist, so the policy can
      // see that provenance was unexamined rather than clean.
      const report = buildForensicsReport({
        exif: { capturedAtHasOffset: false, hasGps: false },
        image: { width: 0, height: 0, format: 'unknown' },
        assignedAt: subject.assignedAt,
        submittedAt: subject.submittedAt,
      });
      await this.repository.recordForensics(submissionId, this.serialise(report, unreadableMedia));
      return { report, images: [], unreadableMedia, notes: this.notes(report) };
    }

    const duplicate = await this.repository.findDuplicate(
      submissionId,
      subject.userId,
      primary.contentHash,
      primary.perceptualHash,
      threshold,
    );

    if (primary.wasVideo) {
      // Recorded as context rather than a finding: it is not a doubt, it is
      // how the frames were obtained, and video is harder to fake than a
      // still.
      unreadableMedia.push(
        `video proof was judged from ${primary.frames.length} sampled frame(s) rather than the clip`,
      );
    }

    const report = buildForensicsReport({
      exif: primary.exif,
      image: primary.image,
      assignedAt: subject.assignedAt,
      submittedAt: subject.submittedAt,
      exactDuplicateOf: duplicate?.exact
        ? { submissionId: duplicate.submissionId, ownedByThisUser: duplicate.ownedByThisUser }
        : undefined,
      nearDuplicateOf: duplicate && !duplicate.exact
        ? {
            submissionId: duplicate.submissionId,
            distance: duplicate.distance,
            ownedByThisUser: duplicate.ownedByThisUser,
          }
        : undefined,
    });

    await this.repository.recordForensics(submissionId, this.serialise(report, unreadableMedia));
    this.logger.debug(
      { submissionId, captureWindow: report.captureWindow, blocks: report.blocksAutomatedApproval },
      'Provenance measured',
    );

    return { report, images, unreadableMedia, notes: this.notes(report) };
  }

  private notes(report: ForensicsReport): string[] {
    // Only findings that carry weight. Passing the reassuring ones to the
    // model would pad the prompt without changing anything it can conclude.
    return report.findings
      .filter((finding) => finding.weight !== 'info')
      .map((finding) => finding.detail);
  }

  private serialise(report: ForensicsReport, unreadableMedia: readonly string[]): Record<string, unknown> {
    return {
      captureWindow: report.captureWindow,
      blocksAutomatedApproval: report.blocksAutomatedApproval,
      findings: report.findings.map((finding) => ({ ...finding })),
      unreadableMedia: [...unreadableMedia],
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
