import { Injectable, Logger } from '@nestjs/common';
import type { CvEvidence } from '../../modules/agent/domain/agent.schemas.js';
import type { CvEvidenceAnalysisInput, CvEvidenceProvider } from '../../modules/agent/domain/cv-evidence.port.js';

/** Fail-closed default when CV_PROVIDER is unset. Never fabricates a positive result. */
@Injectable()
export class NullCvEvidenceProvider implements CvEvidenceProvider {
  private readonly logger = new Logger(NullCvEvidenceProvider.name);

  async analyze(input: CvEvidenceAnalysisInput): Promise<CvEvidence> {
    this.logger.debug({ submissionId: input.submissionId }, 'CV provider not configured; returning UNAVAILABLE');
    return {
      status: 'UNAVAILABLE',
      provider: 'none',
      modelVersion: 'none',
      analyzedAt: new Date().toISOString(),
      detections: [],
      keyFrames: [],
      warnings: ['CV_PROVIDER is not configured'],
    };
  }
}
