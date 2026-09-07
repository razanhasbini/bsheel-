-- Add UPDATE policy for comments (users can edit their own comments)
CREATE POLICY "update_own_comments" ON public.comments
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
