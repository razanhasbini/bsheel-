import { ConflictException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
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
  readonly country_code: string | null;
}

export interface UserXpStatsRecord {
  readonly total_xp: number;
  readonly current_level: number;
  readonly xp_to_next_level: number;
  readonly total_quests: number;
  readonly rank: number;
}

export interface StreakRecord {
  current: number;
  longest: number;
  lastDay: string | null;
  atRisk: boolean;
}

const publicColumns = `id, username::text, display_name, avatar_url, bio, xp, level,
  quests_completed, profile_completed, created_at, updated_at`;

@Injectable()
export class ProfilesRepository {
  constructor(
    private readonly database: DatabaseService,
    private readonly config: ConfigService<Environment, true>,
  ) {}

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
      `SELECT ${publicColumns}, age_verified, analytics_consent_at, country_code FROM profiles WHERE id = $1`,
      [id],
    );
    return result.rows[0] ?? null;
  }

  /// Streak (#46): the run of consecutive UTC days on which this user has at
  /// least one approved submission.
  ///
  /// Counted by `submitted_at` — the day the work was done — never by
  /// `reviewed_at`. Keying on review time would let a moderation backlog
  /// break a streak the user has no way to protect, and the admin dashboard
  /// measures queue age in hours.
  ///
  /// Derived rather than stored. XP is stored and drifts badly enough to need
  /// a reconciliation screen; a second counter kept in two places would earn
  /// a second one. Backed by `submissions_user_approved_day_idx`.
  ///
  /// `current` counts the run only while it is still alive: its last day must
  /// be today or yesterday, since a streak whose last day was yesterday dies
  /// at the end of today. `longest` is the best run ever, which may be an
  /// older one than the current.
  async streak(userId: string): Promise<StreakRecord> {
    // `STREAK_TIMEZONE`, not UTC. The audience is at UTC+3, so a UTC day
    // boundary falls at 03:00 local: submissions at 23:00 and 01:00 local are
    // two consecutive days to the person who made them and one single day to
    // a UTC bucket, so a late-night post did not advance the streak (#63).
    // Passed as a parameter, never interpolated.
    const timezone = this.config.get('STREAK_TIMEZONE', { infer: true });
    const result = await this.database.query<{
      current_streak: number;
      longest_streak: number;
      last_day: string | null;
      today: string;
    }>(
      `WITH days AS (
         SELECT DISTINCT (s.submitted_at AT TIME ZONE $2)::date AS d
         FROM submissions s
         WHERE s.user_id = $1 AND s.status = 'approved' AND s.visibility <> 'deleted'
       ),
       grouped AS (
         SELECT d, d - (row_number() OVER (ORDER BY d))::int AS grp FROM days
       ),
       runs AS (
         SELECT grp, count(*)::int AS len, max(d) AS last_day FROM grouped GROUP BY grp
       )
       SELECT
         COALESCE(MAX(CASE WHEN last_day >= (now() AT TIME ZONE $2)::date - 1
                           THEN len END), 0)::int AS current_streak,
         COALESCE(MAX(len), 0)::int AS longest_streak,
         to_char(MAX(last_day), 'YYYY-MM-DD') AS last_day,
         to_char((now() AT TIME ZONE $2)::date, 'YYYY-MM-DD') AS today
       FROM runs`,
      [userId, timezone],
    );
    const row = result.rows[0];
    return {
      current: row?.current_streak ?? 0,
      longest: row?.longest_streak ?? 0,
      lastDay: row?.last_day ?? null,
      // Alive but expiring tonight, which is what the reminder is about.
      //
      // "Today" now comes from the same query and the same zone as the run
      // itself. It used to be the API host's `new Date()` in UTC, so between
      // 21:00 and 24:00 UTC — midnight to 03:00 local — the server called a
      // streak submitted-to today "at risk" and the reminder job disagreed
      // with the number on screen.
      atRisk: (row?.current_streak ?? 0) > 0
        && row?.last_day != null
        && row.last_day !== row.today,
    };
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
             WHERE user_id = $1 AND object_key = $2 AND kind = 'avatar' AND status = 'ready'
               AND deleted_at IS NULL AND reclaim_started_at IS NULL FOR UPDATE`,
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
           country_code = CASE WHEN $9 THEN $10 ELSE country_code END,
           age_verified = CASE WHEN $11 THEN true ELSE age_verified END,
           updated_at = now()
         WHERE id = $1
         RETURNING ${publicColumns}, age_verified, analytics_consent_at, country_code`,
        [
          id,
          input.username?.trim().toLowerCase(),
          input.displayName?.trim(),
          Object.hasOwn(input, 'avatarUrl'),
          input.avatarUrl ?? null,
          Object.hasOwn(input, 'bio'),
          input.bio?.trim() || null,
          input.profileCompleted,
          Object.hasOwn(input, 'countryCode'),
          // Uppercased to match the column's CHECK, so aggregation never has
          // to fold case and 'lb' and 'LB' cannot become two countries.
          input.countryCode ? input.countryCode.toUpperCase() : null,
          input.ageVerified === true,
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
