CREATE TABLE public.comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  submission_id UUID NOT NULL REFERENCES public.submissions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK (char_length(body) > 0 AND char_length(body) <= 500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_comments_submission ON public.comments(submission_id);
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "read_comments" ON public.comments FOR SELECT USING (true);
CREATE POLICY "insert_comments" ON public.comments FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "delete_own_comments" ON public.comments FOR DELETE USING (auth.uid() = user_id);
