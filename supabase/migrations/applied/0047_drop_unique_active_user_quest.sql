-- Migration 0047: Drop the unique_active_user_quest constraint.
-- This constraint on (user_id, quest_id, status) prevents re-assigning a quest
-- the user previously had with the same status (e.g. assigned -> expired -> assigned again).
-- The RPC functions already enforce one-active-quest-per-user logic,
-- and the idx_one_active_quest_per_user index (on status='assigned') handles the real guard.

ALTER TABLE public.user_quests DROP CONSTRAINT IF EXISTS unique_active_user_quest;
