import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';

export interface SearchResult {
  readonly users: readonly Record<string, unknown>[];
  readonly quests: readonly Record<string, unknown>[];
  readonly posts: readonly Record<string, unknown>[];
}

@Injectable()
export class SearchRepository {
  constructor(private readonly database: DatabaseService) {}

  async search(viewerId: string, query: string, limit: number, offset: number): Promise<SearchResult> {
    const escaped = query.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
    const pattern = `%${escaped}%`;

    const [users, quests, posts] = await Promise.all([
      this.database.query(
        `SELECT p.id, p.username::text, p.display_name, p.avatar_url, p.bio, p.xp, p.level,
                p.quests_completed, p.created_at, p.updated_at, p.profile_completed
         FROM profiles p
         WHERE (lower(p.username::text) LIKE lower($2) ESCAPE '\\'
                OR lower(p.display_name) LIKE lower($2) ESCAPE '\\')
           AND NOT EXISTS (
             SELECT 1 FROM blocked_users b
             WHERE (b.blocker_id = $1 AND b.blocked_id = p.id)
                OR (b.blocker_id = p.id AND b.blocked_id = $1)
           )
         ORDER BY p.xp DESC, p.created_at ASC, p.id
         LIMIT $3 OFFSET $4`,
        [viewerId, pattern, limit, offset],
      ),
      this.database.query(
        `SELECT id, title, description, category, difficulty, xp_reward, duration_hours,
                is_active, created_by, created_at, updated_at
         FROM quests
         WHERE is_active
           AND NOT EXISTS (SELECT 1 FROM quest_destinations d WHERE d.quest_id=quests.id)
           AND (lower(title) LIKE lower($1) ESCAPE '\\'
                OR lower(description) LIKE lower($1) ESCAPE '\\'
                OR lower(category) LIKE lower($1) ESCAPE '\\')
         ORDER BY xp_reward DESC, created_at DESC, id
         LIMIT $2 OFFSET $3`,
        [pattern, limit, offset],
      ),
      this.database.query(
        `SELECT s.id, s.user_quest_id, s.user_id, s.media_url, s.media_type::text,
                s.caption, s.status::text, s.reviewed_by, s.review_note, s.submitted_at,
                s.reviewed_at, s.appeal_note, s.appealed, s.show_in_feed,
                s.visibility::text, s.deleted_at,
                json_build_object(
                  'quest_id', q.id,
                  'quests', json_build_object('title', q.title)
                ) AS user_quests,
                json_build_object(
                  'username', p.username::text,
                  'display_name', p.display_name
                ) AS profiles
         FROM submissions s
         JOIN user_quests uq ON uq.id = s.user_quest_id
         JOIN quests q ON q.id = uq.quest_id
         JOIN profiles p ON p.id = s.user_id
         WHERE s.status = 'approved' AND s.visibility = 'visible' AND s.deleted_at IS NULL
           AND (s.user_id = $1 OR (
             q.is_active AND (
               lower(q.title) LIKE lower($2) ESCAPE '\\'
               OR lower(q.description) LIKE lower($2) ESCAPE '\\'
               OR lower(q.category) LIKE lower($2) ESCAPE '\\'
             )
           ))
           AND NOT EXISTS (
             SELECT 1 FROM blocked_users b
             WHERE (b.blocker_id = $1 AND b.blocked_id = s.user_id)
                OR (b.blocker_id = s.user_id AND b.blocked_id = $1)
           )
         ORDER BY s.submitted_at DESC, s.id DESC
         LIMIT $3 OFFSET $4`,
        [viewerId, pattern, Math.min(limit, 24), offset],
      ),
    ]);

    return { users: users.rows, quests: quests.rows, posts: posts.rows };
  }
}
