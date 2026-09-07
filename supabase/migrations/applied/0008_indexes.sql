-- ============================================================
-- MIGRATION 0008: Indexes
-- Performance indexes for common query patterns.
-- ============================================================

-- Profiles
create index if not exists idx_profiles_username on public.profiles (username);
create index if not exists idx_profiles_xp_desc on public.profiles (xp desc);
create index if not exists idx_profiles_level on public.profiles (level desc);

-- Quests
create index if not exists idx_quests_active on public.quests (is_active) where is_active = true;
create index if not exists idx_quests_category on public.quests (category);
create index if not exists idx_quests_difficulty on public.quests (difficulty);

-- User quests
create index if not exists idx_user_quests_user_id on public.user_quests (user_id);
create index if not exists idx_user_quests_quest_id on public.user_quests (quest_id);
create index if not exists idx_user_quests_status on public.user_quests (status);
create index if not exists idx_user_quests_expires_at on public.user_quests (expires_at)
  where status = 'assigned';

-- Submissions
create index if not exists idx_submissions_user_id on public.submissions (user_id);
create index if not exists idx_submissions_user_quest_id on public.submissions (user_quest_id);
create index if not exists idx_submissions_status on public.submissions (status);
create index if not exists idx_submissions_pending on public.submissions (submitted_at desc)
  where status = 'pending';
create index if not exists idx_submissions_approved_feed on public.submissions (submitted_at desc)
  where status = 'approved';

-- Reactions
create index if not exists idx_reactions_submission_id on public.reactions (submission_id);
create index if not exists idx_reactions_user_id on public.reactions (user_id);

-- Notifications
create index if not exists idx_notifications_user_id on public.notifications (user_id);
create index if not exists idx_notifications_unread on public.notifications (user_id, created_at desc)
  where is_read = false;
create index if not exists idx_notifications_created_at on public.notifications (created_at desc);
