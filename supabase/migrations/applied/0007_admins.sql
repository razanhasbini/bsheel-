-- ============================================================
-- MIGRATION 0007: Admins
-- Admin role assignments for moderation and quest management.
-- ============================================================

create table if not exists public.admins (
  id         uuid        primary key default gen_random_uuid(),
  user_id    uuid        unique not null references public.profiles(id) on delete cascade,
  role       text        not null default 'moderator'
                         check (role in ('super_admin', 'moderator')),
  created_at timestamptz not null default now()
);

-- Helper function to check if current user is admin
create or replace function public.is_admin()
returns boolean as $$
begin
  return exists (select 1 from public.admins where user_id = auth.uid());
end;
$$ language plpgsql security definer stable;

-- Helper function to check if current user is super_admin
create or replace function public.is_super_admin()
returns boolean as $$
begin
  return exists (select 1 from public.admins where user_id = auth.uid() and role = 'super_admin');
end;
$$ language plpgsql security definer stable;

comment on table public.admins is 'Admin role assignments. super_admin can manage admins; moderator can review submissions.';
comment on function public.is_admin() is 'Returns true if the current auth user has any admin role.';
