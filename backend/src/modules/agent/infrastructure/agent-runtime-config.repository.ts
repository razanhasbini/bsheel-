import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';

const SUBMISSION_VERIFICATION_KEY = 'agent_submission_verification_enabled';

/**
 * Reads the admin-toggleable app_config flag (see migration 0026) that
 * pauses/resumes the AI submission-verification pipeline without a deploy.
 * A fresh read every call is deliberate — this is checked once per queued
 * job, not per HTTP request, so staleness from caching isn't worth the
 * complexity, and an admin pausing it should take effect on the very next
 * job, not after some TTL expires.
 */
@Injectable()
export class AgentRuntimeConfigRepository {
  constructor(private readonly database: DatabaseService) {}

  async isSubmissionVerificationEnabled(): Promise<boolean> {
    const result = await this.database.query<{ value: unknown }>(
      'SELECT value FROM app_config WHERE key = $1',
      [SUBMISSION_VERIFICATION_KEY],
    );
    const value = result.rows[0]?.value;
    return value === true || value === 'true';
  }
}
