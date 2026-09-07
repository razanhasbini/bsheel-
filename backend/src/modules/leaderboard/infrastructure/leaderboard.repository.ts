import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';

@Injectable()
export class LeaderboardRepository {
  constructor(private readonly database: DatabaseService) {}

  async list(viewerId: string, scope: 'global' | 'following', limit: number, offset: number) {
    const result = await this.database.query(
      `WITH eligible AS (
         SELECT p.*
         FROM profiles p
         WHERE ($2 = 'global' OR p.id = $1 OR EXISTS (
             SELECT 1 FROM follows f WHERE f.follower_id = $1 AND f.following_id = p.id
           ))
           AND NOT EXISTS (
             SELECT 1 FROM blocked_users b
             WHERE (b.blocker_id = $1 AND b.blocked_id = p.id)
                OR (b.blocker_id = p.id AND b.blocked_id = $1)
           )
       ), ranked AS (
         SELECT row_number() OVER (ORDER BY xp DESC, created_at ASC, id)::integer AS rank,
                id AS user_id, username::text, display_name, avatar_url, xp, level,
                quests_completed
         FROM eligible
       )
       SELECT * FROM ranked ORDER BY rank LIMIT $3 OFFSET $4`,
      [viewerId, scope, limit, offset],
    );
    return result.rows;
  }
}
