var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { ConflictException, Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
const publicColumns = `id, username::text, display_name, avatar_url, bio, xp, level,
  quests_completed, profile_completed, created_at, updated_at`;
let ProfilesRepository = class ProfilesRepository {
    database;
    constructor(database) {
        this.database = database;
    }
    async findPublic(id) {
        const result = await this.database.query(`SELECT ${publicColumns} FROM profiles WHERE id = $1`, [id]);
        return result.rows[0] ?? null;
    }
    async findOwn(id) {
        const result = await this.database.query(`SELECT ${publicColumns}, age_verified, analytics_consent_at FROM profiles WHERE id = $1`, [id]);
        return result.rows[0] ?? null;
    }
    async xpStats(id) {
        const result = await this.database.query(`SELECT p.xp AS total_xp, p.level AS current_level,
              (p.level * 100) - p.xp AS xp_to_next_level,
              p.quests_completed AS total_quests,
              (SELECT count(*)::integer + 1 FROM profiles ranked
               WHERE ranked.xp > p.xp OR (ranked.xp = p.xp AND ranked.created_at < p.created_at)) AS rank
       FROM profiles p WHERE p.id = $1`, [id]);
        return result.rows[0] ?? null;
    }
    async listByXp(limit) {
        const capped = Math.min(Math.max(limit, 1), 200);
        return (await this.database.query(`SELECT ${publicColumns} FROM profiles ORDER BY xp DESC, id LIMIT $1`, [capped])).rows;
    }
    async update(id, input) {
        try {
            return await this.database.transaction(async (transaction) => {
                if (input.avatarUrl) {
                    const avatar = await transaction.query(`SELECT 1 FROM media_objects
             WHERE user_id = $1 AND object_key = $2 AND kind = 'avatar' AND status = 'ready'`, [id, input.avatarUrl]);
                    if (!avatar.rowCount) {
                        throw new ConflictException({ code: 'UNVERIFIED_AVATAR', message: 'Avatar must be an owned, verified upload' });
                    }
                }
                const result = await transaction.query(`UPDATE profiles SET
           username = COALESCE($2, username), display_name = COALESCE($3, display_name),
           avatar_url = CASE WHEN $4 THEN $5 ELSE avatar_url END,
           bio = CASE WHEN $6 THEN $7 ELSE bio END,
           profile_completed = CASE WHEN $8 = true THEN true ELSE profile_completed END,
           updated_at = now()
         WHERE id = $1
         RETURNING ${publicColumns}, age_verified, analytics_consent_at`, [
                    id,
                    input.username?.trim().toLowerCase(),
                    input.displayName?.trim(),
                    Object.hasOwn(input, 'avatarUrl'),
                    input.avatarUrl ?? null,
                    Object.hasOwn(input, 'bio'),
                    input.bio?.trim() || null,
                    input.profileCompleted,
                ]);
                if (result.rows[0])
                    await this.emitUpdated(id, 'profile_edit', transaction);
                return result.rows[0] ?? null;
            });
        }
        catch (error) {
            if (typeof error === 'object' && error !== null && 'code' in error && error.code === '23505') {
                throw new ConflictException({ code: 'USERNAME_TAKEN', message: 'Username is already in use' });
            }
            throw error;
        }
    }
    async setAnalyticsConsent(id, consented) {
        return this.database.transaction(async (transaction) => {
            const result = await transaction.query(`UPDATE profiles SET analytics_consent_at = CASE WHEN $2 THEN now() ELSE NULL END,
           updated_at = now() WHERE id = $1 RETURNING analytics_consent_at`, [id, consented]);
            if (result.rows[0])
                await this.emitUpdated(id, 'analytics_consent', transaction);
            return result.rows[0]?.analytics_consent_at ?? null;
        });
    }
    async acceptTerms(id) {
        return this.database.transaction(async (transaction) => {
            const result = await transaction.query(`UPDATE profiles SET accepted_terms_at = COALESCE(accepted_terms_at, now()),
           updated_at = now() WHERE id = $1 RETURNING accepted_terms_at`, [id]);
            if (result.rows[0])
                await this.emitUpdated(id, 'terms_accepted', transaction);
            return result.rows[0].accepted_terms_at;
        });
    }
    async accountStatus(id) {
        const result = await this.database.query('SELECT status::text FROM users WHERE id = $1', [id]);
        return result.rows[0]?.status ?? null;
    }
    async emitUpdated(profileId, reason, transaction) {
        await transaction.query(`INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       VALUES ('profile', $1, 'profile.updated', $2::jsonb)`, [profileId, JSON.stringify({ profileId, reason })]);
    }
};
ProfilesRepository = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [DatabaseService])
], ProfilesRepository);
export { ProfilesRepository };
//# sourceMappingURL=profiles.repository.js.map