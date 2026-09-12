import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { MapMomentsQueryDto, MapPlaceDto, MapPlaceUpdateDto, MapQueryDto, MapQuestLinkDto } from '../presentation/map.dto.js';
import { confirmedPlaceIds, locked, visible } from './map-visibility.sql.js';
import { submissionSocialRank } from '../../../common/ranking/social-rank.sql.js';

// A locked pin still marks the area — that is the invitation to go and earn
// it — but not the spot: two decimals is roughly a kilometre, wider than
// any geofence radius the schema allows.
/// Whether a hidden quest has opened for this viewer.
///
/// Both mechanisms count, and they are separate by design: discovery owns
/// generic hidden unlocks, journeys own stage unlocks. `$1` is the viewer.
/// Kept identical to the gate in quests.repository.assignSpecific — a map
/// that offers what the assign endpoint refuses is confusing, and a map
/// that reveals what it should withhold is worse.
const hiddenVisible = `(NOT q.is_hidden
  OR EXISTS (SELECT 1 FROM user_quest_unlocks u WHERE u.quest_id=q.id AND u.user_id=$1)
  OR EXISTS (SELECT 1 FROM journey_stage_unlocks j JOIN quest_chain_runs r ON r.id=j.chain_run_id
             WHERE j.quest_id=q.id AND j.target_user_id=$1 AND r.status='active'))`;

const blurred = (column: string) => `CASE WHEN ${locked} THEN round(p.${column}::numeric, 2)::double precision ELSE p.${column} END`;

/**
 * How many moments one place may contribute to the map layer.
 *
 * Two, and the rest are counted rather than drawn — the Snap/Instagram-map
 * shape. A landmark with two hundred completions gets two tiles and a
 * "+198 more", which is both the honest summary and the thing that keeps
 * every other place on the board visible. Opening the place is where the
 * full set lives.
 *
 * Two rather than one because one defeats the layer's own scatter: a single
 * tile per place can never overlap another from the same place, so the
 * offset logic the client spent effort on was dead code in production, and
 * a busy landmark looked exactly as active as a place one person had ever
 * visited. Two is the smallest number that shows a place is busier than
 * another without turning the board into the feed.
 */
const MOMENTS_PER_PLACE = 2;

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

  /// Every published place, locked ones included.
  ///
  /// A locked place is a hidden one the user has not uncovered yet. It is
  /// returned so the map can draw the mystery pin that makes the region worth
  /// exploring, but with its name, description and city withheld and its
  /// position blurred, and it never matches a text search — searching for a
  /// secret by name would otherwise confirm it exists.
  async places(userId: string, query: MapQueryDto) {
    return (await this.database.query(`SELECT p.id,p.country_code,p.category,p.radius_m,p.is_published,p.created_at,
      c.name AS country_name,c.geometry_id,
      ${locked} AS locked,
      CASE WHEN ${locked} THEN 'Locked location' ELSE p.name END AS name,
      CASE WHEN ${locked} THEN '' ELSE p.description END AS description,
      CASE WHEN ${locked} THEN '' ELSE p.city END AS city,
      ${blurred('latitude')} AS latitude,
      ${blurred('longitude')} AS longitude,
      EXISTS (SELECT 1 FROM saved_map_places b WHERE b.user_id=$1 AND b.place_id=p.id) AS saved,
      CASE WHEN ${locked} THEN 0 ELSE (SELECT count(*)::int FROM quest_destinations d JOIN quests q ON q.id=d.quest_id
        WHERE d.place_id=p.id AND q.is_active AND ${hiddenVisible}) END AS quest_count,
      -- The newest approved, feed-visible proof at the place: the pin's photo
      -- snippet. Withheld while locked, like everything else about it.
      CASE WHEN ${locked} THEN NULL ELSE (SELECT s.media_url FROM quest_destinations d
        JOIN user_quests uq ON uq.quest_id=d.quest_id JOIN submissions s ON s.user_quest_id=uq.id
        WHERE d.place_id=p.id AND s.status='approved' AND s.show_in_feed AND s.visibility='visible'
          AND s.deleted_at IS NULL AND s.moderation_removed_at IS NULL
        ORDER BY s.submitted_at DESC LIMIT 1) END AS cover_media_url,
      EXISTS (SELECT 1 FROM quest_destinations d JOIN user_quests uq ON uq.quest_id=d.quest_id
        JOIN submissions s ON s.user_quest_id=uq.id WHERE d.place_id=p.id AND s.user_id=$1
        AND s.status IN ('pending','approved') AND s.deleted_at IS NULL AND s.visibility <> 'deleted'
        AND s.moderation_removed_at IS NULL) AS discovered,
      p.id IN (${confirmedPlaceIds}) AS confirmed
      FROM map_places p JOIN map_countries c ON c.code=p.country_code
      WHERE p.is_published AND ($2::text IS NULL OR p.country_code=$2)
        AND (NOT $7::boolean OR EXISTS(SELECT 1 FROM saved_map_places b WHERE b.user_id=$1 AND b.place_id=p.id))
        AND ($3::text IS NULL OR p.category=$3)
        AND ($4::text='' OR (NOT ${locked} AND position(lower($4) in lower(p.name || ' ' || p.city || ' ' || c.name))>0))
      ORDER BY p.name,p.id LIMIT $5 OFFSET $6`,
    [userId, query.country ?? null, query.category ?? null, query.search?.trim() ?? '', query.limit, query.offset,query.saved==='true'])).rows;
  }

  /// Recent proof, pinned where it happened — the map's "moments" layer.
  ///
  /// Snap/Instagram-map shaped, and built from the feed rather than beside
  /// it: every row here is an approved submission that is already public on
  /// the feed, at a place the viewer may see. It adds no new visibility —
  /// the predicate is the feed's, plus the map's own locked-place rule —
  /// which is what makes showing somebody's face on a map defensible. A
  /// private, rejected, deleted or moderator-removed submission is not a
  /// moment, and neither is one from a blocked account in either direction.
  ///
  /// **The coordinate is the place's, not the person's.** Bsheel does not
  /// store where a photograph was taken; it stores which place the quest
  /// belonged to. Returning the place's own point (and its radius, so the
  /// client can scatter the tiles inside it rather than stack them) keeps
  /// the claim exactly as strong as the evidence: a moment says "this
  /// happened at Baalbek", never "this happened at 34.0069, 36.2039". The
  /// alternative — reading a coordinate out of `network_evidence` — would
  /// publish the output of telecom verification somebody consented to for
  /// one quest, which is not what they agreed to.
  ///
  /// **It is a sample, not the feed on a map.** Two things are cut, and both
  /// of them deliberately:
  ///
  /// - **Hidden quests never appear.** A later stage of a journey, or a
  ///   quest that unlocks by reaching somewhere, is content the player is
  ///   supposed to discover. A tile of somebody else completing it gives
  ///   away that it exists, roughly where it is and what it involves — which
  ///   is the game's whole surprise, spent by a photograph. `is_hidden` is
  ///   excluded outright rather than filtered per viewer, because "you have
  ///   unlocked it, so you may see other people's" is a rule that leaks the
  ///   moment it is slightly wrong. (A locked *place* is already excluded by
  ///   `visible`; this is the quest-level equivalent.)
  /// - **At most MOMENTS_PER_PLACE per place.** A landmark with two hundred
  ///   completions would otherwise bury every other place on the board and
  ///   turn the map into the feed. A couple of tiles says "people have been
  ///   here"; two hundred says nothing extra and hides the rest of the
  ///   country. The place's own sheet is where the full set lives.
  ///
  /// Newest first within a place and overall, bounded. `media_url` is a raw
  /// object key: the client signs it exactly as the feed does.
  async moments(userId: string, query: MapMomentsQueryDto) {
    // The place is aliased p because every fragment in map-visibility.sql
    // is written against that name.
    return (await this.database.query(`WITH visible_moments AS (
        SELECT s.id, s.media_url, s.media_type::text AS media_type,
          -- A still cut from the video, when one has been made. Signed by the
          -- client exactly like media_url, and authorised by the same rule:
          -- it is linked to this submission, so it is precisely as visible.
          s.poster_object_key AS poster_url,
          s.submitted_at, s.net_score, s.caption,
          q.id AS quest_id, q.title AS quest_title, q.category AS quest_category,
          p.id AS place_id, p.name AS place_name, p.city, p.country_code, p.radius_m,
          p.latitude, p.longitude,
          pr.id AS user_id, pr.username::text AS username, pr.avatar_url,
          row_number() OVER (PARTITION BY p.id ORDER BY s.submitted_at DESC, s.id DESC) AS place_rank,
          -- Where this country sits in its own recency order. Used only to
          -- interleave the result below, never to filter.
          row_number() OVER (PARTITION BY p.country_code ORDER BY s.submitted_at DESC, s.id DESC) AS country_rank,
          -- Everything else standing at this place. Drawn as "+N more" on
          -- the tile rather than as N more tiles.
          count(*) OVER (PARTITION BY p.id) - ${MOMENTS_PER_PLACE} AS more_count,
          -- How many quests are on offer here, so the tile can say there is
          -- something to DO and not only something to look at. This is the
          -- point of the layer: a photograph is an invitation to a quest.
          (SELECT count(*)::int FROM quest_destinations qd JOIN quests oq ON oq.id = qd.quest_id
            WHERE qd.place_id = p.id AND oq.is_active AND NOT oq.is_hidden
              AND (oq.available_from IS NULL OR oq.available_from <= now())
              AND (oq.available_until IS NULL OR oq.available_until > now())) AS quest_count
        FROM submissions s
        JOIN user_quests uq ON uq.id = s.user_quest_id
        JOIN quests q ON q.id = uq.quest_id
        JOIN quest_destinations d ON d.quest_id = q.id
        JOIN map_places p ON p.id = d.place_id
        JOIN profiles pr ON pr.id = s.user_id
        JOIN users u ON u.id = s.user_id
        WHERE s.status = 'approved' AND s.show_in_feed AND s.visibility = 'visible'
          AND s.deleted_at IS NULL AND s.moderation_removed_at IS NULL
          AND u.status = 'active' AND u.deleted_at IS NULL
          AND NOT q.is_hidden
          AND ${visible}
          AND ($2::text IS NULL OR p.country_code = $2)
          AND NOT EXISTS (SELECT 1 FROM blocked_users b
            WHERE (b.blocker_id = $1 AND b.blocked_id = s.user_id)
               OR (b.blocker_id = s.user_id AND b.blocked_id = $1))
      )
      SELECT id, media_url, media_type, poster_url, submitted_at, net_score, caption,
        quest_id, quest_title, quest_category, place_id, place_name, city,
        country_code, radius_m, latitude, longitude, user_id, username,
        avatar_url, GREATEST(more_count, 0)::int AS more_count, quest_count
      FROM visible_moments
      WHERE place_rank <= ${MOMENTS_PER_PLACE}
      -- Interleaved, not simply newest-first, and this is the difference
      -- between a map of the whole board and a map of wherever happened to
      -- be busy last week.
      --
      -- ORDER BY submitted_at DESC LIMIT n spends the entire budget on the
      -- most recent submissions, and recency clusters: a country that ran an
      -- event, or a landmark somebody posted six clips from, takes every
      -- tile and the other ten countries draw nothing. The layer is a SAMPLE
      -- of what is happening on the board, so the sample has to be spread
      -- over the board.
      --
      -- Taking place_rank first gives every place its first piece of proof
      -- before any place gets a second; country_rank next rotates between
      -- countries rather than draining one; recency only breaks the tie.
      -- The result is still every row's genuine submitted_at — nothing is
      -- reordered in time, only chosen more evenly.
      ORDER BY place_rank, country_rank, submitted_at DESC, id DESC
      LIMIT $3`, [userId, query.country ?? null, query.limit])).rows;
  }

  async detail(userId: string, id: string) {
    const place = (await this.database.query(`SELECT p.*, p.id IN (${confirmedPlaceIds}) AS confirmed
      FROM map_places p WHERE p.id=$2 AND ${visible}`, [userId,id])).rows[0];
    if (!place) throw new NotFoundException({ code:'PLACE_NOT_FOUND',message:'Place not found' });
    // Every quest at a visible place can be started. `requires_verification`
    // says whether the network will be asked to confirm presence when the
    // proof comes in (migration 0035); it no longer locks the door.
    const quests = (await this.database.query(`SELECT q.id,q.title,q.description,q.category,q.difficulty,
      q.duration_hours,q.xp_reward,d.requires_verification,true AS unlocked
      FROM quest_destinations d JOIN quests q ON q.id=d.quest_id
      WHERE d.place_id=$2 AND q.is_active AND ${hiddenVisible}
      ORDER BY q.title,q.id`, [userId,id])).rows;
    // Every kind of proof standing here, not only the videos.
    //
    // This is what the map tile's "+N more" opens into, so it has to be the
    // whole set a person can see — restricting it to video hid most of it
    // and left the sheet showing play buttons for a place whose proof was
    // mostly photographs. Hidden quests are excluded for the same reason
    // they are excluded from the map: a later stage of a journey is content
    // the player is meant to discover, and a picture of somebody finishing
    // it gives that away.
    const previews = (await this.database.query(`SELECT s.id,s.user_id,p.username::text,s.media_type::text AS media_type,s.submitted_at,s.media_url,
        q.id AS quest_id, q.title AS quest_title
      FROM submissions s JOIN user_quests uq ON uq.id=s.user_quest_id
      JOIN quests q ON q.id=uq.quest_id
      JOIN quest_destinations d ON d.quest_id=uq.quest_id JOIN profiles p ON p.id=s.user_id
      JOIN users u ON u.id=s.user_id
      WHERE d.place_id=$2 AND s.status='approved' AND NOT q.is_hidden
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

  /// The one authoritative exploration model, for the map and the profile.
  ///
  /// A place counts as explored once the user has an approved destination
  /// submission there that still stands — the same predicate as the reveal
  /// rule. Unique places, so completing one place twice moves nothing;
  /// pending and rejected proof move nothing; a quest with no destination
  /// moves nothing. World is explored places over every published place.
  async progress(userId: string) {
    const rows = (await this.database.query(`
      SELECT c.code AS country_code, c.name, c.geometry_id,
        count(p.id)::int AS total_places,
        count(p.id) FILTER (WHERE p.id IN (${confirmedPlaceIds}))::int AS explored_places,
        count(p.id) FILTER (WHERE p.id NOT IN (${confirmedPlaceIds}) AND EXISTS (
          SELECT 1 FROM quest_destinations d JOIN user_quests uq ON uq.quest_id=d.quest_id
          JOIN submissions s ON s.user_quest_id=uq.id
          WHERE d.place_id=p.id AND s.user_id=$1 AND s.status='pending'
            AND s.deleted_at IS NULL AND s.visibility <> 'deleted' AND s.moderation_removed_at IS NULL))::int AS pending_places
      FROM map_countries c LEFT JOIN map_places p ON p.country_code=c.code AND p.is_published
      GROUP BY c.code ORDER BY c.name`, [userId])).rows as {
        country_code: string; name: string; geometry_id: string;
        total_places: number; explored_places: number; pending_places: number;
      }[];
    const percentage = (explored: number, total: number) => total === 0 ? 0 : Math.round((explored / total) * 1000) / 10;
    const totalPlaces = rows.reduce((n, r) => n + r.total_places, 0);
    const exploredPlaces = rows.reduce((n, r) => n + r.explored_places, 0);
    return {
      world: { exploredPlaces, totalPlaces, percentage: percentage(exploredPlaces, totalPlaces) },
      countries: rows.map(r => ({
        countryCode: r.country_code, name: r.name, geometryId: r.geometry_id,
        exploredPlaces: r.explored_places, pendingPlaces: r.pending_places, totalPlaces: r.total_places,
        percentage: percentage(r.explored_places, r.total_places),
      })),
    };
  }

  /// What one country has to offer the requesting user — browsable from
  /// anywhere; being there is never required to look.
  ///
  /// Trending reuses the feed's hot signal (net score decayed by age) over
  /// each quest's approved proof, plus completions, BSHEEEL saves and
  /// comments. Discovery is a deterministic daily shuffle of the rest, so the
  /// same few viral quests do not own the map forever. Both draw only from
  /// active quests at places the user may see; `is_hidden` quests and locked
  /// places are counted, never described.
  async discover(userId: string, code: string) {
    const country = (await this.database.query(`
      SELECT c.code, c.name, c.geometry_id,
        count(p.id)::int AS total_places,
        count(p.id) FILTER (WHERE p.id IN (${confirmedPlaceIds}))::int AS explored_places,
        count(p.id) FILTER (WHERE ${locked})::int AS locked_places
      FROM map_countries c LEFT JOIN map_places p ON p.country_code=c.code AND p.is_published
      WHERE c.code=$2 GROUP BY c.code`, [userId, code])).rows[0];
    if (!country) throw new NotFoundException({ code:'COUNTRY_NOT_FOUND', message:'Country not found' });

    const standing = `s.deleted_at IS NULL AND s.visibility <> 'deleted' AND s.moderation_removed_at IS NULL`;
    const quests = (await this.database.query(`
      WITH candidates AS (
        SELECT q.id, q.title, q.category, q.difficulty, q.xp_reward, q.duration_hours,
          d.requires_verification, p.id AS place_id, p.name AS place_name, p.city, p.latitude, p.longitude
        FROM quest_destinations d JOIN quests q ON q.id=d.quest_id JOIN map_places p ON p.id=d.place_id
        WHERE p.country_code=$2 AND ${visible} AND q.is_active AND NOT q.is_hidden
          AND (q.available_from IS NULL OR q.available_from <= now())
          AND (q.available_until IS NULL OR q.available_until > now())
      ), scored AS (
        SELECT c.*,
          -- A quest trends by the sum of its approved posts' social score —
          -- the SAME score the feed ranks those posts by (common/ranking) —
          -- plus a flat 1.5 per completion, so a place people actually go
          -- to outranks one they only argue about.
          (SELECT COALESCE(sum(${submissionSocialRank('s', 'now()')}), 0)
             + 1.5 * count(*) FILTER (WHERE s.status='approved')
           FROM submissions s JOIN user_quests uq ON uq.id=s.user_quest_id
           WHERE uq.quest_id=c.id AND s.status='approved' AND ${standing}) AS engagement,
          (SELECT count(*)::int FROM saved_quests sq WHERE sq.quest_id=c.id) AS saves,
          (SELECT count(*)::int FROM submissions s JOIN user_quests uq ON uq.id=s.user_quest_id
             WHERE uq.quest_id=c.id AND s.status='approved' AND ${standing}) AS completions,
          (SELECT s.media_url FROM submissions s JOIN user_quests uq ON uq.id=s.user_quest_id
             WHERE uq.quest_id=c.id AND s.status='approved' AND s.show_in_feed AND ${standing}
             ORDER BY s.submitted_at DESC LIMIT 1) AS cover_media_url,
          EXISTS (SELECT 1 FROM submissions s JOIN user_quests uq ON uq.id=s.user_quest_id
             WHERE uq.quest_id=c.id AND s.user_id=$1 AND s.status='approved' AND ${standing}) AS completed,
          EXISTS (SELECT 1 FROM saved_quests sq WHERE sq.quest_id=c.id AND sq.user_id=$1) AS saved
        FROM candidates c
      )
      SELECT *, (engagement + 2 * saves) AS score,
        md5(id::text || current_date::text) AS shuffle
      FROM scored`, [userId, code])).rows as Record<string, unknown>[];

    const byScore = [...quests].sort((a, b) => Number(b.score) - Number(a.score));
    const trending = byScore.filter(q => Number(q.score) > 0).slice(0, 5);
    const taken = new Set(trending.map(q => q.id));
    const discovery = quests.filter(q => !taken.has(q.id))
      .sort((a, b) => String(a.shuffle).localeCompare(String(b.shuffle))).slice(0, 5);
    const hiddenQuests = (await this.database.query(`
      SELECT count(*)::int AS n FROM quest_destinations d JOIN quests q ON q.id=d.quest_id
      JOIN map_places p ON p.id=d.place_id WHERE p.country_code=$1 AND p.is_published AND q.is_active AND q.is_hidden`, [code])).rows[0].n as number;

    const collections = (await this.database.query(`
      SELECT col.id, col.name, col.description,
        count(i.quest_id)::int AS total,
        count(i.quest_id) FILTER (WHERE EXISTS (
          SELECT 1 FROM submissions s JOIN user_quests uq ON uq.id=s.user_quest_id
          WHERE uq.quest_id=i.quest_id AND s.user_id=$1 AND s.status='approved' AND ${standing}))::int AS completed
      FROM quest_collections col LEFT JOIN quest_collection_items i ON i.collection_id=col.id
      WHERE col.country_code=$2 AND col.is_published
      GROUP BY col.id ORDER BY col.name`, [userId, code])).rows;

    const strip = (q: Record<string, unknown>) => {
      const { engagement: _e, shuffle: _s, ...rest } = q;
      return rest;
    };
    const total = Number(country.total_places), explored = Number(country.explored_places);
    return {
      country: {
        code: country.code, name: country.name, geometryId: country.geometry_id,
        totalPlaces: total, exploredPlaces: explored,
        percentage: total === 0 ? 0 : Math.round((explored / total) * 1000) / 10,
      },
      trending: trending.map(strip),
      discovery: discovery.map(strip),
      hiddenCount: Number(country.locked_places) + hiddenQuests,
      collections,
    };
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
