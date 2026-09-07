-- ============================================================
-- MIGRATION 0012: Allow admins to insert notifications
-- Needed for announcements and admin-triggered notifications.
-- ============================================================

create policy "notifications_insert_admin" on public.notifications
  for insert with check (public.is_admin());
