import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { MapPlaceDto, MapPlaceUpdateDto, MapQueryDto, MapQuestLinkDto } from '../presentation/map.dto.js';

// Bound to the requesting user. Device GPS never grants this predicate.
const evidence = `EXISTS (SELECT 1 FROM map_location_evidence e WHERE e.user_id=$1
  AND e.place_id=p.id AND e.location_verified AND e.location_retrieved AND e.geofence_verified
  AND e.verified_at <= now() AND e.expires_at > now())`;
const visible = `p.is_published AND (p.category <> 'hidden' OR ${evidence})`;

@Injectable()
export class MapRepository {
  constructor(private readonly database: DatabaseService) {}

  async canViewProfile(viewerId:string,userId:string) {
    const result=await this.database.query(`SELECT 1 FROM users u WHERE u.id=$2 AND u.deleted_at IS NULL
      AND (u.id=$1 OR u.status='active') AND NOT EXISTS(SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id=$1 AND b.blocked_id=$2) OR (b.blocker_id=$2 AND b.blocked_id=$1))`,[viewerId,userId]);
    return !!result.rowCount;
  }

  async countries(userId: string) {
    return (await this.database.query(`
      WITH discoveries AS (
        SELECT d.place_id, bool_or(s.status='approved') AS confirmed
        FROM submissions s JOIN user_quests uq ON uq.id=s.user_quest_id
        JOIN quest_destinations d ON d.quest_id=uq.quest_id
        WHERE s.user_id=$1 AND s.status IN ('pending','approved')
          AND s.deleted_at IS NULL AND s.visibility <> 'deleted' AND s.moderation_removed_at IS NULL
        GROUP BY d.place_id
      )
      SELECT c.code,c.name,c.geometry_id,count(p.id)::int AS total,
        count(discoveries.place_id)::int AS discovered,
        count(discoveries.place_id) FILTER (WHERE discoveries.confirmed)::int AS confirmed,
        count(saved.place_id)::int AS saved
      FROM map_countries c LEFT JOIN map_places p ON p.country_code=c.code AND p.is_published
      LEFT JOIN discoveries ON discoveries.place_id=p.id
      LEFT JOIN saved_map_places saved ON saved.place_id=p.id AND saved.user_id=$1
      GROUP BY c.code ORDER BY c.name`, [userId])).rows;
  }

  async places(userId: string, query: MapQueryDto) {
    return (await this.database.query(`SELECT p.*,c.name AS country_name,c.geometry_id,
      EXISTS (SELECT 1 FROM saved_map_places b WHERE b.user_id=$1 AND b.place_id=p.id) AS saved,
      ${evidence} AS location_verified,
      (SELECT count(*)::int FROM quest_destinations d JOIN quests q ON q.id=d.quest_id
        WHERE d.place_id=p.id AND q.is_active) AS quest_count,
      EXISTS (SELECT 1 FROM quest_destinations d JOIN user_quests uq ON uq.quest_id=d.quest_id
        JOIN submissions s ON s.user_quest_id=uq.id WHERE d.place_id=p.id AND s.user_id=$1
        AND s.status IN ('pending','approved') AND s.deleted_at IS NULL AND s.visibility <> 'deleted'
        AND s.moderation_removed_at IS NULL) AS discovered
      FROM map_places p JOIN map_countries c ON c.code=p.country_code
      WHERE ${visible} AND ($2::text IS NULL OR p.country_code=$2)
        AND (NOT $7::boolean OR EXISTS(SELECT 1 FROM saved_map_places b WHERE b.user_id=$1 AND b.place_id=p.id))
        AND ($3::text IS NULL OR p.category=$3)
        AND ($4::text='' OR position(lower($4) in lower(p.name || ' ' || p.city || ' ' || c.name))>0)
      ORDER BY p.name,p.id LIMIT $5 OFFSET $6`,
    [userId, query.country ?? null, query.category ?? null, query.search?.trim() ?? '', query.limit, query.offset,query.saved==='true'])).rows;
  }

  async detail(userId: string, id: string) {
    const place = (await this.database.query(`SELECT p.*,${evidence} AS location_verified
      FROM map_places p WHERE p.id=$2 AND ${visible}`, [userId,id])).rows[0];
    if (!place) throw new NotFoundException({ code:'PLACE_NOT_FOUND',message:'Place not found' });
    const quests = (await this.database.query(`SELECT q.id,q.title,q.description,q.category,q.difficulty,
      q.duration_hours,q.xp_reward,d.requires_verification,
      (NOT d.requires_verification OR $2::boolean) AS unlocked
      FROM quest_destinations d JOIN quests q ON q.id=d.quest_id
      WHERE d.place_id=$1 AND q.is_active ORDER BY q.title,q.id`, [id,place.location_verified])).rows;
    const previews = (await this.database.query(`SELECT s.id,s.user_id,p.username::text,s.media_type,s.submitted_at,s.media_url
      FROM submissions s JOIN user_quests uq ON uq.id=s.user_quest_id
      JOIN quest_destinations d ON d.quest_id=uq.quest_id JOIN profiles p ON p.id=s.user_id
      JOIN users u ON u.id=s.user_id
      WHERE d.place_id=$2 AND s.status='approved' AND s.media_type='video'
        AND s.show_in_feed AND s.visibility='visible' AND s.deleted_at IS NULL AND s.moderation_removed_at IS NULL
        AND u.status='active' AND u.deleted_at IS NULL
        AND NOT EXISTS (SELECT 1 FROM blocked_users b WHERE
          (b.blocker_id=$1 AND b.blocked_id=s.user_id) OR (b.blocker_id=s.user_id AND b.blocked_id=$1))
      ORDER BY s.submitted_at DESC,s.id DESC LIMIT 12`, [userId,id])).rows;
    return { ...place,quests,previews };
  }

  async save(userId: string, id: string, save: boolean) {
    if (save) {
      await this.detail(userId,id);
      await this.database.query('INSERT INTO saved_map_places(user_id,place_id) VALUES ($1,$2) ON CONFLICT DO NOTHING',[userId,id]);
    } else {
      await this.database.query('DELETE FROM saved_map_places WHERE user_id=$1 AND place_id=$2',[userId,id]);
    }
    return { saved:save };
  }

  async adminPlaces() {
    return (await this.database.query(`SELECT p.*,c.name AS country_name,c.geometry_id,
        (SELECT count(*) FROM quest_destinations d WHERE d.place_id=p.id)::int AS quest_count
      FROM map_places p JOIN map_countries c ON c.code=p.country_code ORDER BY p.created_at DESC LIMIT 500`)).rows;
  }

  /// Admin view of one place, including the quests already linked to it.
  ///
  /// The public `detail` is gated on published-and-not-hidden, which excludes
  /// exactly the drafts and hidden places staff need to inspect. Without this
  /// they were linking blind: no way to see what was already pinned before
  /// pinning something else.
  async adminPlaceDetail(id: string) {
    const place = (await this.database.query(`SELECT p.*,c.name AS country_name,c.geometry_id
      FROM map_places p JOIN map_countries c ON c.code=p.country_code WHERE p.id=$1`,[id])).rows[0];
    if (!place) throw new NotFoundException({code:'PLACE_NOT_FOUND',message:'Place not found'});
    const quests = (await this.database.query(`SELECT q.id,q.title,q.category,q.difficulty,q.xp_reward,
        d.requires_verification,
        EXISTS(SELECT 1 FROM user_quests uq WHERE uq.quest_id=q.id) AS has_attempts
      FROM quest_destinations d JOIN quests q ON q.id=d.quest_id
      WHERE d.place_id=$1 ORDER BY q.title`,[id])).rows;
    return { ...place, quests };
  }

  /// Detaches a quest from its place.
  ///
  /// Without this a mis-link was permanent, and because destination
  /// assignment is blocked while a place is unpublished or unverified, a bad
  /// link could silently leave a quest unassignable with no way back. The
  /// same guard as `link` applies: a quest with attempts is not moved or
  /// detached, because discovery already counted against that place.
  async unlink(actor: string, placeId: string, questId: string) {
    return this.database.transaction(async tx => {
      const attempts = await tx.query('SELECT 1 FROM user_quests WHERE quest_id=$1 LIMIT 1',[questId]);
      if (attempts.rowCount) {
        throw new ConflictException({code:'QUEST_ALREADY_STARTED',message:'Cannot unlink a quest that already has attempts'});
      }
      const before = (await tx.query('SELECT * FROM quest_destinations WHERE quest_id=$1 AND place_id=$2',[questId,placeId])).rows[0];
      if (!before) throw new NotFoundException({code:'LINK_NOT_FOUND',message:'That quest is not linked to this place'});
      await tx.query('DELETE FROM quest_destinations WHERE quest_id=$1 AND place_id=$2',[questId,placeId]);
      await tx.query(`INSERT INTO admin_audit_log(actor_id,action,target_type,target_id,before_state)
        VALUES($1,'map.quest.unlink','quest',$2,$3::jsonb)`,[actor,questId,JSON.stringify(before)]);
      return { unlinked:true };
    });
  }

  /// Updates a place. Publishing state, coordinates and radius were fixed at
  /// creation, so a wrong coordinate could only be worked around by creating
  /// a second place — and an unpublished place cannot be corrected into a
  /// published one at all.
  async updatePlace(actor: string, id: string, input: MapPlaceUpdateDto) {
    return this.database.transaction(async tx => {
      const before = (await tx.query('SELECT * FROM map_places WHERE id=$1 FOR UPDATE',[id])).rows[0];
      if (!before) throw new NotFoundException({code:'PLACE_NOT_FOUND',message:'Place not found'});
      const row = (await tx.query(`UPDATE map_places SET
          name=COALESCE($2,name), description=COALESCE($3,description), city=COALESCE($4,city),
          category=COALESCE($5,category), latitude=COALESCE($6,latitude), longitude=COALESCE($7,longitude),
          radius_m=COALESCE($8,radius_m), is_published=COALESCE($9,is_published)
        WHERE id=$1 RETURNING *`,
      [id,input.name?.trim() ?? null,input.description?.trim() ?? null,input.city?.trim() ?? null,
       input.category ?? null,input.latitude ?? null,input.longitude ?? null,
       input.radiusM ?? null,input.isPublished ?? null])).rows[0];
      await tx.query(`INSERT INTO admin_audit_log(actor_id,action,target_type,target_id,before_state,after_state)
        VALUES($1,'map.place.update','map_place',$2,$3::jsonb,$4::jsonb)`,
      [actor,id,JSON.stringify(before),JSON.stringify(row)]);
      return row;
    });
  }

  async create(actor: string, input: MapPlaceDto) {
    return this.database.transaction(async tx => {
      await tx.query(`INSERT INTO map_countries(code,name,geometry_id) VALUES($1,$2,$3)
        ON CONFLICT(code) DO UPDATE SET name=EXCLUDED.name,geometry_id=EXCLUDED.geometry_id`,
      [input.countryCode,input.countryName.trim(),input.geometryId]);
      const row = (await tx.query(`INSERT INTO map_places(country_code,name,description,city,category,latitude,longitude,radius_m,is_published)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
      [input.countryCode,input.name.trim(),input.description.trim(),input.city.trim(),input.category,input.latitude,input.longitude,input.radiusM,input.isPublished])).rows[0];
      await tx.query(`INSERT INTO admin_audit_log(actor_id,action,target_type,target_id,after_state)
        VALUES($1,'map.place.create','map_place',$2,$3::jsonb)`,[actor,row.id,JSON.stringify(row)]);
      return row;
    });
  }

  async link(actor: string, placeId: string, input: MapQuestLinkDto) {
    return this.database.transaction(async tx => {
      const place = (await tx.query('SELECT id FROM map_places WHERE id=$1 FOR UPDATE',[placeId])).rows[0];
      const quest = (await tx.query('SELECT id FROM quests WHERE id=$1 FOR UPDATE',[input.questId])).rows[0];
      if (!place || !quest) throw new NotFoundException('Place or quest not found');
      // Reassigning a live quest would retroactively move discovery; reject it.
      const existing = await tx.query('SELECT 1 FROM user_quests WHERE quest_id=$1 LIMIT 1',[input.questId]);
      if (existing.rowCount) throw new ConflictException({code:'QUEST_ALREADY_STARTED',message:'Cannot link a quest that already has attempts'});
      await tx.query(`INSERT INTO quest_destinations(quest_id,place_id,requires_verification) VALUES($1,$2,$3)
        ON CONFLICT(quest_id) DO UPDATE SET place_id=EXCLUDED.place_id,requires_verification=EXCLUDED.requires_verification`,
      [input.questId,placeId,input.requiresVerification]);
      await tx.query(`INSERT INTO admin_audit_log(actor_id,action,target_type,target_id,after_state)
        VALUES($1,'map.quest.link','quest',$2,$3::jsonb)`,[actor,input.questId,JSON.stringify({placeId,...input})]);
      return { linked:true };
    });
  }
}
