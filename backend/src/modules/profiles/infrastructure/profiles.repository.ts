import { ConflictException, Injectable } from '@nestjs/common';
import { DatabaseService, type DatabaseTransaction } from '../../../infrastructure/database/database.service.js';
import type { UpdateProfileDto } from '../presentation/profile.dto.js';

export interface PublicProfileRecord {
  readonly id: string;
  readonly username: string;
  readonly display_name: string;
  readonly avatar_url: string | null;
  readonly bio: string | null;
  readonly xp: number;
  readonly level: number;
  readonly quests_completed: number;
  readonly profile_completed: boolean;
  readonly created_at: Date;
  readonly updated_at: Date;
}

export interface OwnProfileRecord extends PublicProfileRecord {
  readonly age_verified: boolean;
  readonly analytics_consent_at: Date | null;
}

export interface UserXpStatsRecord {
  readonly total_xp: number;
  readonly current_level: number;
  readonly xp_to_next_level: number;
  readonly total_quests: number;
  readonly rank: number;
}

const publicColumns = `id, username::text, display_name, avatar_url, bio, xp, level,
  quests_completed, profile_completed, created_at, updated_at`;

@Injectable()
export class ProfilesRepository {
  constructor(private readonly database: DatabaseService) {}

  async findPublic(id: string): Promise<PublicProfileRecord | null> {
    const result = await this.database.query<PublicProfileRecord>(
      `SELECT ${publicColumns} FROM profiles WHERE id = $1`,
      [id],
    );
    return result.rows[0] ?? null;
  }

  /// Exact, case-insensitive username lookup. `username` is citext and
  /// UNIQUE, so this resolves at most one row — unlike search, which is
  /// fuzzy and must never decide where an @mention navigates.
  async findPublicByUsername(username: string): Promise<PublicProfileRecord | null> {
    const result = await this.database.query<PublicProfileRecord>(
      `SELECT ${publicColumns} FROM profiles WHERE username = $1`,
      [username.trim()],
    );
    return result.rows[0] ?? null;
  }

  async findOwn(id: string): Promise<OwnProfileRecord | null> {
    const result = await this.database.query<OwnProfileRecord>(
      `SELECT ${publicColumns}, age_verified, analytics_consent_at FROM profiles WHERE id = $1`,
      [id],
    );
    return result.rows[0] ?? null;
  }

  async xpStats(id: string): Promise<UserXpStatsRecord | null> {
    const result = await this.database.query<UserXpStatsRecord>(
      `SELECT p.xp AS total_xp, p.level AS current_level,
              (p.level * 100) - p.xp AS xp_to_next_level,
              p.quests_completed AS total_quests,
              (SELECT count(*)::integer + 1 FROM profiles ranked
               WHERE ranked.xp > p.xp OR (ranked.xp = p.xp AND ranked.created_at < p.created_at)) AS rank
       FROM profiles p WHERE p.id = $1`,
      [id],
    );
    return result.rows[0] ?? null;
  }

  async listByXp(limit: number): Promise<readonly PublicProfileRecord[]> {
    const capped = Math.min(Math.max(limit, 1), 200);
    return (await this.database.query<PublicProfileRecord>(
      `SELECT ${publicColumns} FROM profiles ORDER BY xp DESC, id LIMIT $1`,
      [capped],
    )).rows;
  }

  async update(id: string, input: UpdateProfileDto): Promise<OwnProfileRecord | null> {
    try {
      return await this.database.transaction(async (transaction) => {
        if (input.avatarUrl) {
          const avatar = await transaction.query(
            `SELECT 1 FROM media_objects
             WHERE user_id = $1 AND object_key = $2 AND kind = 'avatar' AND status = 'ready'`,
            [id, input.avatarUrl],
          );
          if (!avatar.rowCount) {
            throw new ConflictException({ code: 'UNVERIFIED_AVATAR', message: 'Avatar must be an owned, verified upload' });
          }
        }
        const result = await transaction.query<OwnProfileRecord>(
        `UPDATE profiles SET
           username = COALESCE($2, username), display_name = COALESCE($3, display_name),
           avatar_url = CASE WHEN $4 THEN $5 ELSE avatar_url END,
           bio = CASE WHEN $6 THEN $7 ELSE bio END,
           profile_completed = CASE WHEN $8 = true THEN true ELSE profile_completed END,
           updated_at = now()
         WHERE id = $1
         RETURNING ${publicColumns}, age_verified, analytics_consent_at`,
        [
          id,
          input.username?.trim().toLowerCase(),
          input.displayName?.trim(),
          Object.hasOwn(input, 'avatarUrl'),
          input.avatarUrl ?? null,
          Object.hasOwn(input, 'bio'),
          input.bio?.trim() || null,
          input.profileCompleted,
        ],
        );
        if (result.rows[0]) await this.emitUpdated(id, 'profile_edit', transaction);
        return result.rows[0] ?? null;
      });
    } catch (error) {
      if (typeof error === 'object' && error !== null && 'code' in error && error.code === '23505') {
        throw new ConflictException({ code: 'USERNAME_TAKEN', message: 'Username is already in use' });
      }
      throw error;
    }
  }

  async setAnalyticsConsent(id: string, consented: boolean): Promise<Date | null> {
    return this.database.transaction(async (transaction) => {
      const result = await transaction.query<{ analytics_consent_at: Date | null }>(
        `UPDATE profiles SET analytics_consent_at = CASE WHEN $2 THEN now() ELSE NULL END,
           updated_at = now() WHERE id = $1 RETURNING analytics_consent_at`,
        [id, consented],
      );
      if (result.rows[0]) await this.emitUpdated(id, 'analytics_consent', transaction);
      return result.rows[0]?.analytics_consent_at ?? null;
    });
  }

  async acceptTerms(id: string): Promise<Date> {
    return this.database.transaction(async (transaction) => {
      const result = await transaction.query<{ accepted_terms_at: Date }>(
        `UPDATE profiles SET accepted_terms_at = COALESCE(accepted_terms_at, now()),
           updated_at = now() WHERE id = $1 RETURNING accepted_terms_at`,
        [id],
      );
      if (result.rows[0]) await this.emitUpdated(id, 'terms_accepted', transaction);
      return result.rows[0].accepted_terms_at;
    });
  }

  async accountStatus(id: string): Promise<string | null> {
    const result = await this.database.query<{ status: string }>('SELECT status::text FROM users WHERE id = $1', [id]);
    return result.rows[0]?.status ?? null;
  }

  private async emitUpdated(
    profileId: string,
    reason: string,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    await transaction.query(
      `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       VALUES ('profile', $1, 'profile.updated', $2::jsonb)`,
      [profileId, JSON.stringify({ profileId, reason })],
    );
  }
}
