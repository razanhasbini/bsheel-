-- ============================================================
-- MIGRATION 0014: Add 'mixed' media type for submissions
-- Allows submissions with both images and videos.
-- ============================================================

alter table public.submissions drop constraint submissions_media_type_check;
alter table public.submissions add constraint submissions_media_type_check
  check (media_type in ('image', 'video', 'mixed'));
