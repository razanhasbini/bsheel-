var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
let LeaderboardRepository = class LeaderboardRepository {
    database;
    constructor(database) {
        this.database = database;
    }
    async list(viewerId, scope, limit, offset) {
        const result = await this.database.query(`WITH eligible AS (
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
       SELECT * FROM ranked ORDER BY rank LIMIT $3 OFFSET $4`, [viewerId, scope, limit, offset]);
        return result.rows;
    }
};
LeaderboardRepository = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [DatabaseService])
], LeaderboardRepository);
export { LeaderboardRepository };
//# sourceMappingURL=leaderboard.repository.js.map