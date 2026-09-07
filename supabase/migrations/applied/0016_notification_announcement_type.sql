-- ============================================================
-- MIGRATION 0013: Add 'announcement' notification type
-- ============================================================

alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in ('quest_assigned', 'submission_approved', 'submission_rejected', 'reaction_received', 'level_up', 'announcement'));
