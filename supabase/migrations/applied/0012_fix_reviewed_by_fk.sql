-- ============================================================
-- MIGRATION 0012: Fix reviewed_by FK constraint
-- Adds ON DELETE SET NULL to submissions.reviewed_by foreign key.
-- ============================================================

-- Drop the existing FK and re-add with ON DELETE SET NULL
alter table public.submissions
  drop constraint if exists submissions_reviewed_by_fkey;

alter table public.submissions
  add constraint submissions_reviewed_by_fkey
  foreign key (reviewed_by) references public.profiles(id) on delete set null;

-- Ensure reviewed_by and reviewed_at are consistent
alter table public.submissions
  add constraint reviewed_fields_consistent
  check (
    (reviewed_by is null and reviewed_at is null)
    or (reviewed_by is not null and reviewed_at is not null)
  );
