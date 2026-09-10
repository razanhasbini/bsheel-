import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../config/environment.js';
import { CvEvidenceSchema, type CvEvidence } from '../../modules/agent/domain/agent.schemas.js';
import type { CvEvidenceAnalysisInput, CvEvidenceProvider } from '../../modules/agent/domain/cv-evidence.port.js';

/**
 * Calls an external CV service over HTTP. This adapter owns only the wire
 * contract (POST {CV_SERVICE_BASE_URL}/analyze with CvEvidenceAnalysisInput,
 * expecting a CvEvidenceSchema-shaped JSON body back) and failure handling —
 * this is the exact contract a computer-vision engineer's service needs to
 * implement to plug in. Model choice and training are entirely theirs.
 *
 * A missing base URL, a timeout, a non-2xx response, or a body that fails
 * schema validation all degrade to UNAVAILABLE — this must never invent a
 * result the remote service did not actually return.
 */
@Injectable()
export class HttpCvEvidenceProvider implements CvEvidenceProvider {
  private readonly logger = new Logger(HttpCvEvidenceProvider.name);

  constructor(private readonly config: ConfigService<Environment, true>) {}

  async analyze(input: CvEvidenceAnalysisInput): Promise<CvEvidence> {
    const baseUrl = this.config.get('CV_SERVICE_BASE_URL', { infer: true });
    if (!baseUrl) return this.unavailable('CV_SERVICE_BASE_URL is not configured');

    const timeoutMs = this.config.get('CV_TIMEOUT_MS', { infer: true });
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const token = this.config.get('CV_SERVICE_AUTH_TOKEN', { infer: true });
      const response = await fetch(new URL('/analyze', baseUrl), {
        method: 'POST',
        headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify(input),
        signal: controller.signal,
      });
      if (!response.ok) return this.unavailable(`CV service responded ${response.status}`);

      const body: unknown = await response.json();
      const parsed = CvEvidenceSchema.safeParse(body);
      if (!parsed.success) {
        this.logger.warn({ issues: parsed.error.issues }, 'CV service response failed schema validation');
        return this.unavailable('CV service response did not match the expected contract');
      }
      return parsed.data;
    } catch (error) {
      this.logger.warn({ errorName: error instanceof Error ? error.name : 'UnknownError' }, 'CV service call failed');
      return this.unavailable(error instanceof Error ? error.message : 'CV service call failed');
    } finally {
      clearTimeout(timeout);
    }
  }

  private unavailable(reason: string): CvEvidence {
    return {
      status: 'UNAVAILABLE',
      provider: 'http',
      modelVersion: 'unknown',
      analyzedAt: new Date().toISOString(),
      detections: [],
      keyFrames: [],
      warnings: [reason],
    };
  }
}
