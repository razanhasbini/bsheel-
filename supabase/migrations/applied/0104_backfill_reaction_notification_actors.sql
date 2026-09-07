-- ============================================================
-- MIGRATION 0104: Backfill actor_id for old reaction notifications
-- (imported from PR #30, originally authored as 0095)
--
-- Older reaction notifications were created before notifications.actor_id was
-- stored. This best-effort backfill links old reaction_received rows to the
-- reacting profile by matching:
--   1. same submission reference_id
--   2. notification recipient is not the reactor
--   3. notification body starts with the reactor's display name or username
--
-- Rows with generic/renamed/ambiguous text stay NULL rather than guessing.
-- ============================================================

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS actor_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

WITH candidates AS (
  SELECT
    n.id AS notification_id,
    r.user_id AS actor_id,
    row_number() OVER (
      PARTITION BY n.id
      ORDER BY abs(extract(epoch FROM (n.created_at - r.created_at)))
    ) AS rn
  FROM public.notifications n
  JOIN public.reactions r
    ON n.reference_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   AND r.submission_id = n.reference_id::uuid
   AND r.user_id <> n.user_id
  JOIN public.profiles p
    ON p.id = r.user_id
  WHERE n.type = 'reaction_received'
    AND n.actor_id IS NULL
    AND (
      (p.display_name IS NOT NULL AND p.display_name <> '' AND n.body ILIKE p.display_name || ' %')
      OR (p.username IS NOT NULL AND p.username <> '' AND n.body ILIKE p.username || ' %')
      OR (p.username IS NOT NULL AND p.username <> '' AND n.body ILIKE '@' || p.username || ' %')
    )
)
UPDATE public.notifications n
   SET actor_id = c.actor_id
  FROM candidates c
 WHERE n.id = c.notification_id
   AND c.rn = 1;
