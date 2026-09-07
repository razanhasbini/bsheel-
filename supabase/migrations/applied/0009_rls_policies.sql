-- ============================================================
-- MIGRATION 0009: Row Level Security Policies
-- Enforces access control at the database level.
-- ============================================================

-- Enable RLS on all tables
alter table public.profiles enable row level security;
alter table public.quests enable row level security;
alter table public.user_quests enable row level security;
alter table public.submissions enable row level security;
alter table public.reactions enable row level security;
alter table public.notifications enable row level security;
alter table public.admins enable row level security;

-- ==================== PROFILES ====================

-- Everyone can view profiles (public leaderboard, feed attribution)
create policy "profiles_select_all" on public.profiles
  for select using (true);

-- Users can insert their own profile (handled by trigger, but allows manual)
create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = id);

-- Users can update their own profile
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id)
  with check (auth.uid() = id);

-- Admins can update any profile (e.g., ban, reset XP)
create policy "profiles_update_admin" on public.profiles
  for update using (public.is_admin());

-- ==================== QUESTS ====================

-- Everyone can view active quests
create policy "quests_select_active" on public.quests
  for select using (is_active = true);

-- Admins can see all quests (including inactive)
create policy "quests_select_admin" on public.quests
  for select using (public.is_admin());

-- Admins can insert/update/delete quests
create policy "quests_insert_admin" on public.quests
  for insert with check (public.is_admin());

create policy "quests_update_admin" on public.quests
  for update using (public.is_admin());

create policy "quests_delete_admin" on public.quests
  for delete using (public.is_super_admin());

-- ==================== USER QUESTS ====================

-- Users can view their own quests
create policy "user_quests_select_own" on public.user_quests
  for select using (user_id = auth.uid());

-- Admins can view all user quests
create policy "user_quests_select_admin" on public.user_quests
  for select using (public.is_admin());

-- Users can insert their own quest assignments (or via RPC)
create policy "user_quests_insert_own" on public.user_quests
  for insert with check (user_id = auth.uid());

-- Only system (triggers/RPC) should update user_quests, but allow admin
create policy "user_quests_update_admin" on public.user_quests
  for update using (public.is_admin());

-- ==================== SUBMISSIONS ====================

-- Users can view their own submissions
create policy "submissions_select_own" on public.submissions
  for select using (user_id = auth.uid());

-- Approved submissions are visible to all (public feed)
create policy "submissions_select_approved" on public.submissions
  for select using (status = 'approved');

-- Admins can view all submissions (moderation queue)
create policy "submissions_select_admin" on public.submissions
  for select using (public.is_admin());

-- Users can create their own submissions
create policy "submissions_insert_own" on public.submissions
  for insert with check (user_id = auth.uid());

-- Only admins can update submissions (approve/reject)
create policy "submissions_update_admin" on public.submissions
  for update using (public.is_admin());

-- ==================== REACTIONS ====================

-- Everyone can view reactions (shown on feed posts)
create policy "reactions_select_all" on public.reactions
  for select using (true);

-- Users can add reactions
create policy "reactions_insert_own" on public.reactions
  for insert with check (user_id = auth.uid());

-- Users can remove their own reactions
create policy "reactions_delete_own" on public.reactions
  for delete using (user_id = auth.uid());

-- ==================== NOTIFICATIONS ====================

-- Users can only view their own notifications
create policy "notifications_select_own" on public.notifications
  for select using (user_id = auth.uid());

-- Users can update their own notifications (mark read)
create policy "notifications_update_own" on public.notifications
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- System inserts notifications via triggers (service role bypasses RLS)

-- ==================== ADMINS ====================

-- Only admins can view the admin table
create policy "admins_select_admin" on public.admins
  for select using (public.is_admin());

-- Only super_admins can manage admin roles
create policy "admins_insert_super" on public.admins
  for insert with check (public.is_super_admin());

create policy "admins_update_super" on public.admins
  for update using (public.is_super_admin());

create policy "admins_delete_super" on public.admins
  for delete using (public.is_super_admin());
