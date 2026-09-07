-- ============================================================
-- MIGRATION 0085: Add reply threading to comments
--
-- Adds parent_id FK so comments can be replies to other comments.
-- Top-level comments have parent_id = NULL.
-- ============================================================

ALTER TABLE public.comments
  ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES public.comments(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_comments_parent ON public.comments(parent_id);
