import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';

export type PhoneSigninIntent = 'sign_in' | 'link';

export interface PhoneSigninStateRecord {
  readonly id: string;
  readonly intent: PhoneSigninIntent;
  readonly userId: string | null;
  readonly ageVerified: boolean;
  readonly redirectUri: string;
  /** Null only for rows created before migration 0030. */
  readonly nonce: string | null;
  /**
   * The E.164 number the user claimed when the flow started (migration
   * 0032). Number Verification V1 checks the device against this exact
   * value, so it is read back from here rather than from the callback —
   * the callback is attacker-influenced, this row is not.
   *
   * Null only for rows created before 0032, which the callback rejects.
   */
  readonly claimedPhoneNumber: string | null;
  /**
   * Which CAMARA V1 flow the authorization request used (migration 0033).
   * Null for rows created before it, which were all standard-flow.
   */
  readonly oauthFlow: 'fast' | 'standard' | null;
  /** Optional address offered at signup (migration 0034). */
  readonly claimedEmail: string | null;
}

export interface PhoneSigninHandoff {
  readonly userId: string;
  readonly intent: PhoneSigninIntent;
}

/**
 * Server-side state for the CAMARA Number Verification redirect (see
 * migration 0027). Two consume-once steps, each an atomic UPDATE ... RETURNING
 * so a duplicate callback or a replayed handoff can never succeed twice:
 * `consumePending` (the Nokia redirect back) and `consumeHandoff` (the
 * mobile app's follow-up POST). Tokens are never embedded in the redirect
 * URL between the two — the handoff code is opaque and single-use.
 */
@Injectable()
export class PhoneSigninStateRepository {
  constructor(private readonly database: DatabaseService) {}

  async start(input: {
    state: string;
    intent: PhoneSigninIntent;
    userId?: string;
    ageVerified?: boolean;
    redirectUri: string;
    nonce: string;
    claimedPhoneNumber: string;
    oauthFlow: 'fast' | 'standard';
    claimedEmail?: string | null;
    ttlMs: number;
  }): Promise<void> {
    await this.database.query(
      `INSERT INTO phone_signin_states (state, intent, user_id, age_verified, redirect_uri, nonce, claimed_phone_number, oauth_flow, claimed_email, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, now() + make_interval(secs => $10))`,
      [
        input.state,
        input.intent,
        input.userId ?? null,
        input.ageVerified ?? false,
        input.redirectUri,
        input.nonce,
        input.claimedPhoneNumber,
        input.oauthFlow,
        input.claimedEmail ?? null,
        input.ttlMs / 1000,
      ],
    );
  }

  /// Marks the row 'failed' immediately on consumption; markCompleted()
  /// flips it to 'completed' only once the CAMARA exchange actually
  /// succeeds. A crash mid-flight leaves it 'failed', never a replayable
  /// 'pending' row.
  async consumePending(state: string): Promise<PhoneSigninStateRecord | null> {
    const result = await this.database.query<{
      id: string;
      intent: PhoneSigninIntent;
      user_id: string | null;
      age_verified: boolean;
      redirect_uri: string;
      nonce: string | null;
      claimed_phone_number: string | null;
      oauth_flow: 'fast' | 'standard' | null;
      claimed_email: string | null;
    }>(
      `UPDATE phone_signin_states SET status = 'failed'
       WHERE state = $1 AND status = 'pending' AND expires_at > now()
       RETURNING id, intent, user_id, age_verified, redirect_uri, nonce, claimed_phone_number, oauth_flow, claimed_email`,
      [state],
    );
    const row = result.rows[0];
    return row
      ? {
          id: row.id,
          intent: row.intent,
          userId: row.user_id,
          ageVerified: row.age_verified,
          redirectUri: row.redirect_uri,
          nonce: row.nonce,
          claimedPhoneNumber: row.claimed_phone_number,
          oauthFlow: row.oauth_flow,
          claimedEmail: row.claimed_email,
        }
      : null;
  }

  async markCompleted(id: string, resultUserId: string, handoffCode: string, handoffTtlMs: number): Promise<void> {
    await this.database.query(
      `UPDATE phone_signin_states SET status = 'completed', result_user_id = $2, handoff_code = $3,
         handoff_expires_at = now() + make_interval(secs => $4)
       WHERE id = $1`,
      [id, resultUserId, handoffCode, handoffTtlMs / 1000],
    );
  }

  async consumeHandoff(handoffCode: string): Promise<PhoneSigninHandoff | null> {
    const result = await this.database.query<{ result_user_id: string; intent: PhoneSigninIntent }>(
      `UPDATE phone_signin_states SET status = 'consumed'
       WHERE handoff_code = $1 AND status = 'completed' AND handoff_expires_at > now()
       RETURNING result_user_id, intent`,
      [handoffCode],
    );
    const row = result.rows[0];
    return row ? { userId: row.result_user_id, intent: row.intent } : null;
  }
}
