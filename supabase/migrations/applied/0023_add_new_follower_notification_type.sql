-- Add 'new_follower' to the notifications type check constraint
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (type IN ('quest_assigned', 'submission_approved', 'submission_rejected', 'reaction_received', 'level_up', 'announcement', 'new_follower'));
