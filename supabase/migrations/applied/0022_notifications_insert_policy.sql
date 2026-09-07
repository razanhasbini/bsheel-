-- Allow authenticated users to insert notifications for other users
-- (needed for follow/reaction notifications sent from the client)
CREATE POLICY "authenticated_users_can_notify"
  ON public.notifications
  FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);
