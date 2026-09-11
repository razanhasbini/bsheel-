/**
 * SQL fragments that decide what a user may see and take on the map.
 *
 * One definition, used by the map endpoints and by quest assignment, so the
 * pin a user can see and the quest they can start can never disagree.
 *
 * Every fragment assumes the surrounding query binds the requesting user's
 * id as `$1` and aliases the place being judged as `p`.
 *
 * The model since migration 0035: a destination quest is taken like any
 * other, the geofence opens after assignment, and presence is judged at
 * submission from network evidence. Nothing here asks the network — this is
 * purely what the map reveals, which is the game's progression: an approved
 * quest at one place uncovers the hidden places around it.
 */

/** An approved destination quest at one place uncovers every hidden place within this distance of it. */
export const REVEAL_RADIUS_M = 10_000;

/** Great-circle distance in metres between `p` and the place aliased `o` (haversine, mean Earth radius). */
const distanceTo = (o: string) => `(2 * 6371000 * asin(sqrt(
  power(sin(radians(${o}.latitude - p.latitude) / 2), 2)
  + cos(radians(p.latitude)) * cos(radians(${o}.latitude))
    * power(sin(radians(${o}.longitude - p.longitude) / 2), 2))))`;

/**
 * Places where the requesting user has an approved destination submission
 * that still stands — a takedown or deletion withdraws the discovery, so a
 * revealed region can close again.
 */
export const confirmedPlaceIds = `SELECT d.place_id FROM submissions s
  JOIN user_quests uq ON uq.id = s.user_quest_id
  JOIN quest_destinations d ON d.quest_id = uq.quest_id
  WHERE s.user_id = $1 AND s.status = 'approved'
    AND s.deleted_at IS NULL AND s.visibility <> 'deleted' AND s.moderation_removed_at IS NULL`;

/** True when a confirmed discovery lies within REVEAL_RADIUS_M of `p` (a confirmed quest at `p` itself counts). */
export const revealed = `EXISTS (SELECT 1 FROM map_places o
  WHERE o.id IN (${confirmedPlaceIds}) AND ${distanceTo('o')} <= ${REVEAL_RADIUS_M})`;

/** A hidden place the user has not yet uncovered: shown as a mystery pin, name and exact position withheld. */
export const locked = `(p.category = 'hidden' AND NOT ${revealed})`;

/** What a user may open: published, and not locked. Drafts never surface publicly. */
export const visible = `(p.is_published AND NOT ${locked})`;
